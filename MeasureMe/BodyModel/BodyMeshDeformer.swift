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

            let centroid = bands[lower].centroid
                + (bands[lower + 1].centroid - bands[lower].centroid) * step
            let factor = regionFactors[lower]
                + (regionFactors[lower + 1] - regionFactors[lower]) * step

            let offset = base - centroid
            let alongAxis = simd_dot(offset, axis) * axis
            return centroid + alongAxis + (offset - alongAxis) * factor
        }

        return mesh.positions.indices.map { index in
            let base = mesh.positions[index]
            let region = map.region[index]

            // An unmeasured region never moves at all: the head, hands and feet
            // ride the stature scale and nothing else.
            guard region.isMeasured else { return base * stature }

            let primary = placed(base, in: region) ?? base
            let weight = map.blend[index]
            // Below this the second region contributes nothing visible, and
            // skipping it keeps the interior of every region exact.
            guard weight > 0.001 else { return primary * stature }

            // Where the neighbour is unmeasured, `placed` yields the vertex
            // untouched, so blending feathers this region's factor down toward
            // 1 as it approaches the neck, wrist or ankle. Doing it on the
            // measured side only is what keeps the transition continuous
            // without moving the head: without it a torso vertex at the neck
            // scaled by 1.53 sat against a head vertex at 1.0 and stretched
            // their shared edge 4.5x.
            let other = placed(base, in: map.secondary[index]) ?? base
            return (primary + (other - primary) * weight) * stature
        }
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
        var result: [BodyRegion: [Float]] = [:]
        for (region, bands) in profile where region.isMeasured {
            guard !bands.isEmpty else { continue }
            if let limb = limbMeasurement(region, parameters: parameters) {
                let anchor = widestBand(bands, within: limb.site)
                let target = Float(limb.circumferenceCm / parameters.heightCm)
                let factor = anchor.circumference > 0 ? target / anchor.circumference : 1
                result[region] = Array(repeating: factor, count: bands.count)
            } else {
                result[region] = torsoFactors(bands: bands, parameters: parameters)
            }
        }
        return result
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
    /// by height, and holds the end factor outside that span.
    ///
    /// **Why the hips are not an anchor.** Below the waist the legs take a
    /// growing share of the body's girth, so the torso region's own section
    /// stops being a hip measurement: on the female bake it narrows to 48.7 cm,
    /// less than the band beneath it. Anchoring 98 cm there gave a factor of
    /// 1.85 against the neighbouring thigh's 0.90, and that step rendered as a
    /// hard wedge over the pelvis. Two repairs were tried and both failed —
    /// locating the waist by narrowness picks the crotch, and putting the hip
    /// anchor on the widest sub-waist band let 98 cm overwrite the waist, so a
    /// 78 cm waist rendered as 98. Holding the waist factor downward is what
    /// works.
    ///
    /// **Why the curve stops at the chest.** The next anchor up is
    /// `shouldersCm`, a girth measured around the deltoids; the arms carry that
    /// now, and dividing it by a ribcage rendered a collar.
    ///
    /// The cost, stated plainly: `hipsCm`, `shouldersCm` and `neckCm` do not
    /// shape the mesh. They still reach it through volume reconciliation, which
    /// moves it by millimetres. Nine of the twelve measurements shape it.
    private static func torsoFactors(
        bands: [BodyBand], parameters: BodyMeshParameters
    ) -> [Float] {
        func target(_ landmark: BodyLandmark) -> Float {
            // Gendered fractions differ by at most 1.5% of stature and only
            // pick which value to read; the position comes from the mesh.
            let height = BodyProportions.heightFraction(landmark, gender: .male)
            return Float(sample(parameters.torso, atHeightCm: height * parameters.heightCm)
                / parameters.heightCm)
        }
        func nearest(_ landmark: BodyLandmark) -> Int {
            let height = Float(BodyProportions.heightFraction(landmark, gender: .male))
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

        return bands.indices.map { index in
            if index <= waist { return waistFactor }
            if index >= chest { return chestFactor }
            let step = Float(index - waist) / Float(chest - waist)
            return waistFactor + (chestFactor - waistFactor) * step
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
