import Foundation

let watchAppGroupID = "group.com.jacek.measureme"

/// Data model shared between the watch and the main app via App Group UserDefaults.
/// Matches WidgetMetricData from the widget target.
struct WatchMetricData: Codable {
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
        return samples.filter { $0.date >= cutoff }
    }

    var latestSample: SampleDTO? {
        samples.max(by: { $0.date < $1.date })
    }

    func latestDisplayValue(for kind: WatchMetricKind) -> Double? {
        guard let sample = latestSample else { return nil }
        return kind.valueForDisplay(fromMetric: sample.value, isMetric: isMetric)
    }

    func formattedValue(for kind: WatchMetricKind) -> String {
        guard let val = latestDisplayValue(for: kind) else { return "—" }
        return kind.formattedDisplayValue(val, isMetric: isMetric)
    }

    func deltaText(for kind: WatchMetricKind, recentSamples: [SampleDTO]? = nil) -> String? {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else { return nil }
        let newVal = kind.valueForDisplay(fromMetric: newest.value, isMetric: isMetric)
        let oldVal = kind.valueForDisplay(fromMetric: oldest.value, isMetric: isMetric)
        let delta = newVal - oldVal
        return kind.formattedDisplayValue(delta, isMetric: isMetric, alwaysShowSign: true)
    }

    func trendOutcome(for kind: WatchMetricKind, recentSamples: [SampleDTO]? = nil) -> WatchMetricKind.TrendOutcome {
        let recent = recentSamples ?? last30DaySamples
        guard let first = recent.first?.value, let last = recent.last?.value else { return .neutral }
        return kind.trendOutcome(
            from: first, to: last,
            goalTarget: goal?.targetValue,
            goalDirection: goal?.direction
        )
    }

    func trendStatusText(for kind: WatchMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return watchLocalized("Not enough data", "Brak danych")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            return watchLocalized("Improving", "Poprawa")
        case .negative:
            return watchLocalized("Worsening", "Pogorszenie")
        case .neutral:
            return watchLocalized("Stable", "Stabilnie")
        }
    }

    func accessibilityTrendDescription(for kind: WatchMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return watchLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        }

        let newVal = kind.valueForDisplay(fromMetric: newest.value, isMetric: isMetric)
        let oldVal = kind.valueForDisplay(fromMetric: oldest.value, isMetric: isMetric)
        let delta = newVal - oldVal
        let magnitude = kind.formattedDisplayValue(abs(delta), isMetric: isMetric, alwaysShowSign: false)
        let direction: String
        if delta > 0 {
            direction = watchLocalized("up", "w górę")
        } else if delta < 0 {
            direction = watchLocalized("down", "w dół")
        } else {
            direction = watchLocalized("unchanged", "bez zmian")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            if delta == 0 {
                return watchLocalized("Improving, stable over 30 days", "Poprawa, stabilnie w ostatnich 30 dniach")
            }
            return String(format: watchLocalized("Improving, %@ %@ over 30 days", "Poprawa, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        case .negative:
            if delta == 0 {
                return watchLocalized("Worsening, stable over 30 days", "Pogorszenie, stabilnie w ostatnich 30 dniach")
            }
            return String(format: watchLocalized("Worsening, %@ %@ over 30 days", "Pogorszenie, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        case .neutral:
            if delta == 0 {
                return watchLocalized("Stable over 30 days", "Stabilnie w ostatnich 30 dniach")
            }
            return String(format: watchLocalized("Stable, %@ %@ over 30 days", "Stabilnie, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        }
    }

    func accessibilityGoalDescription(for kind: WatchMetricKind) -> String? {
        guard let goal else { return nil }
        let targetDisplay = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: isMetric)
        let targetText = kind.formattedDisplayValue(targetDisplay, isMetric: isMetric)
        return String(format: watchLocalized("Goal %@", "Cel %@"), targetText)
    }

    // MARK: - App Group I/O

    static func load(for kind: WatchMetricKind) -> WatchMetricData? {
        guard let defaults = UserDefaults(suiteName: watchAppGroupID) else { return nil }
        guard let data = defaults.data(forKey: "widget_data_\(kind.rawValue)") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WatchMetricData.self, from: data)
    }
}

func watchLocalized(_ english: String, _ polish: String) -> String {
    Locale.current.language.languageCode?.identifier == "pl" ? polish : english
}
