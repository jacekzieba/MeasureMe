import AppIntents
import SwiftUI

// MARK: - WidgetMetricKind

/// Lightweight mirror of the app's MetricKind enum, conforming to AppEnum for widget configuration.
enum WidgetMetricKind: String, AppEnum, CaseIterable {
    case weight, bodyFat, height, leanBodyMass, waist
    case neck, shoulders, bust, chest
    case leftBicep, rightBicep, leftForearm, rightForearm
    case hips, leftThigh, rightThigh, leftCalf, rightCalf

    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [WidgetMetricKind: DisplayRepresentation] = [
        .weight:        DisplayRepresentation(title: "Weight"),
        .bodyFat:       DisplayRepresentation(title: "Body Fat"),
        .height:        DisplayRepresentation(title: "Height"),
        .leanBodyMass:  DisplayRepresentation(title: "Lean Body Mass"),
        .waist:         DisplayRepresentation(title: "Waist"),
        .neck:          DisplayRepresentation(title: "Neck"),
        .shoulders:     DisplayRepresentation(title: "Shoulders"),
        .bust:          DisplayRepresentation(title: "Bust"),
        .chest:         DisplayRepresentation(title: "Chest"),
        .leftBicep:     DisplayRepresentation(title: "Left Bicep"),
        .rightBicep:    DisplayRepresentation(title: "Right Bicep"),
        .leftForearm:   DisplayRepresentation(title: "Left Forearm"),
        .rightForearm:  DisplayRepresentation(title: "Right Forearm"),
        .hips:          DisplayRepresentation(title: "Hips"),
        .leftThigh:     DisplayRepresentation(title: "Left Thigh"),
        .rightThigh:    DisplayRepresentation(title: "Right Thigh"),
        .leftCalf:      DisplayRepresentation(title: "Left Calf"),
        .rightCalf:     DisplayRepresentation(title: "Right Calf")
    ]

    // MARK: - Display

    var displayName: String {
        switch self {
        case .weight:       return String(localized: "Weight")
        case .bodyFat:      return String(localized: "Body Fat")
        case .height:       return String(localized: "Height")
        case .leanBodyMass: return String(localized: "Lean Body Mass")
        case .waist:        return String(localized: "Waist")
        case .neck:         return String(localized: "Neck")
        case .shoulders:    return String(localized: "Shoulders")
        case .bust:         return String(localized: "Bust")
        case .chest:        return String(localized: "Chest")
        case .leftBicep:    return String(localized: "Left Bicep")
        case .rightBicep:   return String(localized: "Right Bicep")
        case .leftForearm:  return String(localized: "Left Forearm")
        case .rightForearm: return String(localized: "Right Forearm")
        case .hips:         return String(localized: "Hips")
        case .leftThigh:    return String(localized: "Left Thigh")
        case .rightThigh:   return String(localized: "Right Thigh")
        case .leftCalf:     return String(localized: "Left Calf")
        case .rightCalf:    return String(localized: "Right Calf")
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
}

// MARK: - MetricIntent

struct MetricIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Metric Widget"
    static var description = IntentDescription("Shows a body metric with trend chart and change.")

    @Parameter(title: "Metric", default: .weight)
    var metric: WidgetMetricKind

    @Parameter(title: "Second Metric", default: .bodyFat)
    var metric2: WidgetMetricKind

    @Parameter(title: "Third Metric", default: .waist)
    var metric3: WidgetMetricKind
}
