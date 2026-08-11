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
    /// Fitted once at init — `Superellipse.fitting` numerically integrates a
    /// perimeter, and `reconcile`'s bisection reads `.shape` thousands of
    /// times per call, so this is computed once and stored rather than
    /// recomputed on every access.
    let shape: Superellipse

    init(y: Double, circumferenceCm: Double, aspectRatio: Double, exponent: Double) {
        self.y = y
        self.circumferenceCm = circumferenceCm
        self.aspectRatio = aspectRatio
        self.exponent = exponent
        self.shape = Superellipse.fitting(
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

        // Return the endpoints verbatim. `first + (second - first) * 1` is not
        // bit-identical to `second` in IEEE 754, and the morph must land exactly
        // on the measured bodies at both ends of the slider — an approximation
        // there would mean the silhouette never quite shows either real state.
        if clamped <= 0 { return start }
        if clamped >= 1 { return end }

        func blend(_ a: [BodyCrossSection], _ b: [BodyCrossSection]) -> [BodyCrossSection] {
            // A length mismatch would silently truncate to the shorter side and
            // drop levels mid-morph, so state the invariant rather than assume it.
            precondition(a.count == b.count, "Interpolating bodies with different level counts")
            return zip(a, b).map { first, second in
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
