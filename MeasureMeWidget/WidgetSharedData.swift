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
        return kind.formattedDisplayValue(delta, isMetric: isMetric, alwaysShowSign: true)
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

    func trendStatusText(for kind: WidgetMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return widgetLocalized("Not enough data", "Brak danych")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            return widgetLocalized("Improving", "Poprawa")
        case .negative:
            return widgetLocalized("Worsening", "Pogorszenie")
        case .neutral:
            return widgetLocalized("Stable", "Stabilnie")
        }
    }

    func accessibilityTrendDescription(for kind: WidgetMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return widgetLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        }

        let newVal = kind.valueForDisplay(fromMetric: newest.value, isMetric: isMetric)
        let oldVal = kind.valueForDisplay(fromMetric: oldest.value, isMetric: isMetric)
        let delta = newVal - oldVal
        let magnitude = kind.formattedDisplayValue(abs(delta), isMetric: isMetric, alwaysShowSign: false)
        let direction: String
        if delta > 0 {
            direction = widgetLocalized("up", "w górę")
        } else if delta < 0 {
            direction = widgetLocalized("down", "w dół")
        } else {
            direction = widgetLocalized("unchanged", "bez zmian")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            if delta == 0 {
                return widgetLocalized("Improving, stable over 30 days", "Poprawa, stabilnie w ostatnich 30 dniach")
            }
            return String(format: widgetLocalized("Improving, %@ %@ over 30 days", "Poprawa, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        case .negative:
            if delta == 0 {
                return widgetLocalized("Worsening, stable over 30 days", "Pogorszenie, stabilnie w ostatnich 30 dniach")
            }
            return String(format: widgetLocalized("Worsening, %@ %@ over 30 days", "Pogorszenie, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        case .neutral:
            if delta == 0 {
                return widgetLocalized("Stable over 30 days", "Stabilnie w ostatnich 30 dniach")
            }
            return String(format: widgetLocalized("Stable, %@ %@ over 30 days", "Stabilnie, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        }
    }

    func accessibilityGoalDescription(for kind: WidgetMetricKind) -> String? {
        guard let goal else { return nil }
        let targetDisplay = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: isMetric)
        let targetText = kind.formattedDisplayValue(targetDisplay, isMetric: isMetric)
        return String(format: widgetLocalized("Goal %@", "Cel %@"), targetText)
    }

    // MARK: - App Group I/O

    static func load(for kind: WidgetMetricKind) -> WidgetMetricData? {
        guard let defaults = UserDefaults(suiteName: widgetAppGroupID) else { return nil }
        guard let data = defaults.data(forKey: "widget_data_\(kind.rawValue)") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetMetricData.self, from: data)
    }
}

func widgetLocalized(_ english: String, _ polish: String) -> String {
    Locale.current.language.languageCode?.identifier == "pl" ? polish : english
}
