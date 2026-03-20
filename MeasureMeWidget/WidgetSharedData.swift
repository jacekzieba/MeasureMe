import Foundation

let widgetAppGroupID = "group.com.jacek.measureme"

/// Data model shared between the widget and the main app via App Group UserDefaults.
/// Stored as JSON under key "widget_data_<metricRawValue>" in the shared container.
struct WidgetMetricData: Codable {
    struct SampleDTO: Codable {
        let value: Double
        let date: Date
    }

    struct GoalDTO: Codable {
        let targetValue: Double
        let startValue: Double?
        let direction: String  // "increase" | "decrease"
    }

    let kind: String          // MetricKind rawValue
    let samples: [SampleDTO]  // Sorted oldest-first, up to 90 days
    let goal: GoalDTO?
    let unitsSystem: String

    // MARK: - Convenience

    var isMetric: Bool { unitsSystem != "imperial" }

    var last30DaySamples: [SampleDTO] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        // `samples` are already persisted as oldest-first, so avoid re-sorting on every access.
        return samples.filter { $0.date >= cutoff }
    }

    var latestSample: SampleDTO? {
        samples.max(by: { $0.date < $1.date })
    }

    func latestDisplayValue(for kind: WidgetMetricKind) -> Double? {
        guard let sample = latestSample else { return nil }
        return kind.valueForDisplay(fromMetric: sample.value, isMetric: isMetric)
    }

    /// Returns formatted delta string like "+1.2 kg" or nil if not enough data.
    func deltaText(for kind: WidgetMetricKind, recentSamples: [SampleDTO]? = nil) -> String? {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else { return nil }
        let newVal = kind.valueForDisplay(fromMetric: newest.value, isMetric: isMetric)
        let oldVal = kind.valueForDisplay(fromMetric: oldest.value, isMetric: isMetric)
        let delta = newVal - oldVal
        let unit = kind.unitSymbol(isMetric: isMetric)
        let fmt = kind.unitCategory == .percent ? "%+.1f%@" : "%+.1f\u{202F}%@"
        return String(format: fmt, delta, unit)
    }

    func trendOutcome(for kind: WidgetMetricKind, recentSamples: [SampleDTO]? = nil) -> WidgetMetricKind.TrendOutcome {
        let recent = recentSamples ?? last30DaySamples
        guard let first = recent.first?.value, let last = recent.last?.value else { return .neutral }
        return kind.trendOutcome(
            from: first, to: last,
            goalTarget: goal?.targetValue,
            goalDirection: goal?.direction
        )
    }

    // MARK: - App Group I/O

    static func load(for kind: WidgetMetricKind) -> WidgetMetricData? {
        guard let defaults = UserDefaults(suiteName: widgetAppGroupID) else { return nil }
        guard let data = defaults.data(forKey: "widget_data_\(kind.rawValue)") else { return nil }
        return try? JSONDecoder().decode(WidgetMetricData.self, from: data)
    }
}
