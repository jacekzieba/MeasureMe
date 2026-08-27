// BodyMeshDeformer.swift
//
// **BodyMeshDeformer**
// Applies the solver's circumferences to the base mesh.
//
// **Responsibilities:**
// - Turning each band's target circumference into a radial scale factor
// - Scaling every vertex about its band's centroid, feathered between bands
// - Leaving the head, hands and feet at their baked proportions
//
// **Why the offset is split along and around the bone:**
// Only the component perpendicular to the bone is scaled. Scaling the whole
// offset would make a thicker waist a longer one as well, and would drag the
// shoulders upward as the chest grew.
//
// **Why this satisfies the round-trip criterion by construction:**
// Scaling a planar set radially about a fixed centre by `s` multiplies every
// pairwise distance by `s`, so its convex hull perimeter — the tape-measure
// reading — is multiplied by exactly `s`. With `s = target / base` the band
// measures `target`. The only residual comes from feathering `s` between
// bands, which is what the 1% tolerance absorbs.
//
import Foundation
import simd

nonisolated enum BodyMeshDeformer {
    static func deform(
        mesh: BodyBaseMesh,
        map: BodyRegionMap,
        profile: [BodyRegion: [BodyBand]],
        parameters: BodyMeshParameters
    ) -> [SIMD3<Float>] {
        let stature = Float(parameters.heightCm / 100)
        let factors = scaleFactors(parameters: parameters, profile: profile)

        /// Where one region alone would put this vertex. Returns nil when the
        /// region carries no measurement, so the caller can fall back.
        ///
        /// Interpolates on the vertex's own projection onto the region axis, so
        /// every vertex in a cross-section perpendicular to that axis gets the
        /// same factor and the same centre. That is what makes the section a
        /// uniform planar scaling, and so its tape reading exactly `factor`
        /// times the base.
        func placed(_ base: SIMD3<Float>, in region: BodyRegion) -> SIMD3<Float>? {
            guard region.isMeasured,
                  let bands = profile[region], bands.count > 1,
                  let regionFactors = factors[region]
            else { return nil }

            let axis = bands[0].axis
            let u = simd_dot(base, axis)

            var lower = 0
            while lower < bands.count - 2 && bands[lower + 1].position < u { lower += 1 }
            let span = bands[lower + 1].position - bands[lower].position
            let step = span > 0 ? min(max((u - bands[lower].position) / span, 0), 1) : 0

            // Smoothstepped, not linear. A linear blend is continuous but its
            // slope jumps at every band, and a slope jump on a surface is a
            // crease: eight bands left eight faint rings around the torso,
            // clearest across a heavy back. Smoothstep matches the factor
            // exactly at each band and flattens the join between them.
            let eased = step * step * (3 - 2 * step)
            let centroid = bands[lower].centroid
                + (bands[lower + 1].centroid - bands[lower].centroid) * eased
            let factor = regionFactors[lower]
                + (regionFactors[lower + 1] - regionFactors[lower]) * eased

            let offset = base - centroid
            let alongAxis = simd_dot(offset, axis) * axis
            return centroid + alongAxis + (offset - alongAxis) * factor
        }

        var positions = mesh.positions.indices.map { index -> SIMD3<Float> in
            let base = mesh.positions[index]
            let region = map.region[index]

            // An unmeasured region never moves at all: the head, hands and feet
            // ride the stature scale and nothing else.
            guard region.isMeasured else { return base }

            let primary = placed(base, in: region) ?? base
            let weight = map.blend[index]
            // Below this the second region contributes nothing visible, and
            // skipping it keeps the interior of every region exact.
            guard weight > 0.001 else { return primary }

            // Where the neighbour is unmeasured, `placed` yields the vertex
            // untouched, so blending feathers this region's factor down toward
            // 1 as it approaches the neck, wrist or ankle. Doing it on the
            // measured side only is what keeps the transition continuous
            // without moving the head: without it a torso vertex at the neck
            // scaled by 1.53 sat against a head vertex at 1.0 and stretched
            // their shared edge 4.5x.
            let other = placed(base, in: map.secondary[index]) ?? base
            return primary + (other - primary) * weight
        }

        // Shape first, across the whole body, then size. A projection needs a
        // long, gentle envelope — the belly's runs from mid-pelvis to the chest
        // — while a girth band needs a short one that clears its neighbours'
        // landmarks. Doing both inside one band forced the projection through
        // the girth band's 4 cm ramp and put a hard ledge across the abdomen.
        for projection in ForwardProjection.all {
            applyForwardProjection(projection, to: &positions, map: map, parameters: parameters)
        }
        for girth in LateralGirth.all {
            applyLateralGirth(girth, to: &positions, map: map, parameters: parameters)
        }

        // Last, because the bands above spill onto the limbs and the limb's own
        // measurement outranks that spill.
        restoreLimbGirths(&positions, mesh: mesh, map: map, profile: profile, parameters: parameters)

        return positions.map { $0 * stature }
    }

    // MARK: - Hips and shoulders

    /// A girth the region pass cannot carry, applied afterwards as a plain
    /// horizontal scale over a band of heights.
    ///
    /// **Why these two are not band anchors.** Both tapes enclose more than one
    /// region, and their widest points belong to the *other* one: the hip tape
    /// is pinned by the greater trochanters, which the map assigns to the
    /// thighs, and the shoulder tape by the deltoids, which it assigns to the
    /// arms. Scaling the torso alone therefore moved about a tenth of the tape
    /// — measured at +0.4 cm for a +3 cm target — while stepping away from the
    /// limb beside it by up to 23.7 mm. Both numbers get worse the further the
    /// measurement is from the bake.
    ///
    /// **Why this cannot seam.** The scale is a function of height alone,
    /// applied to every vertex regardless of region, so there is no boundary
    /// for it to be discontinuous across. Scaling a planar set about a fixed
    /// point multiplies every pairwise distance by the factor, so on the
    /// plateau the tape reading is multiplied by exactly that factor and the
    /// measurement is hit, not approached.
    ///
    /// **Why the plateaus are where they are.** The measuring slab has to sit
    /// wholly inside the plateau, or the scale is not uniform across it and the
    /// target is undershot — that alone cost the shoulders 5%. The fades then
    /// have to be long enough that no two neighbouring vertices land on very
    /// different weights, because that difference is a ledge: a 4 cm ramp under
    /// the buttocks put a 69 mm shelf on a 132 cm hip, which rendered as a
    /// bustle. Twelve centimetres of ramp reaching down the femur is what
    /// removes it.
    ///
    /// **The cost of that long lower ramp, stated plainly.** The hips now
    /// widen the upper thigh as well, so a body asking for 132 cm hips and
    /// 58 cm thighs renders thighs above 58 at the crotch. That is the honest
    /// trade: the alternative is a shelf, and the two measurements genuinely
    /// describe overlapping flesh. The thigh's own read still governs the
    /// leg's girth from mid-femur down, where the ramp has died out.
    ///
    /// Upward, each band still has to clear the measurement above it: the hips
    /// end at 0.615 against a waist at 0.630, the shoulders start at 0.715
    /// against a chest at 0.720. The shoulder band also has to die by the neck
    /// joint at 0.860, or it starts widening the jaw — it reached 5.2 mm into
    /// the skull when it ran to 0.885.
    struct LateralGirth {
        let landmark: BodyLandmark
        /// Heights over which the scale ramps in, holds, and ramps out.
        let fadeIn: ClosedRange<Float>
        let plateau: ClosedRange<Float>
        let fadeOut: ClosedRange<Float>
        /// How the arm chain takes part.
        ///
        /// The shoulders need it whole — the deltoids are what the tape reads.
        /// The hips must leave it alone: in the A-pose the hands hang at hip
        /// height, 30 cm out from the midline, so scaling them about it threw
        /// them 45 mm sideways on a wide-hipped body; nothing is lost, because
        /// the arm chain only shares edges with the torso up at the shoulder.
        /// The chest is the middle case — a chest tape passes *under* the arms,
        /// so they must not be measured, but they sit against the armpit and
        /// would step away from it if they did not move.
        enum Arms {
            case ignored, carried, included

            var measured: Bool { self == .included }
            var moved: Bool { self != .ignored }
        }
        let arms: Arms

        /// How the band moves what it touches. Only radial survives.
        ///
        /// A sideways-only slide was tried for the shoulders, to stop the band
        /// cutting the upper arm in half horizontally. It cannot hit a girth:
        /// moving x alone adds very little perimeter, so the solver asked for a
        /// strength of about 0.5 and the chest came out 36% wider than the
        /// measurement. The arm was never the band's fault anyway — see
        /// `deltoidShare`.
        enum Motion {
            case radial
        }
        let motion: Motion

        static let hips = LateralGirth(
            landmark: .hip,
            fadeIn: 0.380...0.500, plateau: 0.500...0.565, fadeOut: 0.565...0.615,
            arms: .ignored, motion: .radial
        )
        /// Wedged between the hip band below and the chest band above, which is
        /// all the room there is: the plateau has to hold the measuring slab
        /// and both neighbours have to see zero weight at their own landmarks.
        static let waist = LateralGirth(
            landmark: .waist,
            fadeIn: 0.598...0.620, plateau: 0.620...0.648, fadeOut: 0.648...0.668,
            arms: .ignored, motion: .radial
        )
        static let chest = LateralGirth(
            landmark: .chest,
            fadeIn: 0.655...0.700, plateau: 0.700...0.745, fadeOut: 0.745...0.800,
            arms: .carried, motion: .radial
        )
        static let shoulders = LateralGirth(
            landmark: .shoulder,
            fadeIn: 0.715...0.805, plateau: 0.805...0.840, fadeOut: 0.840...0.858,
            arms: .included, motion: .radial
        )
        /// Bottom-up, so each band normalises against a body the one below it
        /// has already settled.
        static let all = [hips, waist, chest, shoulders]

        /// Regions the tape encloses.
        func measures(_ region: BodyRegion) -> Bool {
            arms.measured || !region.isArmChain
        }

        /// Regions the scale moves.
        func moves(_ region: BodyRegion) -> Bool {
            arms.moved || !region.isArmChain
        }

        /// 0 outside the fades, 1 on the plateau, smoothstepped between.
        func weight(atHeight y: Float) -> Float {
            func smooth(_ range: ClosedRange<Float>, _ value: Float) -> Float {
                let span = range.upperBound - range.lowerBound
                guard span > 0 else { return value < range.lowerBound ? 0 : 1 }
                let t = min(max((value - range.lowerBound) / span, 0), 1)
                return t * t * (3 - 2 * t)
            }
            if y <= fadeIn.lowerBound || y >= fadeOut.upperBound { return 0 }
            if y < plateau.lowerBound { return smooth(fadeIn, y) }
            if y <= plateau.upperBound { return 1 }
            return 1 - smooth(fadeOut, y)
        }
    }

    /// Scales `positions` horizontally so the tape reading at the landmark
    /// becomes the measured one. Operates in the unit mesh's space.
    private static func applyLateralGirth(
        _ girth: LateralGirth,
        to positions: inout [SIMD3<Float>],
        map: BodyRegionMap,
        parameters: BodyMeshParameters
    ) {
        let height = Float(
            BodyProportions.heightFraction(girth.landmark, gender: parameters.gender)
        )
        let target = sample(
            parameters.torso, atHeightCm: Double(height) * parameters.heightCm
        ) / parameters.heightCm
        guard target > 0 else { return }

        // The pivot every motion here turns about: the measured section's own
        // centre, NOT the origin.
        //
        // The baked mesh is centred over its whole bounding box, and the head
        // and feet pull that centre well in front of the torso — the male
        // chest section runs from z = -22.1 cm to +1.1, centred on -10.5. A
        // radial scale about z = 0 is therefore a scale about a point 10 cm
        // outside the body: it moves the back four times as far as the front,
        // walks the torso backwards a couple of centimetres per band, and
        // leaves the chest 24% deeper than the bake while the tape still reads
        // correctly. That lopsidedness was the "blown-out chest".
        guard let pivot = sectionPivot(positions, map: map, atHeight: height, includes: girth.measures)
        else { return }

        // A narrow slab, so it stays inside the plateau where the motion is
        // uniform across it.
        func reading(_ p: [SIMD3<Float>]) -> Float {
            tape(p, map: map, atHeight: height, halfBand: 0.008, includes: girth.measures)
        }
        let achieved = reading(positions)
        guard achieved > 0 else { return }

        // Scaling a planar set about a fixed point multiplies every pairwise
        // distance by the factor, so the tape lands exactly on target.
        let strength = Float(target) / achieved - 1
        guard abs(strength) > 0.0005 else { return }

        for index in positions.indices {
            guard girth.moves(map.region[index]) else { continue }
            let weight = girth.weight(atHeight: positions[index].y)
            guard weight > 0 else { continue }
            let scale = 1 + strength * weight
            positions[index].x = pivot.x + (positions[index].x - pivot.x) * scale
            positions[index].z = pivot.y + (positions[index].z - pivot.y) * scale
        }
    }

    /// The centre of the section a band is measured on, in the horizontal
    /// plane. `x` is the horizontal centre, `y` the depth centre.
    private static func sectionPivot(
        _ positions: [SIMD3<Float>],
        map: BodyRegionMap,
        atHeight height: Float,
        includes: (BodyRegion) -> Bool
    ) -> SIMD2<Float>? {
        let members = positions.indices.filter {
            map.region[$0].isMeasured && includes(map.region[$0])
                && abs(positions[$0].y - height) < 0.012
        }
        guard members.count > 2 else { return nil }
        // Midpoint of the extent rather than the mean of the vertices: the mesh
        // puts far more detail on some parts of a section than others, and a
        // vertex average follows the detail instead of the shape.
        let xs = members.map { positions[$0].x }, zs = members.map { positions[$0].z }
        return SIMD2((xs.min()! + xs.max()!) / 2, (zs.min()! + zs.max()!) / 2)
    }

    /// Moves the front of the chest out (or lets it fall back) according to
    /// `chestProjection`, leaving the back nearly alone.
    ///
    /// **Why the back barely moves.** Breasts and pectorals are in front. A
    /// symmetric depth scale would push the shoulder blades out by as much as
    /// the bust, which reads as a body inflated with a bicycle pump. A quarter
    /// share behind keeps the section continuous through `z = 0` without
    /// inventing a back.
    ///
    /// **Why 0.35 is the pivot.** That is the baked mesh's own build, so a body
    /// scoring 0.35 comes out of here untouched and only the girth pass shapes
    /// it. Above it the chest projects, below it the chest flattens into a
    /// barrel — which is what carrying the same centimetres as fat looks like.
    ///
    /// **Why the push grows with the square of how far forward a point already
    /// is.** A flat multiply on `z` moves the ribcage as much as the breast in
    /// front of it, so the breast gains nothing *relative* to the chest it sits
    /// on — which is exactly how a 118 cm bust on a 104 cm ribcage came out
    /// looking like a barrel with no bust at all. Squaring the share means the
    /// apex, already the furthest forward, moves four times as far as a point
    /// halfway back, and the breast emerges from the wall instead of riding it.

    // MARK: - Limbs

    /// Puts each limb back on the girth it was measured at.
    ///
    /// **Why it is needed at all.** The hip, waist, chest and shoulder bands are
    /// functions of height applied to every vertex, which is what stops them
    /// seaming — and it also means they scale whatever limb happens to cross
    /// their band. On a body close to the bake that is a rounding error. On a
    /// heavy one it is not: measured at bicep 40 cm rendering as 47.9 (+20%)
    /// and thigh 68 cm as 84.1 (+24%), while the calf, which no band reaches,
    /// came out exact. Arms thicker than the thighs beside them is most of why
    /// a heavy body stopped reading as a person.
    ///
    /// **Why a separate pass rather than a smaller band.** The bands have to
    /// reach the limbs. The hip band deliberately runs 12 cm down the femur,
    /// because stopping it at the crotch put a 69 mm shelf under the buttock,
    /// and the chest band has to cross the armpit or it tears there. What was
    /// missing was the correction afterwards, not a narrower band.
    ///
    /// **Arms only, and the legs are not an oversight.** No torso tape wraps a
    /// bicep, so restoring the arm costs nothing. The hip tape, on the other
    /// hand, is pinned by the very thigh vertices a thigh measurement also
    /// describes: forcing both at once over-determines that flesh, and the
    /// attempt put the hips 6 cm off their measurement and tore the crotch at
    /// 3.9x edge stretch. The legs keep the arrangement already documented on
    /// `LateralGirth` — hips own the flesh above the gluteal fold, the thigh's
    /// own read governs from mid-femur down.
    ///
    /// Tapered at the joints, so putting the girth back does not re-open the
    /// seam the band was widened to close.
    private static func restoreLimbGirths(
        _ positions: inout [SIMD3<Float>],
        mesh: BodyBaseMesh,
        map: BodyRegionMap,
        profile: [BodyRegion: [BodyBand]],
        parameters: BodyMeshParameters
    ) {
        let bandCount = BodyBandProfile.defaultBandCount

        for (region, bands) in profile where region.isArmChain && region.isMeasured {
            guard let limb = limbMeasurement(region, parameters: parameters), !bands.isEmpty
            else { continue }

            let anchor = widestBand(bands, within: limb.site)
            let slot = bands.firstIndex { $0.position == anchor.position } ?? 0
            let axis = anchor.axis
            let (right, up) = BodyBandProfile.frame(for: axis)

            // Membership from `along`, which the deformation does not move —
            // a projection onto the axis does, because the bands above slide
            // the limb along it.
            let members = positions.indices.filter {
                map.region[$0] == region
                    && min(Int(map.along[$0] * Float(bandCount)), bandCount - 1) == slot
            }
            guard members.count > 2 else { continue }
            let ordered = members.sorted { map.along[$0] < map.along[$1] }
            let keep = max(members.count / 2, min(members.count, 8))
            let drop = (ordered.count - keep) / 2
            let core = Array(ordered[drop..<(drop + keep)])

            let centre = core.reduce(SIMD3<Float>.zero) { $0 + positions[$1] } / Float(core.count)
            let achieved = ConvexHull.perimeter(of: core.map { index -> SIMD2<Float> in
                let offset = positions[index] - centre
                return SIMD2(simd_dot(offset, right), simd_dot(offset, up))
            })
            guard achieved > 1e-6 else { continue }

            let target = Float(limb.circumferenceCm / parameters.heightCm)
            let correction = target / achieved
            guard abs(correction - 1) > 0.005 else { continue }

            for index in positions.indices where map.region[index] == region {
                let band = min(Int(map.along[index] * Float(bandCount)), bandCount - 1)
                // Gated by the same two rules that decide where the limb's own
                // factor may act. Correcting the deltoid, which the bicep never
                // scaled, put a 10 mm step on the 3 mm edges where it meets the
                // trapezius — a 3.9x stretch on an edge that short.
                let weight = jointWeight(region, band: band, of: bandCount)
                    * deltoidShare(bands[min(band, bands.count - 1)], anchor: anchor)
                let factor = 1 + (correction - 1) * weight
                let offset = positions[index] - centre
                let along = simd_dot(offset, axis) * axis
                positions[index] = centre + along + (offset - along) * factor
            }
        }
    }

    /// How much of a limb correction a band may take: nothing at the joints,
    /// all of it in the middle.
    ///
    /// The counts match `jointHandover`, so the correction fades exactly where
    /// the limb had already handed its factor over — restoring girth in the
    /// shoulder or the elbow would undo the two fixes that closed the seams
    /// there.
    private static func jointWeight(_ region: BodyRegion, band: Int, of count: Int) -> Float {
        let joints = jointHandover(region, uniform: [:])
        let top = count - 1
        var weight: Float = 1
        if joints.proximalBands > 0 {
            weight = min(weight, min(Float(band) / Float(joints.proximalBands), 1))
        }
        if joints.distalBands > 0 {
            weight = min(weight, min(Float(top - band) / Float(joints.distalBands), 1))
        }
        return weight
    }

    // MARK: - Forward projection

    /// A band of heights over which some of a girth is pushed in front of the
    /// body rather than wrapped evenly around it.
    ///
    /// **Why this is not folded into `LateralGirth`.** The two want opposite
    /// envelopes. A girth band has to be short, so it clears its neighbours'
    /// landmarks and does not disturb their measurements. A projection has to
    /// be long, because it is pure shape and any ramp short enough for a girth
    /// band shows up as a ledge — the belly's 4 cm ramp cut a step clean across
    /// the abdomen of every heavy body. Running all the projections first and
    /// all the girth bands after also means each girth lands on its measurement
    /// whatever the shaping did.
    struct ForwardProjection {
        let fadeIn: ClosedRange<Float>
        let plateau: ClosedRange<Float>
        let fadeOut: ClosedRange<Float>
        /// Where the "how far forward does this body already reach" reference
        /// is taken, and where the girth it belongs to is measured.
        let landmark: BodyLandmark
        let amount: @Sendable (BodyMeshParameters) -> Double
        /// Whether the arm chain rides along.
        ///
        /// The chest must take it: its envelope reaches the armpit ring where
        /// arm and torso share edges, and leaving the arm behind tore 22.6 mm
        /// of step and a 5x stretched edge there. The belly must not: in the
        /// A-pose the hands hang at belly height, and pushing them forward with
        /// the abdomen threw them 43 mm out of place. The belly's envelope stops
        /// just short of the armpit, so it owes the arm nothing.
        let movesArms: Bool

        static let belly = ForwardProjection(
            fadeIn: 0.470...0.560, plateau: 0.560...0.635, fadeOut: 0.635...0.672,
            landmark: .waist, amount: { $0.bellyProjection }, movesArms: false
        )
        static let chest = ForwardProjection(
            fadeIn: 0.660...0.705, plateau: 0.705...0.760, fadeOut: 0.760...0.820,
            landmark: .chest, amount: { $0.chestProjection }, movesArms: true
        )
        static let all = [belly, chest]

        func weight(atHeight y: Float) -> Float {
            LateralGirth(
                landmark: landmark, fadeIn: fadeIn, plateau: plateau, fadeOut: fadeOut,
                arms: .ignored, motion: .radial
            ).weight(atHeight: y)
        }
    }

    /// Moves the front of a section out (or lets it fall back), leaving the
    /// back nearly alone.
    ///
    /// **Why the back barely moves.** Breasts, pectorals and bellies are in
    /// front. A symmetric depth scale would push the shoulder blades out by as
    /// much as the bust, which reads as a body inflated with a bicycle pump. A
    /// quarter share behind keeps the section continuous through the middle.
    ///
    /// **Why 0.35 is the pivot.** That is the baked mesh's own build, so a body
    /// scoring 0.35 comes out of here untouched and only the girth pass shapes
    /// it. Above it the section projects, below it it flattens into a barrel —
    /// which is what carrying the same centimetres as fat looks like.
    ///
    /// **Why the push grows with the square of how far forward a point already
    /// is.** A flat multiply on `z` moves the ribcage as much as the breast in
    /// front of it, so the breast gains nothing *relative* to the chest it sits
    /// on — which is exactly how a 118 cm bust on a 104 cm ribcage came out
    /// looking like a barrel with no bust at all. Squaring the share means the
    /// apex, already the furthest forward, moves four times as far as a point
    /// halfway back.
    private static func applyForwardProjection(
        _ projection: ForwardProjection,
        to positions: inout [SIMD3<Float>],
        map: BodyRegionMap,
        parameters: BodyMeshParameters
    ) {
        // Faded out as the heavy bake takes over.
        //
        // These projections exist because a lean bake has no belly and no
        // hanging bust to speak of, so the shape had to be sculpted on top of
        // the girth. The heavy bake carries both already, and sculpting them
        // again over that is what turned a gut into a cone and left a fold
        // across the mid-back — the "broken spine". Rendered side by side with
        // the projections switched off, the ablation is not close: the belly
        // hangs, the chest sags, and the fold is gone.
        //
        // **What this costs, stated plainly.** On a very heavy body the bust
        // measurement stops shaping the chest and the abdomen stops responding
        // to the waist-to-hip ratio; both are then whatever the heavy bake says.
        // A cone that no bust measurement can explain was the worse of the two.
        let handover = Float(1 - min(max(parameters.fatness, 0), 1))
        let bias = Float(projection.amount(parameters) - 0.35) * 1.6 * handover
        guard abs(bias) > 0.005 else { return }

        let height = Float(
            BodyProportions.heightFraction(projection.landmark, gender: parameters.gender)
        )
        // The section's own centre, not the origin: the baked mesh is centred
        // over its whole bounding box and the torso sits about 10 cm behind
        // that, so a split on `z > 0` puts nearly the whole torso on the back.
        guard let pivot = sectionPivot(
            positions, map: map, atHeight: height, includes: { !$0.isArmChain }
        ) else { return }

        // How far forward this section reaches from its own centre.
        let front = positions.indices
            .filter { map.region[$0] == .torso && projection.weight(atHeight: positions[$0].y) > 0.9 }
            .reduce(Float(0)) { max($0, positions[$1].z - pivot.y) }
        guard front > 1e-4 else { return }

        // The head needs no exclusion: both envelopes die below where it starts.
        for index in positions.indices {
            guard projection.movesArms || !map.region[index].isArmChain else { continue }
            let weight = projection.weight(atHeight: positions[index].y)
            guard weight > 0 else { continue }
            let depth = positions[index].z - pivot.y
            let share = depth > 0
                ? min(depth / front, 1) * min(depth / front, 1)
                : -0.25 * max(depth / front, -1)
            positions[index].z += bias * weight * share * front
        }
    }

    /// A horizontal tape around every measured region at a height, in the
    /// space the positions are given in.
    static func tape(
        _ positions: [SIMD3<Float>],
        map: BodyRegionMap,
        atHeight height: Float,
        halfBand: Float = 0.012,
        includes: (BodyRegion) -> Bool = { _ in true }
    ) -> Float {
        let members = positions.indices.filter {
            map.region[$0].isMeasured && includes(map.region[$0])
                && abs(positions[$0].y - height) < halfBand
        }
        guard members.count > 2 else { return 0 }
        return ConvexHull.perimeter(of: members.map { SIMD2(positions[$0].x, positions[$0].z) })
    }

    /// One `target / base` factor per band. Unmeasured regions never reach here.
    ///
    /// **Limbs get a single uniform factor, deliberately.** Interpolating a
    /// target curve along a limb was the first design and it destroyed the
    /// natural taper: the solver's anchor heights were laid out for the old
    /// ring-stack, where the arm hung vertically, so on an A-pose mesh the
    /// wrist sampled a mid-forearm target and inflated from 15.4 cm to 26.9 —
    /// nearly the bicep. Scaling the whole limb by one number keeps the base
    /// mesh's own shape exactly and only changes its girth.
    static func scaleFactors(
        parameters: BodyMeshParameters,
        profile: [BodyRegion: [BodyBand]]
    ) -> [BodyRegion: [Float]] {
        // Every limb's own uniform factor first, so each end can see what it
        // is handing over to.
        var uniform: [BodyRegion: Float] = [:]
        for (region, bands) in profile where region.isMeasured {
            guard !bands.isEmpty, let limb = limbMeasurement(region, parameters: parameters)
            else { continue }
            let anchor = widestBand(bands, within: limb.site)
            let target = Float(limb.circumferenceCm / parameters.heightCm)
            uniform[region] = anchor.circumference > 0 ? target / anchor.circumference : 1
        }

        var result: [BodyRegion: [Float]] = [:]
        for (region, bands) in profile where region.isMeasured {
            guard !bands.isEmpty else { continue }
            if region == .neck {
                result[region] = neckFactors(bands: bands, parameters: parameters)
                continue
            }
            guard let factor = uniform[region] else {
                result[region] = torsoFactors(bands: bands, parameters: parameters)
                continue
            }
            let joints = jointHandover(region, uniform: uniform)
            let anchor = limbMeasurement(region, parameters: parameters)
                .map { widestBand(bands, within: $0.site) }
            let raw = bands.indices.map { index -> Float in
                let jointed = joints.factor(factor, atBand: index, of: bands.count)
                guard let anchor else { return jointed }
                // A band far bigger than the one the limb was read on is not
                // that limb, and must not take its factor. Whichever of the two
                // rules holds the factor back further wins.
                let share = deltoidShare(bands[index], anchor: anchor)
                return min(jointed, 1 + (factor - 1) * share)
            }
            // Smoothed across neighbours, because the base circumferences the
            // deltoid gate reads jump — 28.2 cm to 16.1 between two bands on
            // the male arm — so the gate follows them with a jump of its own
            // and the render grows a sleeve seam where it lands.
            result[region] = raw.indices.map { index in
                let before = raw[max(index - 1, 0)]
                let after = raw[min(index + 1, raw.count - 1)]
                return (before + raw[index] * 2 + after) / 4
            }
        }
        return result
    }

    /// The neck carries `neckCm` at its base and lets go of it by the jaw.
    ///
    /// **Why it needs its own rule rather than the torso's or a limb's.** The
    /// torso's stack is anchored on the waist and the chest and returns to 1
    /// above them, so it has nothing to say this high. A limb's rule reads one
    /// circumference over a measurement site and applies it to the whole
    /// region, which here would scale the jaw and the base of the skull by a
    /// neck measurement.
    ///
    /// Bands run upward from the neck joint, so the lower half carries the
    /// measurement and the upper half hands back to 1 before the head begins.
    private static func neckFactors(
        bands: [BodyBand], parameters: BodyMeshParameters
    ) -> [Float] {
        let height = BodyProportions.heightFraction(.neck, gender: parameters.gender)
        let target = Float(
            sample(parameters.torso, atHeightCm: height * parameters.heightCm)
                / parameters.heightCm
        )
        // The NARROWEST band of the lower half, not the widest.
        //
        // A neck is measured at its thinnest point, just under the larynx, and
        // the bands say exactly where that is: 39.3, 37.5, 36.3, 38.2 on the
        // male bake before the region turns into jaw at 44.8. Anchoring on the
        // widest instead took 39.3 — the flare into the shoulders — so a 39 cm
        // neck solved to a factor of 0.99 and a 10 cm span of measurements moved
        // the mesh by 3 cm.
        let neckProper = bands.prefix(max(bands.count / 2, 1))
        guard let anchor = neckProper.min(by: { $0.circumference < $1.circumference }),
              anchor.circumference > 0, target > 0
        else { return Array(repeating: 1, count: bands.count) }
        let factor = target / anchor.circumference

        let top = bands.count - 1
        return bands.indices.map { index in
            let fraction = top > 0 ? Float(index) / Float(top) : 0
            // Zero where the neck leaves the torso, so the two meet without a
            // step; full across the neck itself; back to zero before the jaw,
            // which no neck measurement describes.
            let rise = min(max(fraction / 0.286, 0), 1)
            let fall = 1 - min(max((fraction - 0.429) / 0.285, 0), 1)
            return 1 + (factor - 1) * min(rise, fall)
        }
    }

    /// How much of a limb's own factor a band is allowed to take, judged by how
    /// much fatter it is than the band the measurement was read on.
    ///
    /// **Why band index is not enough.** The upper-arm region owns the deltoid,
    /// and on the baked meshes the deltoid bands read 55-70 cm against a bicep
    /// band of 25-29. A bicep of 36 cm solves to a factor of 1.45, and handing
    /// even a third of that to the deltoid grew it from 54 cm to 71 — the
    /// shoulder pads that made every heavy body look like a bodybuilder. A
    /// fixed count of tapered bands cannot fix it, because the deltoid takes
    /// three bands on the female bake and four on the male one.
    ///
    /// Reading the base circumferences instead finds the cliff wherever it is:
    /// a band up to a quarter fatter than the anchor is still the limb, and one
    /// twice as fat is the shoulder it hangs from.
    private static func deltoidShare(_ band: BodyBand, anchor: BodyBand) -> Float {
        guard anchor.circumference > 0 else { return 1 }
        let ratio = band.circumference / anchor.circumference
        return 1 - min(max((ratio - 1.25) / 0.75, 0), 1)
    }

    /// What a limb's factor gives way to at each of its two ends, and over how
    /// many bands. Bands run from the body-side joint outward.
    ///
    /// **Why a limb has to let go of its factor at a joint.** A vertex is moved
    /// by its perpendicular distance to its region's axis times `factor - 1`.
    /// On top of the shoulder that distance is about 18 cm to the spine and
    /// about 5 cm to the humerus, so the same pair of factors moves the torso
    /// side three times as far as the arm side and leaves a wall between them —
    /// 13.6 mm on the male bake, 19.3 mm on the female one, which is what the
    /// key light rendered as a white seam across the trapezius. The elbow has
    /// the same disease in milder form: an obese bake solves the upper arm at
    /// 1.38 and the forearm at 1.23, and the 17 mm between them reads as a
    /// bracelet. Widening the region blend closes neither — the ramp was swept
    /// from 0.70 down to 0.30 and bought 1.4 mm at the cost of five points of
    /// waist accuracy.
    ///
    /// **Where each ramp is allowed to sit.** Only outside the limb's own
    /// measurement site, or it would move the number the limb was solved for.
    /// The bicep is read over 0.50...0.85 of the upper arm, which leaves both
    /// ends free; the forearm is read over 0.00...0.30, hard against the elbow,
    /// so that end gets a single band and the wrist end gets two.
    ///
    /// The legs are deliberately left alone: the knee and ankle measured 1.4 mm
    /// and 0.7 mm, and the thigh's meeting with the pelvis is handled by the
    /// torso's own ramp rather than here.
    private struct JointHandover {
        let proximal: Float
        let proximalBands: Int
        let distal: Float
        let distalBands: Int

        func factor(_ own: Float, atBand index: Int, of count: Int) -> Float {
            if proximalBands > 0 && index < proximalBands {
                return proximal + (own - proximal) * (Float(index) / Float(proximalBands))
            }
            if distalBands > 0 && index > count - 1 - distalBands {
                return distal + (own - distal) * (Float(count - 1 - index) / Float(distalBands))
            }
            return own
        }
    }

    private static func jointHandover(
        _ region: BodyRegion, uniform: [BodyRegion: Float]
    ) -> JointHandover {
        _ = uniform
        // Both sides of the elbow go to 1, not to their average. Matching the
        // two factors is not enough and was tried: with the upper arm and the
        // forearm both handed 1.30 the step stayed at 17.0 mm, because the two
        // regions scale about different centroids along differently angled
        // axes, and a vertex sitting between them lands `(perpA - perpB) *
        // (factor - 1)` apart however equal the factors are. Only `factor = 1`
        // makes that difference vanish. It costs nothing anatomically: an elbow
        // is bone and does not thicken with the arm around it.
        let elbow: Float = 1
        switch region {
        case .leftUpperArm:
            return JointHandover(
                proximal: 1, proximalBands: 3, distal: elbow, distalBands: 2
            )
        case .rightUpperArm:
            return JointHandover(
                proximal: 1, proximalBands: 3, distal: elbow, distalBands: 2
            )
        case .leftForearm:
            return JointHandover(
                proximal: elbow, proximalBands: 1, distal: 1, distalBands: 2
            )
        case .rightForearm:
            return JointHandover(
                proximal: elbow, proximalBands: 1, distal: 1, distalBands: 2
            )
        default:
            return JointHandover(proximal: 1, proximalBands: 0, distal: 1, distalBands: 0)
        }
    }

    /// The one circumference a limb segment is described by, and where along
    /// that segment a tape measure would read it. `site` runs 0 at the joint
    /// nearest the body to 1 at the far one.
    private static func limbMeasurement(
        _ region: BodyRegion, parameters: BodyMeshParameters
    ) -> (circumferenceCm: Double, site: ClosedRange<Float>)? {
        let arm = parameters.arm, leg = parameters.leg
        guard !arm.isEmpty, !leg.isEmpty else { return nil }

        // The solver builds the arm as wrist -> forearm -> bicep and the leg
        // bottom-up as ankle -> calf -> knee -> thigh, so the biggest value in
        // the lower half of the leg is the calf and the top of each stack is
        // the girth nearest the torso.
        let bicep = arm[arm.count - 1].circumferenceCm
        let forearm = arm[arm.count / 2].circumferenceCm
        let thigh = leg[leg.count - 1].circumferenceCm
        let calf = leg.prefix(max(leg.count / 2, 1)).map(\.circumferenceCm).max() ?? 0

        switch region {
        // Skips the deltoid, which shares this region but is not what a bicep
        // measurement describes — its base reads 69.9 cm against the bicep's 29.
        case .leftUpperArm, .rightUpperArm: return (bicep, 0.50...0.85)
        case .leftForearm, .rightForearm:   return (forearm, 0.00...0.30)
        case .leftThigh, .rightThigh:       return (thigh, 0.00...0.35)
        case .leftShin, .rightShin:         return (calf, 0.00...0.50)
        default:                            return nil
        }
    }

    /// The thickest band inside a fractional window of the region.
    private static func widestBand(_ bands: [BodyBand], within site: ClosedRange<Float>) -> BodyBand {
        let candidates = bands.indices.filter {
            let fraction = bands.count > 1 ? Float($0) / Float(bands.count - 1) : 0
            return site.contains(fraction)
        }
        let pool = candidates.isEmpty ? Array(bands.indices) : candidates
        return bands[pool.max { bands[$0].circumference < bands[$1].circumference } ?? pool[0]]
    }

    /// The torso interpolates between two anchors — waist and chest — located
    /// by height, and returns to 1 above the chest.
    ///
    /// **Why the hips are not an anchor here.** Below the waist the legs take a
    /// growing share of the girth, so the torso region's own section stops
    /// being a hip measurement: on the female bake it narrows to 48.7 cm, less
    /// than the band beneath it. Worse, the hip tape's widest points are thigh
    /// vertices, not torso ones, so scaling the pelvis by a hip factor moves
    /// barely a tenth of the tape and steps away from the leg beside it —
    /// measured at 23.7 mm on a 132 cm hip. `hips` and `shoulders` are applied
    /// by `lateralGirth` instead, which does not know about regions and so
    /// cannot step at their boundaries.
    ///
    /// **Why the curve returns to 1 above the chest** — see `jointTaper`.
    private static func torsoFactors(
        bands: [BodyBand], parameters: BodyMeshParameters
    ) -> [Float] {
        func target(_ landmark: BodyLandmark) -> Float {
            // The solver's own table, not `.male` regardless: sampling 1.5% of
            // stature off the anchor lands mid-Hermite, where the neighbouring
            // measurement leaks in.
            let height = BodyProportions.heightFraction(landmark, gender: parameters.gender)
            return Float(sample(parameters.torso, atHeightCm: height * parameters.heightCm)
                / parameters.heightCm)
        }
        func nearest(_ landmark: BodyLandmark) -> Int {
            let height = Float(BodyProportions.heightFraction(landmark, gender: parameters.gender))
            return bands.indices.min {
                abs(bands[$0].centroid.y - height) < abs(bands[$1].centroid.y - height)
            } ?? 0
        }
        func factor(_ index: Int, _ landmark: BodyLandmark) -> Float {
            bands[index].circumference > 0 ? target(landmark) / bands[index].circumference : 1
        }
        let waist = nearest(.waist)
        let chest = max(nearest(.chest), waist)
        let waistFactor = factor(waist, .waist)
        guard chest > waist else { return Array(repeating: waistFactor, count: bands.count) }
        let chestFactor = factor(chest, .chest)

        // Above the chest the torso's cross-section stops being a ribcage and
        // becomes the shelf the deltoids sit on, roughly 18 cm out from the
        // spine the factor is measured against. Holding `chestFactor` up there
        // pushed that shelf sideways by a centimetre while the arm beside it
        // moved a quarter of that, and the step between them was the visible
        // seam. Letting the factor return to 1 puts the shoulder back on the
        // base mesh, where the arm meets it.
        // Below the waist the torso runs into the thighs, and the same argument
        // that applies at the shoulder applies here upside down: the lower
        // abdomen is a long way from the spine the factor is measured against,
        // the femur is close to the leg's own axis, and holding `waistFactor`
        // all the way to the crotch left the two meeting at a fold. On an obese
        // body it rendered as a hard V running from each hip to the pubis — a
        // triangular flap with a knife edge, the single worst-looking thing on
        // the model. Letting the factor return to 1 removes the edge; the hips
        // are what put the girth back, and they do it without knowing where a
        // region boundary is.
        // The ramp starts one band below the waist, not at it. `placed`
        // interpolates factors between neighbouring bands, so a band directly
        // under the waist carrying a lower factor drags the waist's own slab
        // down with it — measured at 104 cm rendering as 99.6 instead of 100.5.
        let top = bands.count - 1
        let rampTop = max(waist - 1, 0)
        let perBand = bands.indices.map { index -> Float in
            if index < rampTop {
                let step = Float(index) / Float(rampTop)
                return 1 + (waistFactor - 1) * step
            }
            if index <= waist { return waistFactor }
            if index < chest {
                let step = Float(index - waist) / Float(chest - waist)
                return waistFactor + (chestFactor - waistFactor) * step
            }
            guard top > chest else { return chestFactor }
            let step = Float(index - chest) / Float(top - chest)
            return chestFactor + (1 - chestFactor) * step
        }

        // Smoothed across neighbours. The profile above is piecewise linear
        // with corners at the hip ramp, the waist and the chest, and a corner
        // in the factor is a corner in the surface — under a grazing key light
        // that reads as a horizontal line round the body, worst across a heavy
        // back where the factors are largest.
        return perBand.indices.map { index in
            let below = perBand[max(index - 1, 0)]
            let above = perBand[min(index + 1, perBand.count - 1)]
            return (below + perBand[index] * 2 + above) / 4
        }
    }

    private static func solverStack(
        for region: BodyRegion, parameters: BodyMeshParameters
    ) -> [BodyCrossSection] {
        switch region {
        case .leftUpperArm, .rightUpperArm, .leftForearm, .rightForearm: return parameters.arm
        case .leftThigh, .rightThigh, .leftShin, .rightShin:             return parameters.leg
        default:                                                        return parameters.torso
        }
    }

    /// Linear interpolation through a solver stack, clamped at both ends.
    /// The stacks are ordered bottom to top.
    static func sample(_ stack: [BodyCrossSection], atHeightCm height: Double) -> Double {
        guard let first = stack.first, let last = stack.last else { return 0 }
        if height <= first.y { return first.circumferenceCm }
        if height >= last.y { return last.circumferenceCm }
        for index in 0..<(stack.count - 1) where height <= stack[index + 1].y {
            let low = stack[index], high = stack[index + 1]
            let span = high.y - low.y
            let t = span > 0 ? (height - low.y) / span : 0
            return low.circumferenceCm + (high.circumferenceCm - low.circumferenceCm) * t
        }
        return last.circumferenceCm
    }

    /// The tape-measure reading of a rendered body, in the horizontal plane —
    /// which is how a waist is actually measured. Used by the tests: this is
    /// how the acceptance criterion is checked against the output rather than
    /// against the intent.
    static func circumference(
        of positions: [SIMD3<Float>],
        map: BodyRegionMap,
        region: BodyRegion,
        atHeight height: Float,
        halfBand: Float = 0.012
    ) -> Float {
        let members = positions.indices.filter {
            map.region[$0] == region && abs(positions[$0].y - height) < halfBand
        }
        guard members.count > 2 else { return 0 }
        let centroid = members.reduce(SIMD3<Float>.zero) { $0 + positions[$1] } / Float(members.count)
        return ConvexHull.perimeter(of: members.map {
            SIMD2(positions[$0].x - centroid.x, positions[$0].z - centroid.z)
        })
    }

    /// Smooth per-vertex normals for a deformed position array. The baked
    /// normals describe the base surface and stop matching once it moves.
    static func normals(for positions: [SIMD3<Float>], indices: [Int32]) -> [SIMD3<Float>] {
        var accumulated = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var triangle = 0
        while triangle + 2 < indices.count {
            let i0 = Int(indices[triangle])
            let i1 = Int(indices[triangle + 1])
            let i2 = Int(indices[triangle + 2])
            let faceNormal = cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            accumulated[i0] += faceNormal
            accumulated[i1] += faceNormal
            accumulated[i2] += faceNormal
            triangle += 3
        }
        return accumulated.map { normal in
            let length = simd_length(normal)
            // A vertex touched only by degenerate triangles would normalise to
            // NaN; fall back to a sane unit vector instead.
            return length > 0 ? normal / length : SIMD3<Float>(0, 1, 0)
        }
    }
}
