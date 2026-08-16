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
