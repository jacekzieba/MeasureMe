// BodyGeometryBuilder.swift
//
// **BodyGeometryBuilder**
// Turns solved cross-sections into SceneKit geometry.
//
// **Responsibilities:**
// - Emitting one ring of vertices per cross-section
// - Stitching neighbouring rings into triangle strips
// - Producing an `SCNGeometry` with a position source and a triangle index element
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
import Foundation
import SceneKit

nonisolated enum BodyGeometryBuilder {
    /// Vertices per cross-section ring.
    static let segmentsPerRing = 32

    /// Horizontal offsets, in cm, applied to mirrored limbs.
    private static let armOffsetCm = 22.0
    private static let legOffsetCm = 9.0

    /// Every ring of the body, in a fixed order: torso, both arms, both legs.
    private static func rings(for parameters: BodyMeshParameters) -> [(section: BodyCrossSection, xOffsetCm: Double)] {
        parameters.torso.map { ($0, 0.0) }
            + parameters.arm.map { ($0, -armOffsetCm) }
            + parameters.arm.map { ($0, armOffsetCm) }
            + parameters.leg.map { ($0, -legOffsetCm) }
            + parameters.leg.map { ($0, legOffsetCm) }
    }

    static func positions(for parameters: BodyMeshParameters) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(rings(for: parameters).count * segmentsPerRing)

        for ring in rings(for: parameters) {
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

    static func geometry(for parameters: BodyMeshParameters) -> SCNGeometry {
        let vertices = positions(for: parameters)
        let source = SCNGeometrySource(
            vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        let element = SCNGeometryElement(
            indices: indices(for: parameters),
            primitiveType: .triangles
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        return geometry
    }
}
