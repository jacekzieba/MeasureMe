// BodyBaseMeshProvider.swift
//
// **BodyBaseMeshProvider**
// Loads the baked base meshes out of the app bundle and blends them.
//
// **Responsibilities:**
// - Resolving a gender to its bundled `.bodymesh` resources
// - Blending the lean and heavy bakes by how much fat the body carries
// - Holding the decoded bakes for the process, and the blends only while the
//   screen that uses them is up
//
// **Why there are two bakes per gender and not one.**
// Scaling cross-sections radially changes how big a body is, not what kind of
// body it is. Driven hard enough to reach 125 kg, a lean bake comes out as a
// lean body inflated: taut, symmetric, with the abdominal and deltoid relief of
// the original still showing through, and nothing anywhere that hangs. The
// measurements were right and it did not read as a person. The second bake is
// MakeHuman's minimum-muscle, maximum-weight target — the soft end of the axis —
// and blending toward it before the deformer runs gives the girth pass a body of
// the right *kind* to resize.
//
// **Two caches, with different lifetimes, because they cost different amounts.**
//
// `bakes` holds what decoding and the topology pass produced: four meshes at
// 13 380 vertices, a little over two megabytes, plus a region map that costs
// 121 ms per gender to build. None of it depends on a measurement, so it is
// kept for the process — re-decoding on every appearance would trade two
// megabytes for a hitch on a user-visible transition.
//
// `blends` holds the *derived* meshes: one per grid node of `fatness`, each
// carrying its own 13 380 positions (214 KB) and the band profile measured on
// them. It used to be unbounded, and with a fine grid that was 11 MB that
// nothing ever freed. It is now an LRU of `blendCacheLimit` nodes per gender —
// wide enough for the whole span a morph slider covers — and it is dropped
// outright when the body model screen goes away. See `releaseBlends`.
//
// **Why so few grid nodes.** A blended position is exactly linear in `fatness`,
// so interpolating between two neighbouring nodes reproduces the mesh the exact
// blend would have produced, to 0.0001 mm. Only the band profile is an
// approximation, because a hull perimeter is not linear in the positions it
// encloses — measured at 0.22% of a band circumference on this grid, 0.21 mm
// after the deformer has run and 0.16 mm on a thigh girth. Rounding `fatness`
// to the nearest node instead, which is what this did before, stepped the
// silhouette by 3 to 6 mm at every boundary; the grid was eight times finer and
// that bought nothing, because the error is a *discontinuity*, not a size.
//
import Foundation
import simd

enum BodyBaseMeshProvider {
    enum LoadError: Error, Equatable {
        case resourceMissing(String)
    }

    /// The lean and heavy bakes for one gender, plus everything derived from
    /// the topology rather than from the positions.
    private struct Bakes: Sendable {
        let lean: BodyBaseMesh
        let heavy: BodyBaseMesh
        /// Built on the lean bake and reused for every blend.
        ///
        /// Both bakes share a vertex order, a triangle list and a skeleton — the
        /// weight target moves flesh, not joints — so which vertex belongs to
        /// which region, and how far along it sits, does not depend on the
        /// blend. The band *profile* does, because it records circumferences.
        let map: BodyRegionMap
        let bones: [BodyBone]
    }

    private static var bakes: [BodyGender: Bakes] = [:]
    /// Grid nodes: a blended mesh and the band profile measured on it, keyed by
    /// gender and node index. A node exists because building a band profile
    /// costs 18 ms, which no frame of a drag can afford; `prepared` interpolates
    /// between two of them rather than rounding to one.
    private static var blends: [BlendKey: Prepared] = [:]
    /// The same keys, least-recently-used first.
    ///
    /// Kept beside `blends` because a Dictionary has no order to evict by. At
    /// this size a linear scan is cheaper than a second index would be: the
    /// array never holds more than `blendCacheLimit` entries per gender.
    private static var blendOrder: [BlendKey] = []

    private struct BlendKey: Hashable {
        let gender: BodyGender
        let step: Int
    }

    /// Intervals the `fatness` range is divided into; there is one node more
    /// than this. Four, because interpolation — not a finer grid — is what
    /// removes the boundary step, and five nodes is a whole slider's span held
    /// at once for 1.1 MB. See the note on grid size at the top of the file.
    nonisolated private static let blendSteps = 4

    /// Nodes kept per gender. One more than the grid has, so the span a morph
    /// slider covers is never evicted by its own far end while it is being
    /// dragged; the limit is what stops a gender switch doubling the cost.
    nonisolated private static let blendCacheLimit = 6

    /// Everything a render needs, built together so it can cross the actor
    /// boundary in one hop.
    struct Prepared: Sendable {
        let mesh: BodyBaseMesh
        let map: BodyRegionMap
        let profile: [BodyRegion: [BodyBand]]
    }

