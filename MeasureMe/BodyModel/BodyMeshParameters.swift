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
    /// The body this was solved for.
    ///
    /// The deformer needs it to look landmark heights up in the same table the
    /// solver used. Re-deriving them as `.male` regardless put the female waist
    /// 1.5% of stature below the anchor the solver had placed, so the target
    /// read off the Hermite curve running down to the hips — and the hip
    /// measurement leaked into the waist, moving it by up to 4%.
    let gender: BodyGender
    /// How much of the chest girth reads as forward projection rather than as
    /// thickness spread evenly round the ribcage. 0.35 is the baked shape.
    ///
    /// The same number of centimetres round a chest can be a pectoral shelf or
    /// a barrel of fat, and a bust can be full or flat; girth alone cannot tell
    /// them apart, so it renders every chest as the same slightly rounded box.
    /// See `BodyMeshSolver.chestProjection` for where the value comes from.
    let chestProjection: Double
    /// The same idea one landmark down: how much of the waist girth hangs in
    /// front rather than wrapping evenly. 0.35 is the baked shape.
    ///
    /// Without it a 128 cm waist renders as a barrel — measured at 15.8 cm in
    /// front of the section's centre and 15.8 cm behind, on a body that should
    /// be carrying most of it forward.
    let bellyProjection: Double
    /// How far toward the heavy bake this body sits, 0 lean and 1 heavy.
    ///
    /// Chooses the *kind* of body the girth pass then resizes. See
    /// `BodyMeshSolver.fatness` and `BodyBaseMeshProvider`.
    let fatness: Double

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
            heightCm: start.heightCm + (end.heightCm - start.heightCm) * clamped,
            gender: start.gender,
            chestProjection: start.chestProjection
                + (end.chestProjection - start.chestProjection) * clamped,
            bellyProjection: start.bellyProjection
                + (end.bellyProjection - start.bellyProjection) * clamped,
            fatness: start.fatness + (end.fatness - start.fatness) * clamped
        )
    }
}
