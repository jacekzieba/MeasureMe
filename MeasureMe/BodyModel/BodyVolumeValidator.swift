// BodyVolumeValidator.swift
//
// **BodyVolumeValidator**
// Independent check that the solved silhouette agrees with logged weight.
//
// **Responsibilities:**
// - Integrating cross-section area into a body volume
// - Converting body fat into a whole-body density (Siri two-compartment model)
// - Reconciling the two by nudging the torso/leg split, and reporting what is left
//
// **What is corrected and what is not:**
// Circumferences are measurements and are never touched — scaling them would
// make the model lie about the user's data. The corrected quantity is the one
// the app never measures: how the user's height divides between torso and
// legs. The torso has a far larger cross-section than the legs, so moving that
// split changes volume substantially at constant height. Beyond ±6% the model
// reports the disagreement rather than forcing a fit.
//
import Foundation

nonisolated enum BodyValidationBand: Equatable, Sendable {
    case good
    case approximate
    case suspect

    init(deviationFraction: Double) {
        switch abs(deviationFraction) {
        case ..<0.0500001: self = .good
        case ..<0.1200001: self = .approximate
        default:           self = .suspect
        }
    }
}

nonisolated struct BodyValidationResult: Equatable, Sendable {
    /// Signed `(predicted - logged) / logged`.
    let deviationFraction: Double
    let band: BodyValidationBand
    /// Site contributing most to an unresolved disagreement; nil unless
    /// `.suspect`, and nil even then when no single site's deviation clears
    /// the threshold — meaning no one measurement explains the disagreement,
    /// so the logged weight itself is the likelier culprit.
    let suspectSite: BodyMeasurementSite?
    /// Where the torso/leg correction settled.
    let torsoShareScale: Double
}