    /// Decodes both bakes and builds the topology-derived rig **off the main
    /// actor**, then caches.
    ///
    /// Measured on the simulator: decoding is 15 ms per mesh, the region map
    /// 121 ms and a band profile 18 ms. Run synchronously on the main actor —
    /// which is where this used to happen, the module defaulting to `MainActor`
    /// — that blocks the very thread a progress indicator needs in order to
    /// animate, so a spinner alone would have sat frozen.
    static func prepare(for gender: BodyGender) async {
        guard bakes[gender] == nil else { return }

        guard let leanData = data(gender, variant: "Base"),
              let heavyData = data(gender, variant: "Heavy"),
              let bones = try? BodySkeleton.bones(for: gender)
        else { return }

        let built = await Task.detached(priority: .userInitiated) { () -> Bakes? in
            guard let lean = try? BodyMeshFile.decode(leanData),
                  let heavy = try? BodyMeshFile.decode(heavyData),
                  lean.positions.count == heavy.positions.count
            else { return nil }
            return Bakes(
                lean: lean,
                heavy: heavy,
                map: BodyRegionMap.build(mesh: lean, bones: bones),
                bones: bones
            )
        }.value

        guard let built else { return }
        bakes[gender] = built
    }

    /// The prepared rig at a given fatness, or nil while `prepare` has not
    /// finished. Callers render nothing rather than blocking to build it.
    ///
    /// `fatness` is 0 for the lean bake and 1 for the heavy one; see
    /// `BodyMeshSolver.fatness` for where the number comes from.
    ///
    /// Between two grid nodes the answer is interpolated, not rounded. Rounding
    /// is what a slider feels: the parameters move continuously while the base
    /// mesh underneath them only changes at a boundary, so the silhouette sits
    /// still and then steps — measured at 3 to 6 mm across 1 800 vertices, most
    /// of it at the waist, and the same amount of pixel change as a frame and a
    /// half of the Play animation delivered in no time at all.
    static func prepared(for gender: BodyGender, fatness: Double = 0) -> Prepared? {
        guard bakes[gender] != nil else { return nil }

        let scaled = min(max(fatness, 0), 1) * Double(blendSteps)
        let lower = min(Int(scaled), blendSteps)
        guard let low = node(gender, step: lower) else { return nil }

        let share = Float(scaled - Double(lower))
        guard lower < blendSteps, share > 1e-4, let high = node(gender, step: lower + 1)
        else { return low }
        return interpolated(low, high, share)
    }

    /// Builds every grid node the slider between two bodies will land on, off
    /// the main actor, so the first drag pays nothing at a boundary.
    ///
    /// Without it each new node costs 18 ms on the thread drawing the frame —
    /// a dropped frame at every boundary, and the Play animation crosses one
    /// every few frames.
    static func warm(gender: BodyGender, between first: Double, and second: Double) async {
        guard let bakes = bakes[gender] else { return }

        let low = node(containing: min(first, second))
        let high = min(node(containing: max(first, second)) + 1, blendSteps)
        for step in low...high {
            let key = BlendKey(gender: gender, step: step)
            if blends[key] != nil {
                touch(key)
                continue
            }
            guard !Task.isCancelled else { return }
            store(key, await Task.detached(priority: .utility) { build(bakes, step: step) }.value)
        }
    }

    /// Drops every blended mesh, keeping the decoded bakes and the region map.
    ///
    /// Called when the body model screen goes away. The blends are the part
    /// that scales with how far the slider was dragged and the part nothing
    /// else in the app has a use for; the bakes cost 121 ms of region map to
    /// rebuild and are what makes coming back cheap.
    static func releaseBlends() {
        blends.removeAll()
        blendOrder.removeAll()
    }

    /// The node at or below a fatness value.
    nonisolated private static func node(containing fatness: Double) -> Int {
        min(Int(min(max(fatness, 0), 1) * Double(blendSteps)), blendSteps)
    }

    private static func node(_ gender: BodyGender, step: Int) -> Prepared? {
        let key = BlendKey(gender: gender, step: step)
        if let cached = blends[key] {
            touch(key)
            return cached
        }
        guard let bakes = bakes[gender] else { return nil }
        let built = build(bakes, step: step)
        store(key, built)
        return built
    }

    private static func touch(_ key: BlendKey) {
        if let index = blendOrder.firstIndex(of: key) { blendOrder.remove(at: index) }
        blendOrder.append(key)
    }

    /// Evicts per gender rather than across the whole cache: switching gender
    /// must not throw away the nodes the slider is mid-drag on, and a gender
    /// nobody is looking at must not survive because it was touched last.
    private static func store(_ key: BlendKey, _ prepared: Prepared) {
        blends[key] = prepared
        touch(key)

        var held = blendOrder.filter { $0.gender == key.gender }.count
        var index = 0
        while held > blendCacheLimit, index < blendOrder.count {
            guard blendOrder[index].gender == key.gender else {
                index += 1
                continue
            }
            blends[blendOrder[index]] = nil
            blendOrder.remove(at: index)
            held -= 1
        }
    }

