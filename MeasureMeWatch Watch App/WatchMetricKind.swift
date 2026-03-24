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
        case .weight:       return String(localized: "Weight", table: "Watch")
        case .bodyFat:      return String(localized: "Body Fat", table: "Watch")
        case .height:       return String(localized: "Height", table: "Watch")
        case .leanBodyMass: return String(localized: "Lean Body Mass", table: "Watch")
        case .waist:        return String(localized: "Waist", table: "Watch")
        case .neck:         return String(localized: "Neck", table: "Watch")
        case .shoulders:    return String(localized: "Shoulders", table: "Watch")
        case .bust:         return String(localized: "Bust", table: "Watch")
        case .chest:        return String(localized: "Chest", table: "Watch")
        case .leftBicep:    return String(localized: "Left Bicep", table: "Watch")
        case .rightBicep:   return String(localized: "Right Bicep", table: "Watch")
        case .leftForearm:  return String(localized: "Left Forearm", table: "Watch")
        case .rightForearm: return String(localized: "Right Forearm", table: "Watch")
        case .hips:         return String(localized: "Hips", table: "Watch")
        case .leftThigh:    return String(localized: "Left Thigh", table: "Watch")
        case .rightThigh:   return String(localized: "Right Thigh", table: "Watch")
        case .leftCalf:     return String(localized: "Left Calf", table: "Watch")
        case .rightCalf:    return String(localized: "Right Calf", table: "Watch")
        }
    }

    var shortName: String {
        switch self {
        case .weight:       return String(localized: "Weight", table: "Watch")
        case .bodyFat:      return String(localized: "Fat", table: "Watch")
        case .height:       return String(localized: "Height", table: "Watch")
        case .leanBodyMass: return String(localized: "Lean", table: "Watch")
        case .waist:        return String(localized: "Waist", table: "Watch")
        case .neck:         return String(localized: "Neck", table: "Watch")
        case .shoulders:    return String(localized: "Shoulders", table: "Watch")
        case .bust:         return String(localized: "Bust", table: "Watch")
        case .chest:        return String(localized: "Chest", table: "Watch")
        case .leftBicep:    return String(localized: "L Bicep", table: "Watch")
        case .rightBicep:   return String(localized: "R Bicep", table: "Watch")
        case .leftForearm:  return String(localized: "L Forearm", table: "Watch")
        case .rightForearm: return String(localized: "R Forearm", table: "Watch")
        case .hips:         return String(localized: "Hips", table: "Watch")
        case .leftThigh:    return String(localized: "L Thigh", table: "Watch")
        case .rightThigh:   return String(localized: "R Thigh", table: "Watch")
        case .leftCalf:     return String(localized: "L Calf", table: "Watch")
        case .rightCalf:    return String(localized: "R Calf", table: "Watch")
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
                ? String(format: "\(valueFormat)%%", displayValue)
                : String(format: valueFormat, displayValue)
        case .weight, .length:
            if includeUnit {
                return String(format: "\(valueFormat)\u{202F}%@", displayValue, unitSymbol(isMetric: isMetric))
            }
            return String(format: valueFormat, displayValue)
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
