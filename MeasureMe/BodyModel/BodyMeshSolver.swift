// BodyMeshSolver.swift
//
// **BodyMeshSolver**
// Turns a `BodySnapshot` into the stack of cross-sections that describes it.
//
// **Responsibilities:**
// - Placing measured circumferences at their anthropometric heights
// - Filling the levels between anchors with monotone interpolation
// - Applying the torso/leg split correction supplied by the volume validator
//
// **The invariant this file exists to protect:**
// Every measured circumference must survive to the rendered mesh unchanged.
// Anchors are generated as mesh levels rather than sampled onto a fixed grid,
// so a measurement is never rounded onto a neighbouring level. Values between
// anchors are guesses; the anchors themselves are data.
//
// **Why monotone (Fritsch-Carlson) and not a cubic spline:**
// A cubic spline overshoots between anchors, which shows up as a visible
// ripple between the waist and the hips. Monotone interpolation cannot
// overshoot.
//
import Foundation

nonisolated enum BodyMeshSolver {
    /// Levels inserted between each pair of anchors.
    private static let levelsBetweenAnchors = 2

    /// Torso anchors, bottom to top.
    private static let torsoAnchors: [BodyLandmark] = [.crotch, .hip, .waist, .chest, .shoulder, .neck, .crown]

    static func solve(snapshot: BodySnapshot, torsoShareScale: Double = 1.0) -> BodyMeshParameters {
        let height = snapshot.heightCm
        let gender = snapshot.gender
        let scale = min(max(torsoShareScale, BodyProportions.torsoShareRange.lowerBound),
                        BodyProportions.torsoShareRange.upperBound)

        // The crotch is the pivot: scaling the torso share moves it, which
        // lengthens the torso and shortens the legs (or the reverse) while
        // total height stays exactly as measured.
        let nominalCrotch = BodyProportions.heightFraction(.crotch, gender: gender)
        let crotchFraction = nominalCrotch / scale

        /// Landmark height in cm, with the torso compressed or stretched
        /// against the moved crotch and the crown pinned at full height.
        func anchorY(_ landmark: BodyLandmark) -> Double {
            let nominal = BodyProportions.heightFraction(landmark, gender: gender)
            guard landmark != .crown else { return height }
            guard nominal > nominalCrotch else {
                // Below the crotch: leg landmarks compress toward the floor.
                return height * nominal * (crotchFraction / nominalCrotch)
            }
            // Above the crotch: remap [nominalCrotch, 1] onto [crotchFraction, 1].
            let progress = (nominal - nominalCrotch) / (1 - nominalCrotch)
            return height * (crotchFraction + progress * (1 - crotchFraction))
        }

        /// Measured circumference for each torso anchor.
        func anchorCircumference(_ landmark: BodyLandmark) -> Double {
            switch landmark {
            case .crotch:   return snapshot.thighCm * 1.9   // two thighs meeting
            case .hip:      return snapshot.hipsCm
            case .waist:    return snapshot.waistCm
            case .chest:    return snapshot.bustCm ?? snapshot.chestCm
            case .shoulder: return snapshot.shouldersCm
            case .neck:     return snapshot.neckCm
            case .crown:    return snapshot.neckCm * 0.55   // taper to a rounded top
            case .knee:     return snapshot.calfCm * 1.02
            case .ankle:    return snapshot.calfCm * 0.72
            }
        }

        let torso = buildStack(
            anchors: torsoAnchors,
            y: anchorY,
            circumference: anchorCircumference,
            gender: gender
        )

        // Limbs are simple tapered tubes between two anchors each.
        let leg = buildStack(
            anchors: [.ankle, .knee, .crotch],
            y: anchorY,
            circumference: { $0 == .crotch ? snapshot.thighCm : anchorCircumference($0) },
            gender: gender
        )

        let shoulderY = anchorY(.shoulder)
        let arm = buildLinearStack(
            from: (y: shoulderY - (shoulderY - anchorY(.waist)) * 1.55, circumference: snapshot.forearmCm * 0.78),
            mid: (y: shoulderY - (shoulderY - anchorY(.waist)) * 0.85, circumference: snapshot.forearmCm),
            to: (y: shoulderY - (shoulderY - anchorY(.waist)) * 0.10, circumference: snapshot.bicepCm)
        )

        return BodyMeshParameters(torso: torso, arm: arm, leg: leg, heightCm: height)
    }

    /// Builds a level stack in which every anchor is itself a level.
    private static func buildStack(
        anchors: [BodyLandmark],
        y: (BodyLandmark) -> Double,
        circumference: (BodyLandmark) -> Double,
        gender: BodyGender
    ) -> [BodyCrossSection] {
        let knots = anchors.map { landmark in
            (
                y: y(landmark),
                circumference: circumference(landmark),
                aspect: BodyProportions.aspectRatio(landmark, gender: gender),
                exponent: BodyProportions.exponent(landmark)
            )
        }
        let slopes = monotoneSlopes(
            xs: knots.map(\.y),
            ys: knots.map(\.circumference)
        )

        var sections: [BodyCrossSection] = []
        for index in knots.indices {
            let knot = knots[index]
            // The anchor level carries the measurement verbatim.
            sections.append(BodyCrossSection(
                y: knot.y,
                circumferenceCm: knot.circumference,
                aspectRatio: knot.aspect,
                exponent: knot.exponent
            ))

            guard index + 1 < knots.count else { continue }
            let next = knots[index + 1]
            for step in 1...levelsBetweenAnchors {
                let fraction = Double(step) / Double(levelsBetweenAnchors + 1)
                let levelY = knot.y + (next.y - knot.y) * fraction
                sections.append(BodyCrossSection(
                    y: levelY,
                    circumferenceCm: hermite(
                        x: levelY,
                        x0: knot.y, x1: next.y,
                        y0: knot.circumference, y1: next.circumference,
                        m0: slopes[index], m1: slopes[index + 1]
                    ),
                    aspectRatio: knot.aspect + (next.aspect - knot.aspect) * fraction,
                    exponent: knot.exponent + (next.exponent - knot.exponent) * fraction
                ))
            }
        }
        return sections
    }

    /// Three-knot tube used for the arm, which has no anthropometric landmarks.
    private static func buildLinearStack(
        from start: (y: Double, circumference: Double),
        mid: (y: Double, circumference: Double),
        to end: (y: Double, circumference: Double)
    ) -> [BodyCrossSection] {
        [start, mid, end].map {
            BodyCrossSection(y: $0.y, circumferenceCm: $0.circumference, aspectRatio: 1.0, exponent: 2.0)
        }
    }

    /// Fritsch-Carlson slope limiting — guarantees no overshoot between knots.
    private static func monotoneSlopes(xs: [Double], ys: [Double]) -> [Double] {
        let count = xs.count
        guard count > 1 else { return [0] }

        var secants: [Double] = []
        for index in 0..<(count - 1) {
            secants.append((ys[index + 1] - ys[index]) / (xs[index + 1] - xs[index]))
        }

        var slopes = [Double](repeating: 0, count: count)
        slopes[0] = secants[0]
        slopes[count - 1] = secants[count - 2]
        for index in 1..<(count - 1) {
            // A sign change means a local extremum; a zero slope pins it there.
            slopes[index] = secants[index - 1] * secants[index] <= 0
                ? 0
                : (secants[index - 1] + secants[index]) / 2
        }

        for index in 0..<(count - 1) where secants[index] == 0 {
            slopes[index] = 0
            slopes[index + 1] = 0
        }

        for index in 0..<(count - 1) where secants[index] != 0 {
            let alpha = slopes[index] / secants[index]
            let beta = slopes[index + 1] / secants[index]
            let magnitude = alpha * alpha + beta * beta
            if magnitude > 9 {
                let tau = 3 / magnitude.squareRoot()
                slopes[index] = tau * alpha * secants[index]
                slopes[index + 1] = tau * beta * secants[index]
            }
        }
        return slopes
    }

    /// Cubic Hermite evaluation between two knots.
    private static func hermite(
        x: Double, x0: Double, x1: Double,
        y0: Double, y1: Double, m0: Double, m1: Double
    ) -> Double {
        let h = x1 - x0
        let t = (x - x0) / h
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * y0
            + (t3 - 2 * t2 + t) * h * m0
            + (-2 * t3 + 3 * t2) * y1
            + (t3 - t2) * h * m1
    }
}