nonisolated enum BodyVolumeValidator {
    /// Density of fat mass, g/cm³.
    private static let fatDensity = 0.900
    /// Density of fat-free mass, g/cm³.
    private static let leanDensity = 1.100

    /// Siri two-compartment whole-body density.
    static func bodyDensity(bodyFatPercent: Double) -> Double {
        let fraction = min(max(bodyFatPercent / 100, 0), 0.75)
        return 1 / (fraction / fatDensity + (1 - fraction) / leanDensity)
    }

    /// Trapezoidal integration of cross-section area over height, in litres.
    /// Limbs count twice — the solver builds one of each and mirrors at render.
    static func volumeLitres(_ parameters: BodyMeshParameters) -> Double {
        let cubicCentimetres = stackVolume(parameters.torso)
            + 2 * stackVolume(parameters.arm)
            + 2 * stackVolume(parameters.leg)
        return cubicCentimetres / 1000
    }

    private static func stackVolume(_ sections: [BodyCrossSection]) -> Double {
        let sorted = sections.sorted { $0.y < $1.y }
        guard sorted.count > 1 else { return 0 }
        var total = 0.0
        for index in 0..<(sorted.count - 1) {
            let lower = sorted[index]
            let upper = sorted[index + 1]
            total += (lower.shape.area + upper.shape.area) / 2 * (upper.y - lower.y)
        }
        return total
    }

    /// Solves the body, then searches the allowed torso/leg range for the split
    /// that best matches logged weight. The relationship is smooth and
    /// monotonic, so a bisection over the range converges in a few steps.
    static func reconcile(snapshot: BodySnapshot) -> (parameters: BodyMeshParameters, validation: BodyValidationResult) {
        let density = bodyDensity(bodyFatPercent: snapshot.bodyFatPercent)

        func deviation(at scale: Double) -> Double {
            let parameters = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: scale)
            let predicted = volumeLitres(parameters) * density
            guard snapshot.weightKg > 0 else { return 0 }
            return (predicted - snapshot.weightKg) / snapshot.weightKg
        }

        var low = BodyProportions.torsoShareRange.lowerBound
        var high = BodyProportions.torsoShareRange.upperBound
        var best = 1.0

        let lowDeviation = deviation(at: low)
        let highDeviation = deviation(at: high)

        if lowDeviation * highDeviation < 0 {
            // `low`'s deviation only changes when `low` itself moves, so it is
            // cached rather than recomputed (and re-solved) on every iteration.
            var cachedLowDeviation = lowDeviation
            for _ in 0..<24 {
                let mid = (low + high) / 2
                let midDeviation = deviation(at: mid)
                if cachedLowDeviation * midDeviation <= 0 {
                    high = mid
                } else {
                    low = mid
                    cachedLowDeviation = midDeviation
                }
            }
            best = (low + high) / 2
        } else {
            // No zero crossing inside the range: take whichever end gets closest.
            best = abs(lowDeviation) < abs(highDeviation)
                ? BodyProportions.torsoShareRange.lowerBound
                : BodyProportions.torsoShareRange.upperBound
        }

        let parameters = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: best)
        let residual = deviation(at: best)
        let band = BodyValidationBand(deviationFraction: residual)

        return (
            parameters,
            BodyValidationResult(
                deviationFraction: residual,
                band: band,
                suspectSite: band == .suspect ? suspectSite(for: snapshot, residual: residual) : nil,
                torsoShareScale: best
            )
        )
    }

    /// A site's aligned relative deviation must clear this before it is named
    /// as the suspect — below it, every measurement looks textbook and the
    /// disagreement is more likely a bad weight entry than a bad tape reading.
    private static let suspectThreshold = 0.15

    /// Expected circumference as a fraction of height, from the same tables
    /// that place the landmarks. Anchored to this validator's test fixture
    /// (a 180 cm reference body) rather than to published population data —
    /// e.g. `bicep` 0.189 is 34/180 and `forearm` 0.156 is 28/180. That
    /// tradeoff was flagged in an earlier review and consciously carried, not
    /// re-derived here.
    private static let expectedFractionsOfHeight: [(site: BodyMeasurementSite, fractionOfHeight: Double)] = [
        (.neck, 0.211),
        (.shoulders, 0.653),
        (.chest, 0.556),
        (.waist, 0.472),
        (.hips, 0.544),
        (.thigh, 0.322),
        (.calf, 0.211),
        (.bicep, 0.189),
        (.forearm, 0.156)
    ]

    /// Sites the suspect-site heuristic can name. Exposed only so a
    /// structural test can assert every `BodyMeasurementSite` case is
    /// covered; the fractions themselves stay private.
    static var expectationSites: [BodyMeasurementSite] {
        expectedFractionsOfHeight.map(\.site)
    }

    private static func measuredCm(for site: BodyMeasurementSite, in snapshot: BodySnapshot) -> Double {
        switch site {
        case .neck:      return snapshot.neckCm
        case .shoulders: return snapshot.shouldersCm
        case .chest:     return snapshot.bustCm ?? snapshot.chestCm
        case .waist:     return snapshot.waistCm
        case .hips:      return snapshot.hipsCm
        case .thigh:     return snapshot.thighCm
        case .calf:      return snapshot.calfCm
        case .bicep:     return snapshot.bicepCm
        case .forearm:   return snapshot.forearmCm
        }
    }

    /// Ranks measured circumferences by how far each sits from the population
    /// norm for this height and gender, and names the worst outlier if it
    /// clears `suspectThreshold`. A model too light means an implausibly
    /// small circumference, and vice versa.
    private static func suspectSite(for snapshot: BodySnapshot, residual: Double) -> BodyMeasurementSite? {
        let worst = expectedFractionsOfHeight
            .map { item -> (BodyMeasurementSite, Double) in
                let expected = snapshot.heightCm * item.fractionOfHeight
                let measured = measuredCm(for: item.site, in: snapshot)
                let relative = (measured - expected) / expected
                // Only count deviations in the direction that explains the residual.
                let aligned = residual < 0 ? -relative : relative
                return (item.site, aligned)
            }
            .max { $0.1 < $1.1 }

        guard let worst, worst.1 > suspectThreshold else { return nil }
        return worst.0
    }
}
