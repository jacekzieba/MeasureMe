// BodyMeshParameters.swift
//
// **BodyMeshParameters**
// The solved description of one body, and the unit the morph interpolates.
//
// **Responsibilities:**
// - Holding the stack of cross-sections for torso, arm and leg
// - Interpolating between two solved bodies
//
// **Why the morph interpolates this and not vertices:**
// Interpolating parameters keeps topology fixed and guarantees every
// intermediate state is a valid body, so the renderer only ever swaps
// position buffers.
//
import Foundation

nonisolated struct BodyCrossSection: Equatable, Sendable {
    /// Height above the floor, in cm.
    let y: Double
    let circumferenceCm: Double
    /// Depth over width.
    let aspectRatio: Double
    let exponent: Double

    var shape: Superellipse {
        Superellipse.fitting(
            circumference: circumferenceCm,
            aspectRatio: aspectRatio,
            exponent: exponent
        )
    }
}

nonisolated struct BodyMeshParameters: Equatable, Sendable {
    /// Bottom-to-top stack of torso sections, from crotch to crown.
    let torso: [BodyCrossSection]
    /// One arm, mirrored at render time.
    let arm: [BodyCrossSection]
    /// One leg, mirrored at render time.
    let leg: [BodyCrossSection]
    let heightCm: Double

    /// Linear blend of two solved bodies. `t` is clamped to `0...1`.
    static func interpolated(
        from start: BodyMeshParameters,
        to end: BodyMeshParameters,
        t: Double
    ) -> BodyMeshParameters {
        let clamped = min(max(t, 0), 1)

        func blend(_ a: [BodyCrossSection], _ b: [BodyCrossSection]) -> [BodyCrossSection] {
            // Both sides are solved with the same level count, so zip is safe.
            zip(a, b).map { first, second in
                BodyCrossSection(
                    y: first.y + (second.y - first.y) * clamped,
                    circumferenceCm: first.circumferenceCm
                        + (second.circumferenceCm - first.circumferenceCm) * clamped,
                    aspectRatio: first.aspectRatio
                        + (second.aspectRatio - first.aspectRatio) * clamped,
                    exponent: first.exponent
                        + (second.exponent - first.exponent) * clamped
                )
            }
        }

        return BodyMeshParameters(
            torso: blend(start.torso, end.torso),
            arm: blend(start.arm, end.arm),
            leg: blend(start.leg, end.leg),
            heightCm: start.heightCm + (end.heightCm - start.heightCm) * clamped
        )
    }
}
