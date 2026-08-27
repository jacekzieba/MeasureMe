// BodyBaseMeshProvider.swift
//
// **BodyBaseMeshProvider**
// Loads the baked base meshes out of the app bundle and blends them.
//
// **Responsibilities:**
// - Resolving a gender to its bundled `.bodymesh` resources
// - Blending the lean and heavy bakes by how much fat the body carries
// - Caching the decoded meshes and the derived rig for the lifetime of the process
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
// **Why the cache is not a weak one:**
// Four meshes at 13 380 vertices are a little over two megabytes and all of them
// are needed for as long as the screen is reachable. Re-decoding on every
// appearance would trade that for a hitch on a user-visible transition.
//
import Foundation
import simd

enum BodyBaseMeshProvider {
    enum LoadError: Error, Equatable {
        case resourceMissing(String)
    }

    /// The lean and heavy bakes for one gender, plus everything derived from
    /// the topology rather than from the positions.
    private struct Bakes {
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
    /// Blended meshes and their profiles, keyed by gender and quantised
    /// fatness. Quantised because the morph slider sweeps fatness continuously
    /// and rebuilding a band profile costs 18 ms; 32 steps is finer than the
    /// eye and turns a per-frame rebuild into at most 32 of them.
    private static var blends: [BlendKey: Prepared] = [:]

    private struct BlendKey: Hashable {
        let gender: BodyGender
        let step: Int
    }

    private static let blendSteps = 32

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
        _ = prepared(for: gender, fatness: 0)
    }

    /// The prepared rig at a given fatness, or nil while `prepare` has not
    /// finished. Callers render nothing rather than blocking to build it.
    ///
    /// `fatness` is 0 for the lean bake and 1 for the heavy one; see
    /// `BodyMeshSolver.fatness` for where the number comes from.
    static func prepared(for gender: BodyGender, fatness: Double = 0) -> Prepared? {
        guard let bakes = bakes[gender] else { return nil }

        let step = Int((min(max(fatness, 0), 1) * Double(blendSteps)).rounded())
        let key = BlendKey(gender: gender, step: step)
        if let cached = blends[key] { return cached }

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

        let prepared = Prepared(
            mesh: blended,
            map: bakes.map,
            profile: BodyBandProfile.build(
                mesh: blended, map: bakes.map, bones: bakes.bones,
                bandsPerRegion: BodyBandProfile.defaultBandCount
            )
        )
        blends[key] = prepared
        return prepared
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

    /// The heavy bake on its own, for the tests that compare the two.
    static func heavyMesh(for gender: BodyGender) throws -> BodyBaseMesh {
        if let cached = bakes[gender] { return cached.heavy }
        let name = variantName(gender, variant: "Heavy")
        guard let data = data(gender, variant: "Heavy") else {
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
