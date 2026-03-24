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

    /// Map to WatchMetricKind for data loading.
    var watchMetricKind: WatchMetricKind {
        WatchMetricKind(rawValue: rawValue)!
    }

    var systemImage: String {
        watchMetricKind.systemImage
    }
}
