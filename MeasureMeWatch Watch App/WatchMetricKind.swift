import SwiftUI

/// Lightweight mirror of the app's MetricKind enum for the watchOS target.
/// Based on WidgetMetricKind but without AppEnum conformance.
enum WatchMetricKind: String, CaseIterable, Identifiable {
    case weight, bodyFat, height, leanBodyMass, waist
    case neck, shoulders, bust, chest
    case leftBicep, rightBicep, leftForearm, rightForearm
    case hips, leftThigh, rightThigh, leftCalf, rightCalf

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .weight:       return WatchLocalization.string("Weight")
        case .bodyFat:      return WatchLocalization.string("Body Fat")
        case .height:       return WatchLocalization.string("Height")
        case .leanBodyMass: return WatchLocalization.string("Lean Body Mass")
        case .waist:        return WatchLocalization.string("Waist")
        case .neck:         return WatchLocalization.string("Neck")
        case .shoulders:    return WatchLocalization.string("Shoulders")
        case .bust:         return WatchLocalization.string("Bust")
        case .chest:        return WatchLocalization.string("Chest")
        case .leftBicep:    return WatchLocalization.string("Left Bicep")
        case .rightBicep:   return WatchLocalization.string("Right Bicep")
        case .leftForearm:  return WatchLocalization.string("Left Forearm")
        case .rightForearm: return WatchLocalization.string("Right Forearm")
        case .hips:         return WatchLocalization.string("Hips")
        case .leftThigh:    return WatchLocalization.string("Left Thigh")
        case .rightThigh:   return WatchLocalization.string("Right Thigh")
        case .leftCalf:     return WatchLocalization.string("Left Calf")
        case .rightCalf:    return WatchLocalization.string("Right Calf")
        }
    }

    var shortName: String {
        switch self {
        case .weight:       return WatchLocalization.string("Weight")
        case .bodyFat:      return WatchLocalization.string("Fat")
        case .height:       return WatchLocalization.string("Height")
        case .leanBodyMass: return WatchLocalization.string("Lean")
        case .waist:        return WatchLocalization.string("Waist")
        case .neck:         return WatchLocalization.string("Neck")
        case .shoulders:    return WatchLocalization.string("Shoulders")
        case .bust:         return WatchLocalization.string("Bust")
        case .chest:        return WatchLocalization.string("Chest")
        case .leftBicep:    return WatchLocalization.string("L Bicep")
        case .rightBicep:   return WatchLocalization.string("R Bicep")
        case .leftForearm:  return WatchLocalization.string("L Forearm")
        case .rightForearm: return WatchLocalization.string("R Forearm")
        case .hips:         return WatchLocalization.string("Hips")
        case .leftThigh:    return WatchLocalization.string("L Thigh")
        case .rightThigh:   return WatchLocalization.string("R Thigh")
        case .leftCalf:     return WatchLocalization.string("L Calf")
        case .rightCalf:    return WatchLocalization.string("R Calf")
        }
    }

    var systemImage: String {
        switch self {
        case .weight:                               return "scalemass.fill"
        case .bodyFat:                              return "figure.arms.open"
        case .height:                               return "figure.stand"
        case .leanBodyMass:                         return "figure.strengthtraining.traditional"
        case .waist:                                return "figure.cooldown"
        case .neck:                                 return "person.crop.square"
        case .shoulders:                            return "person.fill"
        case .bust:                                 return "figure.stand.dress"
        case .chest:                                return "figure"
        case .leftBicep, .rightBicep:               return "figure.martial.arts"
        case .leftForearm, .rightForearm:           return "hand.raised.palm.facing"
        case .hips:                                 return "figure.mixed.cardio"
        case .leftThigh, .rightThigh:               return "figure.walk"
        case .leftCalf, .rightCalf:                 return "figure.run"
        }
    }

    // MARK: - Units

    enum UnitCategory { case weight, length, percent }

    var unitCategory: UnitCategory {
        switch self {
        case .weight, .leanBodyMass: return .weight
        case .bodyFat:               return .percent
        default:                     return .length
        }
    }

    func unitSymbol(isMetric: Bool) -> String {
        switch unitCategory {
        case .weight:  return isMetric ? "kg" : "lb"
        case .length:  return isMetric ? "cm" : "in"
        case .percent: return "%"
        }
    }

    func valueForDisplay(fromMetric value: Double, isMetric: Bool) -> Double {
        switch unitCategory {
        case .weight:  return isMetric ? value : value / 0.45359237
        case .length:  return isMetric ? value : value / 2.54
        case .percent: return value
        }
    }

    func formattedDisplayValue(
        _ displayValue: Double,
        isMetric: Bool,
        includeUnit: Bool = true,
        alwaysShowSign: Bool = false
    ) -> String {
        let valueFormat = alwaysShowSign ? "%+.2f" : "%.2f"

        switch unitCategory {
        case .percent:
            return includeUnit
                ? String(format: "\(valueFormat)%%", locale: WatchLocalization.currentLocale, displayValue)
                : String(format: valueFormat, locale: WatchLocalization.currentLocale, displayValue)
        case .weight, .length:
            if includeUnit {
                return String(format: "\(valueFormat)\u{202F}%@", locale: WatchLocalization.currentLocale, displayValue, unitSymbol(isMetric: isMetric))
            }
            return String(format: valueFormat, locale: WatchLocalization.currentLocale, displayValue)
        }
    }

    func formattedMetricValue(
        fromMetric metricValue: Double,
        isMetric: Bool,
        includeUnit: Bool = true,
        alwaysShowSign: Bool = false
    ) -> String {
        formattedDisplayValue(
            valueForDisplay(fromMetric: metricValue, isMetric: isMetric),
            isMetric: isMetric,
            includeUnit: includeUnit,
            alwaysShowSign: alwaysShowSign
        )
    }

    func metricValue(fromDisplay value: Double, isMetric: Bool) -> Double {
        switch unitCategory {
        case .weight:  return isMetric ? value : value * 0.45359237
        case .length:  return isMetric ? value : value * 2.54
        case .percent: return value
        }
    }

    /// Step size for Digital Crown rotation (in display units).
    var crownStep: Double {
        0.1
    }

    /// Reasonable range for Digital Crown input (in display units).
    var displayRange: ClosedRange<Double> {
        switch unitCategory {
        case .weight:  return 20...300
        case .length:  return 10...200
        case .percent: return 1...60
        }
    }

    // MARK: - Trend

    var favorsDecrease: Bool {
        switch self {
        case .weight, .bodyFat, .waist, .hips, .bust: return true
        default: return false
        }
    }

    enum TrendOutcome { case positive, negative, neutral }

    func trendOutcome(from start: Double, to end: Double,
                      goalTarget: Double?, goalDirection: String?) -> TrendOutcome {
        if let target = goalTarget {
            let startDist = abs(target - start)
            let endDist   = abs(target - end)
            if endDist < startDist { return .positive }
            if endDist > startDist { return .negative }
            return .neutral
        }
        let delta = end - start
        if delta == 0 { return .neutral }
        return (favorsDecrease ? delta < 0 : delta > 0) ? .positive : .negative
    }

    // MARK: - HealthKit

    var isHealthKitSynced: Bool {
        switch self {
        case .weight, .bodyFat, .height, .leanBodyMass, .waist: return true
        default: return false
        }
    }
}
