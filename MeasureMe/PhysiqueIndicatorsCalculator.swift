import Foundation

@MainActor
final class PhysiqueIndicatorsCalculator {

    struct RatioResult {
        let value: Double
        let category: Category

        enum Category: String {
            case average = "Average"
            case athletic = "Athletic"
            case top = "Top"

            var color: String {
                switch self {
                case .average: return "#60A5FA"
                case .athletic: return "#22C55E"
                case .top: return "#FCA311"
                }
            }
        }
    }

    struct BalanceResult {
        let value: Double
        let category: Category

        enum Category: String {
            case lowerDominant = "Lower-body dominant"
            case balanced = "Balanced frame"
            case upperDominant = "Upper-body dominant"

            var color: String {
                switch self {
                case .lowerDominant: return "#60A5FA"
                case .balanced: return "#22C55E"
                case .upperDominant: return "#FCA311"
                }
            }
        }
    }

    struct VisualBodyFatResult {
        let percent: Double
        let category: Category

        enum Category: String {
            case athletes = "Athletes"
            case fitness = "Fitness"
            case average = "Average"
            case high = "High"

            var color: String {
                switch self {
                case .athletes: return "#22C55E"
                case .fitness: return "#34D399"
                case .average: return "#FCA311"
                case .high: return "#EF4444"
                }
            }
        }
    }

    struct HybridWHtRResult {
        let ratio: Double
        let category: Category

        enum Category: String {
            case visibleDefinition = "Visible definition"
            case softDefinition = "Soft definition"
            case hiddenProportions = "Hidden proportions"

            var color: String {
                switch self {
                case .visibleDefinition: return "#22C55E"
                case .softDefinition: return "#FCA311"
                case .hiddenProportions: return "#EF4444"
                }
            }
        }
    }

    static func calculateSWR(shouldersCm: Double?, waistCm: Double?) -> RatioResult? {
        guard let shouldersCm, let waistCm, shouldersCm > 0, waistCm > 0 else { return nil }
        let ratio = shouldersCm / waistCm
        return RatioResult(value: ratio, category: categoryForThreeTierRatio(ratio, averageUpper: 1.44, athleticUpper: 1.59))
    }

    static func calculateCWR(chestCm: Double?, waistCm: Double?, gender: Gender) -> GenderDependentResult<RatioResult>? {
        guard gender != .notSpecified else { return .requiresGender }
        guard let chestCm, let waistCm, chestCm > 0, waistCm > 0 else { return nil }

        let ratio = chestCm / waistCm
        let category = categoryForThreeTierRatio(ratio, averageUpper: 1.19, athleticUpper: 1.29)
        return .value(RatioResult(value: ratio, category: category))
    }

    static func calculateHWR(hipsCm: Double?, waistCm: Double?, gender: Gender) -> GenderDependentResult<RatioResult>? {
        guard gender != .notSpecified else { return .requiresGender }
        guard let hipsCm, let waistCm, hipsCm > 0, waistCm > 0 else { return nil }

        let ratio = hipsCm / waistCm
        let category = categoryForThreeTierRatio(ratio, averageUpper: 1.34, athleticUpper: 1.49)
        return .value(RatioResult(value: ratio, category: category))
    }

    static func calculateBWR(
        bustCm: Double?,
        chestCm: Double?,
        waistCm: Double?,
        gender: Gender
    ) -> GenderDependentResult<RatioResult>? {
        guard gender != .notSpecified else { return .requiresGender }
        guard let waistCm, waistCm > 0 else { return nil }

        let torsoCm: Double?
        switch gender {
        case .female:
            torsoCm = (bustCm ?? chestCm)
        case .male:
            torsoCm = (chestCm ?? bustCm)
        case .notSpecified:
            return .requiresGender
        }

        guard let torsoCm, torsoCm > 0 else { return nil }

        let ratio = torsoCm / waistCm
        let category = categoryForThreeTierRatio(ratio, averageUpper: 1.19, athleticUpper: 1.29)
        return .value(RatioResult(value: ratio, category: category))
    }

    static func calculateSHR(shouldersCm: Double?, hipsCm: Double?, gender: Gender) -> GenderDependentResult<BalanceResult>? {
        guard gender != .notSpecified else { return .requiresGender }
        guard let shouldersCm, let hipsCm, shouldersCm > 0, hipsCm > 0 else { return nil }

        let ratio = shouldersCm / hipsCm
        let category: BalanceResult.Category
        if ratio < 1.0 {
            category = .lowerDominant
        } else if ratio <= 1.25 {
            category = .balanced
        } else {
            category = .upperDominant
        }

        return .value(BalanceResult(value: ratio, category: category))
    }

    static func classifyBodyFat(percent: Double?, gender: Gender) -> GenderDependentResult<VisualBodyFatResult>? {
        guard let percent, percent >= 0 else { return nil }
        guard gender != .notSpecified else { return .requiresGender }

        let category: VisualBodyFatResult.Category
        switch gender {
        case .male:
            if percent <= 13 {
                category = .athletes
            } else if percent <= 17 {
                category = .fitness
            } else if percent <= 24 {
                category = .average
            } else {
                category = .high
            }
        case .female:
            if percent <= 20 {
                category = .athletes
            } else if percent <= 24 {
                category = .fitness
            } else if percent <= 31 {
                category = .average
            } else {
                category = .high
            }
        case .notSpecified:
            return .requiresGender
        }

        return .value(VisualBodyFatResult(percent: percent, category: category))
    }

    static func classifyRFM(rfm: Double?, gender: Gender) -> GenderDependentResult<VisualBodyFatResult>? {
        guard let rfm else { return nil }
        return classifyBodyFat(percent: rfm, gender: gender)
    }

    static func classifyWHtRVisual(waistCm: Double?, heightCm: Double?) -> HybridWHtRResult? {
        guard let whtr = HealthMetricsCalculator.calculateWHtR(waistCm: waistCm, heightCm: heightCm) else { return nil }
        let category: HybridWHtRResult.Category
        if whtr.ratio <= 0.50 {
            category = .visibleDefinition
        } else if whtr.ratio <= 0.59 {
            category = .softDefinition
        } else {
            category = .hiddenProportions
        }
        return HybridWHtRResult(ratio: whtr.ratio, category: category)
    }

    private static func categoryForThreeTierRatio(
        _ ratio: Double,
        averageUpper: Double,
        athleticUpper: Double
    ) -> RatioResult.Category {
        if ratio <= averageUpper {
            return .average
        }
        if ratio <= athleticUpper {
            return .athletic
        }
        return .top
    }
}
