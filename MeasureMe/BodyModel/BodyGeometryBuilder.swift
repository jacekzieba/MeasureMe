// BodyGeometryBuilder.swift
//
// **BodyGeometryBuilder**
// Turns solved cross-sections into SceneKit geometry.
//
// **Responsibilities:**
// - Emitting one ring of vertices per cross-section
// - Stitching neighbouring rings into triangle strips
// - Producing an `SCNGeometry` with position, normal and triangle-index sources
//
// **Why topology is fixed:**
// Ring count and segment count never depend on the body's dimensions, so the
// morph can swap the position buffer of an existing geometry instead of
// rebuilding it. Everything here is mechanical — no body knowledge lives in
// this file.
//
// Positions are emitted in metres (SceneKit's convention) while the model
// works in centimetres.
//
// **Why normals are accumulated rather than derived analytically:**
// SceneKit does not synthesise normals for hand-built geometry, and the
// `.physicallyBased` material lights the mesh entirely from its normals — no
// normal source means a black mannequin regardless of the scene's lights.
// Summing each triangle's face normal into its three vertices and
// normalising (standard smooth shading) handles the stack boundaries, the
// calf's local maximum and the mirrored limb offsets uniformly, without a
// parallel analytic formula that could drift out of sync with the triangles
// `indices(for:)` actually draws.
//
import Foundation
import SceneKit
import simd

nonisolated enum BodyGeometryBuilder {
    /// Vertices per cross-section ring.
    static let segmentsPerRing = 32

    /// Horizontal offsets, in cm, applied to mirrored limbs.
    private static let armOffsetCm = 22.0
    private static let legOffsetCm = 9.0

    /// Every ring of the body, in a fixed order: torso, both arms, both legs.
    private static func rings(for parameters: BodyMeshParameters) -> [(section: BodyCrossSection, xOffsetCm: Double)] {
        let torsoRings: [(section: BodyCrossSection, xOffsetCm: Double)] = parameters.torso.map { ($0, 0.0) }
        let leftArm: [(section: BodyCrossSection, xOffsetCm: Double)] = parameters.arm.map { ($0, -armOffsetCm) }
        let rightArm: [(section: BodyCrossSection, xOffsetCm: Double)] = parameters.arm.map { ($0, armOffsetCm) }
        let leftLeg: [(section: BodyCrossSection, xOffsetCm: Double)] = parameters.leg.map { ($0, -legOffsetCm) }
        let rightLeg: [(section: BodyCrossSection, xOffsetCm: Double)] = parameters.leg.map { ($0, legOffsetCm) }
        return torsoRings + leftArm + rightArm + leftLeg + rightLeg
    }

    static func positions(for parameters: BodyMeshParameters) -> [SIMD3<Float>] {
        let allRings = rings(for: parameters)
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(allRings.count * segmentsPerRing)

        for ring in allRings {
            let shape = ring.section.shape
            let power = 2 / shape.exponent
            for segment in 0..<segmentsPerRing {
                let angle = (2 * Double.pi) * Double(segment) / Double(segmentsPerRing)
                let cosA = cos(angle)
                let sinA = sin(angle)
                let x = shape.semiAxisA * (cosA < 0 ? -1 : 1) * pow(abs(cosA), power)
                let z = shape.semiAxisB * (sinA < 0 ? -1 : 1) * pow(abs(sinA), power)
                result.append(SIMD3<Float>(
                    Float((x + ring.xOffsetCm) / 100),
                    Float(ring.section.y / 100),
                    Float(z / 100)
                ))
            }
        }
        return result
    }

    static func indices(for parameters: BodyMeshParameters) -> [Int32] {
        // Stack boundaries must not be stitched across — each stack is closed
        // on its own, or the last torso ring would connect to the first arm ring.
        let stackLengths = [
            parameters.torso.count,
            parameters.arm.count, parameters.arm.count,
            parameters.leg.count, parameters.leg.count
        ]

        var result: [Int32] = []
        var ringBase = 0
        for length in stackLengths {
            for ring in 0..<max(length - 1, 0) {
                for segment in 0..<segmentsPerRing {
                    let next = (segment + 1) % segmentsPerRing
                    let lower = Int32((ringBase + ring) * segmentsPerRing)
                    let upper = Int32((ringBase + ring + 1) * segmentsPerRing)

                    let a = lower + Int32(segment)
                    let b = lower + Int32(next)
                    let c = upper + Int32(segment)
                    let d = upper + Int32(next)

                    result.append(contentsOf: [a, c, b])
                    result.append(contentsOf: [b, c, d])
                }
            }
            ringBase += length
        }
        return result
    }

    /// One smoothed normal per vertex, built by accumulating the face normal
    /// of every triangle that touches it and normalising. Matches
    /// `positions(for:)` exactly in count and order, as SceneKit pairs
    /// geometry sources by index.
    static func normals(for parameters: BodyMeshParameters) -> [SIMD3<Float>] {
        let vertices = positions(for: parameters)
        let triangleIndices = indices(for: parameters)

        var accumulated = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        var triangle = 0
        while triangle + 2 < triangleIndices.count {
            let i0 = Int(triangleIndices[triangle])
            let i1 = Int(triangleIndices[triangle + 1])
            let i2 = Int(triangleIndices[triangle + 2])

            let faceNormal = cross(vertices[i1] - vertices[i0], vertices[i2] - vertices[i0])
            accumulated[i0] += faceNormal
            accumulated[i1] += faceNormal
            accumulated[i2] += faceNormal

            triangle += 3
        }

        return accumulated.map { normal in
            let length = simd_length(normal)
            // A vertex touched only by degenerate triangles would otherwise
            // normalise to NaN; fall back to a sane unit vector instead.
            return length > 0 ? normal / length : SIMD3<Float>(0, 1, 0)
        }
    }

    static func geometry(for parameters: BodyMeshParameters) -> SCNGeometry {
        let vertices = positions(for: parameters)
        let vertexSource = SCNGeometrySource(
            vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        let normalSource = SCNGeometrySource(
            normals: normals(for: parameters).map { SCNVector3($0.x, $0.y, $0.z) }
        )
        let element = SCNGeometryElement(
            indices: indices(for: parameters),
            primitiveType: .triangles
        )
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        return geometry
    }
}
