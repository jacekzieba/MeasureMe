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
            // Knee girth sits just under maximum calf girth; the ankle well under it.
            case .calf:     return snapshot.calfCm
            case .knee:     return snapshot.calfCm * 0.93
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
            anchors: [.ankle, .calf, .knee, .crotch],
            y: anchorY,
            circumference: { $0 == .crotch ? snapshot.thighCm : anchorCircumference($0) },
            gender: gender
        )

        // The shoulder circumference is measured around the deltoids, so it
        // already encloses the top of the arm; a separate arm stack rising
        // into that same slab would count that tissue twice. The chest is
        // measured with the arms hanging clear, so anchoring the arm's top
        // there instead keeps it below the shoulder slab.
        let shoulderY = anchorY(.shoulder)
        let arm = buildLinearStack(
            from: (y: shoulderY - (shoulderY - anchorY(.waist)) * 1.55, circumference: snapshot.forearmCm * 0.78),
            mid: (y: shoulderY - (shoulderY - anchorY(.waist)) * 0.85, circumference: snapshot.forearmCm),
            to: (y: anchorY(.chest), circumference: snapshot.bicepCm)
        )

        return BodyMeshParameters(
            torso: torso, arm: arm, leg: leg, heightCm: height, gender: gender,
            chestProjection: chestProjection(snapshot),
            bellyProjection: bellyProjection(snapshot),
            fatness: fatness(snapshot)
        )
    }

    /// How much of the chest girth is carried in front of the ribcage rather
    /// than spread evenly round it. 0 is a barrel, 1 projects hard forward, and
    /// **0.35 is the baked mesh's own shape** — a body scoring 0.35 is left
    /// exactly as the deformer's girth pass left it.
    ///
    /// **Women: measured, not inferred.** The model already requires a woman to
    /// log both `.chest` and `.bust`, which is the bra-fitting pair, so their
    /// difference is breast projection read straight off the tape. Until now
    /// `chestCm` was collected from women and then thrown away — the solver
    /// took `bustCm ?? chestCm` and never looked at it.
    ///
    /// **Men: inferred, because nothing measures a pectoral.** Two signals
    /// agree on the answer often enough to use: body fat, and the chest-to-waist
    /// taper. A lean man whose chest is a third wider than his waist carries
    /// that girth as muscle in front; a heavy man whose chest and waist are
    /// close carries it as fat all the way round. Either signal alone is
    /// fooled — a heavy powerlifter has both a high body fat and a real chest,
    /// a skinny man has a low body fat and no chest at all — so they are
    /// averaged rather than gated on each other.
    /// Which of the two bakes this body is, 0 lean and 1 heavy.
    ///
    /// **Why body fat and not BMI.** The bakes differ in softness, not in size,
    /// and the girth pass handles size. A heavy powerlifter and a heavy sedentary
    /// man can share a BMI and must not share a shape; their body fat does not.
    ///
    /// The neutral points are where each lean bake stops being a fair likeness —
    /// MakeHuman's unmodified weight axis is a normally-built adult, not an
    /// athlete — and the far end is where the fat target stops adding.
    static func fatness(_ snapshot: BodySnapshot) -> Double {
        let (neutral, full) = snapshot.gender == .male ? (15.0, 38.0) : (24.0, 48.0)
        return min(max((snapshot.bodyFatPercent - neutral) / (full - neutral), 0), 1)
    }

    /// How much of the waist girth is carried in front of the spine rather than
    /// wrapped evenly around it. Same scale as `chestProjection`, same neutral.
    ///
    /// Fat above the waist threshold goes to the abdomen, and a waist that has
    /// caught up with the hips says it went to the front rather than the seat.
    /// Neither signal alone is enough: a lean pear-shaped body scores low on
    /// fat and high on nothing, and a heavy body can still carry it low.
    static func bellyProjection(_ snapshot: BodySnapshot) -> Double {
        func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }
        let neutralFat = snapshot.gender == .male ? 18.0 : 28.0
        let fat = clamped((snapshot.bodyFatPercent - neutralFat) / 18)
        let apple = snapshot.hipsCm > 0
            ? clamped((snapshot.waistCm / snapshot.hipsCm - 0.85) / 0.25)
            : 0
        return clamped(0.35 + 0.55 * (0.65 * fat + 0.35 * apple))
    }

    static func chestProjection(_ snapshot: BodySnapshot) -> Double {
        func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }

        switch snapshot.gender {
        case .female:
            guard let bust = snapshot.bustCm, snapshot.chestCm > 0 else { return 0.35 }
            // Bra sizing runs about 2.5 cm of difference per cup. Zero apart is
            // a flat chest; 16 cm is a very full one.
            return clamped(0.08 + 0.85 * (bust - snapshot.chestCm) / 16)
        case .male:
            guard snapshot.waistCm > 0 else { return 0.35 }
            let leanness = clamped((25 - snapshot.bodyFatPercent) / 13)
            let taper = clamped((snapshot.chestCm / snapshot.waistCm - 1.05) / 0.25)
            return clamped(0.08 + 0.62 * (leanness + taper) / 2)
        }
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
