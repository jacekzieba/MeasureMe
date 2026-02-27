import AppIntents
import SwiftUI

// MARK: - WidgetMetricKind

/// Lightweight mirror of the app's MetricKind enum, conforming to AppEnum for widget configuration.
enum WidgetMetricKind: String, AppEnum, CaseIterable {
    case weight, bodyFat, height, leanBodyMass, waist
    case neck, shoulders, bust, chest
    case leftBicep, rightBicep, leftForearm, rightForearm
    case hips, leftThigh, rightThigh, leftCalf, rightCalf

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"

    static var caseDisplayRepresentations: [WidgetMetricKind: DisplayRepresentation] = [
        .weight:        "Weight",
        .bodyFat:       "Body Fat",
        .height:        "Height",
        .leanBodyMass:  "Lean Body Mass",
        .waist:         "Waist",
        .neck:          "Neck",
        .shoulders:     "Shoulders",
        .bust:          "Bust",
        .chest:         "Chest",
        .leftBicep:     "Left Bicep",
        .rightBicep:    "Right Bicep",
        .leftForearm:   "Left Forearm",
        .rightForearm:  "Right Forearm",
        .hips:          "Hips",
        .leftThigh:     "Left Thigh",
        .rightThigh:    "Right Thigh",
        .leftCalf:      "Left Calf",
        .rightCalf:     "Right Calf"
    ]

    // MARK: - Display

    var displayName: String {
        switch self {
        case .weight:       return "Weight"
        case .bodyFat:      return "Body Fat"
        case .height:       return "Height"
        case .leanBodyMass: return "Lean Body Mass"
        case .waist:        return "Waist"
        case .neck:         return "Neck"
        case .shoulders:    return "Shoulders"
        case .bust:         return "Bust"
        case .chest:        return "Chest"
        case .leftBicep:    return "Left Bicep"
        case .rightBicep:   return "Right Bicep"
        case .leftForearm:  return "Left Forearm"
        case .rightForearm: return "Right Forearm"
        case .hips:         return "Hips"
        case .leftThigh:    return "Left Thigh"
        case .rightThigh:   return "Right Thigh"
        case .leftCalf:     return "Left Calf"
        case .rightCalf:    return "Right Calf"
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
