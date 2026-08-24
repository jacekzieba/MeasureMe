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
        samples(for: .thirtyDays)
    }

    var latestSample: SampleDTO? {
        samples.max(by: { $0.date < $1.date })
    }

    func samples(for window: WidgetTrendWindow) -> [SampleDTO] {
        let cutoff = Date().addingTimeInterval(-Double(window.days) * 24 * 3600)
        return samples.filter { $0.date >= cutoff }
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

    func goalProgress(for kind: WidgetMetricKind) -> Double? {
        guard let goal, let latest = latestDisplayValue(for: kind) else { return nil }
        let startMetric = goal.startValue ?? goal.targetValue
        let start = kind.valueForDisplay(fromMetric: startMetric, isMetric: isMetric)
        let target = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: isMetric)
        let total = abs(target - start)
        guard total > 0 else { return 1.0 }
        let progress = 1.0 - abs(target - latest) / total
        return min(max(progress, 0), 1)
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
            return widgetLocalized("Not enough data")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            return widgetLocalized("Improving")
        case .negative:
            return widgetLocalized("Worsening")
        case .neutral:
            return widgetLocalized("Stable")
        }
    }

    func accessibilityTrendDescription(for kind: WidgetMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return widgetLocalized("Not enough data for trend")
        }

        let newVal = kind.valueForDisplay(fromMetric: newest.value, isMetric: isMetric)
        let oldVal = kind.valueForDisplay(fromMetric: oldest.value, isMetric: isMetric)
        let delta = newVal - oldVal
        let magnitude = kind.formattedDisplayValue(abs(delta), isMetric: isMetric, alwaysShowSign: false)
        let direction: String
        if delta > 0 {
            direction = widgetLocalized("up")
        } else if delta < 0 {
            direction = widgetLocalized("down")
        } else {
            direction = widgetLocalized("unchanged")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            if delta == 0 {
                return widgetLocalized("Improving, stable over 30 days")
            }
            return String(format: widgetLocalized("Improving, %@ %@ over 30 days"), direction, magnitude)
        case .negative:
            if delta == 0 {
                return widgetLocalized("Worsening, stable over 30 days")
            }
            return String(format: widgetLocalized("Worsening, %@ %@ over 30 days"), direction, magnitude)
        case .neutral:
            if delta == 0 {
                return widgetLocalized("Stable over 30 days")
            }
            return String(format: widgetLocalized("Stable, %@ %@ over 30 days"), direction, magnitude)
        }
    }

    func accessibilityGoalDescription(for kind: WidgetMetricKind) -> String? {
        guard let goal else { return nil }
        let targetDisplay = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: isMetric)
        let targetText = kind.formattedDisplayValue(targetDisplay, isMetric: isMetric)
        return String(format: widgetLocalized("Goal %@"), targetText)
    }

    // MARK: - App Group I/O

    static func load(for kind: WidgetMetricKind) -> WidgetMetricData? {
        guard let defaults = UserDefaults(suiteName: widgetAppGroupID) else { return nil }
        guard let data = defaults.data(forKey: "widget_data_\(kind.rawValue)") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetMetricData.self, from: data)
    }

    static func allData() -> [(kind: WidgetMetricKind, data: WidgetMetricData)] {
        WidgetMetricKind.allCases.compactMap { kind in
            guard let data = load(for: kind) else { return nil }
            return (kind: kind, data: data)
        }
    }
}

struct WidgetStreakPayload: Codable {
    let currentStreak: Int
    let maxStreak: Int
    let loggedToday: Bool
}

func widgetPremiumEnabled() -> Bool {
    let defaults = UserDefaults(suiteName: widgetAppGroupID)
    return defaults?.bool(forKey: "widget_premium_enabled") ?? false
}

func widgetStreakPayload() -> WidgetStreakPayload? {
    guard let defaults = UserDefaults(suiteName: widgetAppGroupID),
          let data = defaults.data(forKey: "widget_streak_payload") else {
        return nil
    }
    return try? JSONDecoder().decode(WidgetStreakPayload.self, from: data)
}

/// Resolves through the widget extension's own `Localizable.strings`.
///
/// This used to take a second, hardcoded Polish string that was silently discarded — it read
/// like the source of truth for Polish while the catalog was doing the actual work, and for a
/// long time the catalog had none of these keys at all.
func widgetLocalized(_ english: String) -> String {
    NSLocalizedString(english, bundle: .main, comment: "")
}
