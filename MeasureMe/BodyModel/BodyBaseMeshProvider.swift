// BodyBaseMeshProvider.swift
//
// **BodyBaseMeshProvider**
// Loads a baked base mesh out of the app bundle, once per gender.
//
// **Responsibilities:**
// - Resolving a gender to its bundled `.bodymesh` resource
// - Caching the decoded mesh for the lifetime of the process
// - Scaling the unit-height mesh to a measured stature
//
// **Why the cache is not a weak one:**
// Two meshes at 13 380 vertices are a little over a megabyte in total and both
// are needed for as long as the screen is reachable. Re-decoding on every
// appearance would trade that megabyte for a hitch on a user-visible transition.
//
import Foundation
import simd

enum BodyBaseMeshProvider {
    enum LoadError: Error, Equatable {
        case resourceMissing(String)
    }

    private static var cache: [BodyGender: BodyBaseMesh] = [:]
    private static var rigs: [BodyGender: (map: BodyRegionMap, profile: [BodyRegion: [BodyBand]])] = [:]

    /// Region map and band profile, built once per gender. None of it depends
    /// on the user's measurements, so it never has to be rebuilt as they change.
    static func rig(
        for gender: BodyGender
    ) throws -> (map: BodyRegionMap, profile: [BodyRegion: [BodyBand]]) {
        if let cached = rigs[gender] { return cached }
        let mesh = try mesh(for: gender)
        let bones = try BodySkeleton.bones(for: gender)
        let map = BodyRegionMap.build(mesh: mesh, bones: bones)
        let built = (
            map,
            BodyBandProfile.build(
                mesh: mesh, map: map, bones: bones,
                bandsPerRegion: BodyBandProfile.defaultBandCount
            )
        )
        rigs[gender] = built
        return built
    }

    /// Everything a render needs, built together so it can cross the actor
    /// boundary in one hop.
    struct Prepared: Sendable {
        let mesh: BodyBaseMesh
        let map: BodyRegionMap
        let profile: [BodyRegion: [BodyBand]]
    }

    /// Decodes the asset and builds the rig **off the main actor**, then caches.
    ///
    /// Measured on the simulator: decoding is 15 ms, the region map 121 ms and
    /// the band profile 18 ms. Run synchronously on the main actor — which is
    /// where this used to happen, the module defaulting to `MainActor` — that
    /// blocks the very thread a progress indicator needs in order to animate,
    /// so a spinner alone would have sat frozen.
    static func prepare(for gender: BodyGender) async {
        guard rigs[gender] == nil else { return }

        let name = gender == .male ? "MaleBase" : "FemaleBase"
        guard let url = Bundle.main.url(forResource: name, withExtension: "bodymesh"),
              let data = try? Data(contentsOf: url),
              let bones = try? BodySkeleton.bones(for: gender)
        else { return }

        let built = await Task.detached(priority: .userInitiated) { () -> Prepared? in
            guard let mesh = try? BodyMeshFile.decode(data) else { return nil }
            let map = BodyRegionMap.build(mesh: mesh, bones: bones)
            return Prepared(
                mesh: mesh,
                map: map,
                profile: BodyBandProfile.build(
                    mesh: mesh, map: map, bones: bones,
                    bandsPerRegion: BodyBandProfile.defaultBandCount
                )
            )
        }.value

        guard let built else { return }
        cache[gender] = built.mesh
        rigs[gender] = (built.map, built.profile)
    }

    /// The prepared rig, or nil while `prepare` has not finished. Callers render
    /// nothing rather than blocking to build it.
    static func prepared(for gender: BodyGender) -> Prepared? {
        guard let mesh = cache[gender], let rig = rigs[gender] else { return nil }
        return Prepared(mesh: mesh, map: rig.map, profile: rig.profile)
    }

    static func mesh(for gender: BodyGender) throws -> BodyBaseMesh {
        if let cached = cache[gender] { return cached }

        let name = gender == .male ? "MaleBase" : "FemaleBase"
        guard let url = Bundle.main.url(forResource: name, withExtension: "bodymesh") else {
            throw LoadError.resourceMissing(name)
        }
        let mesh = try BodyMeshFile.decode(Data(contentsOf: url))
        cache[gender] = mesh
        return mesh
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
