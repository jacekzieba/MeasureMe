import AppIntents

/// AppIntent for selecting which metric to show in a watch complication.
struct ComplicationMetricIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Metric Complication"
    static var description = IntentDescription("Shows the latest value for a body metric.")

    @Parameter(title: "Metric", default: .weight)
    var metric: ComplicationMetricKind
}

/// Lightweight AppEnum for complication metric selection.
enum ComplicationMetricKind: String, AppEnum, CaseIterable {
    case weight, bodyFat, height, leanBodyMass, waist
    case neck, shoulders, bust, chest
    case leftBicep, rightBicep, leftForearm, rightForearm
    case hips, leftThigh, rightThigh, leftCalf, rightCalf

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"

    static var caseDisplayRepresentations: [ComplicationMetricKind: DisplayRepresentation] = [
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

    /// Map to ComplicationMetricKindHelper for data loading.
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

    var shortName: String {
        switch self {
        case .weight:       return "Weight"
        case .bodyFat:      return "Fat"
        case .height:       return "Height"
        case .leanBodyMass: return "Lean"
        case .waist:        return "Waist"
        case .neck:         return "Neck"
        case .shoulders:    return "Shoulders"
        case .bust:         return "Bust"
        case .chest:        return "Chest"
        case .leftBicep:    return "L Bicep"
        case .rightBicep:   return "R Bicep"
        case .leftForearm:  return "L Forearm"
        case .rightForearm: return "R Forearm"
        case .hips:         return "Hips"
        case .leftThigh:    return "L Thigh"
        case .rightThigh:   return "R Thigh"
        case .leftCalf:     return "L Calf"
        case .rightCalf:    return "R Calf"
        }
    }

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

    // MARK: - Units (self-contained — no dependency on WatchMetricKind)

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