    /// One grid node: the two bakes mixed, and the bands measured on the result.
    ///
    /// `nonisolated` so `warm` can run it off the main actor; it reads nothing
    /// but its arguments.
    nonisolated private static func build(_ bakes: Bakes, step: Int) -> Prepared {
        let t = Float(step) / Float(blendSteps)
        let positions = zip(bakes.lean.positions, bakes.heavy.positions).map {
            $0 + ($1 - $0) * t
        }
        // Normals recomputed here would be thrown away: nothing in the app
        // reads a base mesh's normals, because the renderer rebuilds them from
        // the DEFORMED positions — the baked ones stop describing the surface
        // the moment a measurement moves a vertex. Carrying the lean bake's
        // through keeps the field meaning what it means in the file, and saves
        // a pass over 26 756 triangles per blend step.
        //
        // They are stale for a blended mesh, and deliberately so. If something
        // ever does need them, recompute from the positions rather than
        // interpolating the two bakes': the mean of two unit normals is a short
        // vector pointing between them, not the normal of the surface that
        // interpolating the positions produced.
        let blended = BodyBaseMesh(
            positions: positions,
            normals: bakes.lean.normals,
            indices: bakes.lean.indices
        )

        return Prepared(
            mesh: blended,
            map: bakes.map,
            profile: BodyBandProfile.build(
                mesh: blended, map: bakes.map, bones: bakes.bones,
                bandsPerRegion: BodyBandProfile.defaultBandCount
            )
        )
    }

    /// A point between two grid nodes.
    ///
    /// The positions are exact: a blend is linear in `fatness`, so mixing two
    /// mixes of the same pair lands on the mix that value would have produced.
    /// The band circumferences are not — a hull perimeter is not linear in the
    /// points it wraps — but over one interval of this grid the difference is
    /// 0.22% of a circumference.
    ///
    /// `axis` and `vertexCount` are copied rather than blended because they do
    /// not depend on the blend at all: the axis comes from the skeleton, which
    /// both bakes share, and band membership comes from `map.along`, which is
    /// fixed by the topology.
    nonisolated private static func interpolated(
        _ low: Prepared, _ high: Prepared, _ t: Float
    ) -> Prepared {
        var profile: [BodyRegion: [BodyBand]] = [:]
        profile.reserveCapacity(low.profile.count)
        for (region, bands) in low.profile {
            guard let other = high.profile[region], other.count == bands.count else {
                profile[region] = bands
                continue
            }
            profile[region] = zip(bands, other).map { first, second in
                BodyBand(
                    centroid: first.centroid + (second.centroid - first.centroid) * t,
                    axis: first.axis,
                    position: first.position + (second.position - first.position) * t,
                    circumference: first.circumference
                        + (second.circumference - first.circumference) * t,
                    vertexCount: first.vertexCount
                )
            }
        }

        return Prepared(
            mesh: BodyBaseMesh(
                positions: zip(low.mesh.positions, high.mesh.positions).map {
                    $0 + ($1 - $0) * t
                },
                normals: low.mesh.normals,
                indices: low.mesh.indices
            ),
            map: low.map,
            profile: profile
        )
    }

    /// The rig for the lean bake. Kept for the tests and diagnostics that want
    /// a body the deformer has not been told anything about.
    static func rig(
        for gender: BodyGender
    ) throws -> (map: BodyRegionMap, profile: [BodyRegion: [BodyBand]]) {
        if let prepared = prepared(for: gender, fatness: 0) {
            return (prepared.map, prepared.profile)
        }
        let mesh = try mesh(for: gender)
        let bones = try BodySkeleton.bones(for: gender)
        let map = BodyRegionMap.build(mesh: mesh, bones: bones)
        return (
            map,
            BodyBandProfile.build(
                mesh: mesh, map: map, bones: bones,
                bandsPerRegion: BodyBandProfile.defaultBandCount
            )
        )
    }

    static func mesh(for gender: BodyGender) throws -> BodyBaseMesh {
        if let cached = bakes[gender] { return cached.lean }
        let name = variantName(gender, variant: "Base")
        guard let data = data(gender, variant: "Base") else {
            throw LoadError.resourceMissing(name)
        }
        return try BodyMeshFile.decode(data)
    }

    private static func variantName(_ gender: BodyGender, variant: String) -> String {
        (gender == .male ? "Male" : "Female") + variant
    }

    private static func data(_ gender: BodyGender, variant: String) -> Data? {
        guard let url = Bundle.main.url(
            forResource: variantName(gender, variant: variant), withExtension: "bodymesh"
        ) else { return nil }
        return try? Data(contentsOf: url)
    }
}

extension BodyBaseMesh {
    /// Positions in metres for a body of the given stature. The baked mesh is
    /// exactly one unit tall, so stature is a single uniform scale.
    func positions(forHeightCm heightCm: Double) -> [SIMD3<Float>] {
        let scale = Float(heightCm / 100)
        return positions.map { $0 * scale }
    }
}
