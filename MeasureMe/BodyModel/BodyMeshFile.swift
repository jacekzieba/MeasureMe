// BodyMeshFile.swift
//
// **BodyMeshFile**
// Decoder for the baked `.bodymesh` assets.
//
// **Responsibilities:**
// - Validating the header before trusting any offset
// - Producing plain Swift arrays the deformer and renderer can both use
//
// **Why a private format rather than OBJ or USDZ:**
// The mesh has to be reachable as a flat position array — the morph rewrites
// every vertex per frame — so a loader that hands back an opaque scene graph
// would only have to be unpacked again. Parsing 13 380 ASCII vertices at launch
// also costs roughly 50 000 text-to-float conversions, where this is a memcpy.
//
// **Why little-endian is assumed rather than converted:**
// Every Apple target is little-endian, and the writer is `tools/bodymesh/bake.py`
// in this same repository. Byte-swapping here would be dead code that could
// never be tested.
//
import Foundation
import simd

nonisolated struct BodyBaseMesh: Equatable, Sendable {
    /// Feet at y = 0, total height exactly 1, centred in X and Z.
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [Int32]
}

nonisolated enum BodyMeshFile {
    enum DecodeError: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
    }

    private static let magic = Array("BMSH".utf8)
    private static let headerSize = 16
    private static let currentVersion: UInt32 = 1

    static func decode(_ data: Data) throws -> BodyBaseMesh {
        guard data.count >= headerSize else { throw DecodeError.truncated }

        // `withUnsafeBytes` on a sliced Data would otherwise index from the
        // slice's own start while `count` reports the slice length — the two
        // agree here only because the buffer is rebased first.
        let data = Data(data)

        return try data.withUnsafeBytes { raw in
            guard Array(raw[0..<4]) == magic else { throw DecodeError.badMagic }

            let version = raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            guard version == currentVersion else { throw DecodeError.unsupportedVersion(version) }

            let vertexCount = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            let indexCount = Int(raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self))

            let vectorBytes = vertexCount * 12
            let expected = headerSize + vectorBytes * 2 + indexCount * 4
            guard data.count == expected else { throw DecodeError.truncated }

            func vectors(at offset: Int) -> [SIMD3<Float>] {
                (0..<vertexCount).map { index in
                    let base = offset + index * 12
                    return SIMD3<Float>(
                        raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                        raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)
                    )
                }
            }

            let indicesOffset = headerSize + vectorBytes * 2
            return BodyBaseMesh(
                positions: vectors(at: headerSize),
                normals: vectors(at: headerSize + vectorBytes),
                indices: (0..<indexCount).map {
                    Int32(raw.loadUnaligned(fromByteOffset: indicesOffset + $0 * 4, as: UInt32.self))
                }
            )
        }
    }
}
