import Foundation

/// Self-contained data model for complications.
/// Matches WidgetMetricData / WatchMetricData from other targets.
let complicationAppGroupID = "group.com.jacek.measureme"

struct ComplicationMetricData: Codable {
    struct SampleDTO: Codable {
        let value: Double
        let date: Date
    }

    struct GoalDTO: Codable {
        let targetValue: Double
        let startValue: Double?
        let direction: String
    }

    let kind: String
    let samples: [SampleDTO]
    let goal: GoalDTO?
    let unitsSystem: String

    var isMetric: Bool { unitsSystem != "imperial" }

    var last30DaySamples: [SampleDTO] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        return samples.filter { $0.date >= cutoff }
    }

    var latestSample: SampleDTO? {
        samples.max(by: { $0.date < $1.date })
    }

    func latestDisplayValue(for kind: ComplicationMetricKind) -> Double? {
        guard let sample = latestSample else { return nil }
        return kind.valueForDisplay(fromMetric: sample.value, isMetric: isMetric)
    }

    func formattedValue(for kind: ComplicationMetricKind) -> String {
        guard let val = latestDisplayValue(for: kind) else { return "—" }
        let unit = kind.unitSymbol(isMetric: isMetric)
        let fmt = kind.unitCategory == .percent ? "%.1f%@" : "%.1f\u{202F}%@"
        return String(format: fmt, val, unit)
    }

    func deltaText(for kind: ComplicationMetricKind, recentSamples: [SampleDTO]? = nil) -> String? {
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

    func trendOutcome(for kind: ComplicationMetricKind, recentSamples: [SampleDTO]? = nil) -> ComplicationMetricKind.TrendOutcome {
        let recent = recentSamples ?? last30DaySamples
        guard let first = recent.first?.value, let last = recent.last?.value else { return .neutral }
        return kind.trendOutcome(
            from: first, to: last,
            goalTarget: goal?.targetValue,
            goalDirection: goal?.direction
        )
    }

    func trendStatusText(for kind: ComplicationMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return complicationLocalized("Not enough data", "Brak danych")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            return complicationLocalized("Improving", "Poprawa")
        case .negative:
            return complicationLocalized("Worsening", "Pogorszenie")
        case .neutral:
            return complicationLocalized("Stable", "Stabilnie")
        }
    }

    func accessibilityTrendDescription(for kind: ComplicationMetricKind, recentSamples: [SampleDTO]? = nil) -> String {
        let recent = recentSamples ?? last30DaySamples
        guard let oldest = recent.first, let newest = recent.last,
              oldest.date != newest.date else {
            return complicationLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        }

        let newVal = kind.valueForDisplay(fromMetric: newest.value, isMetric: isMetric)
        let oldVal = kind.valueForDisplay(fromMetric: oldest.value, isMetric: isMetric)
        let delta = newVal - oldVal
        let magnitude = complicationFormattedMagnitude(for: kind, value: abs(delta))
        let direction: String
        if delta > 0 {
            direction = complicationLocalized("up", "w górę")
        } else if delta < 0 {
            direction = complicationLocalized("down", "w dół")
        } else {
            direction = complicationLocalized("unchanged", "bez zmian")
        }

        switch trendOutcome(for: kind, recentSamples: recent) {
        case .positive:
            if delta == 0 {
                return complicationLocalized("Improving, stable over 30 days", "Poprawa, stabilnie w ostatnich 30 dniach")
            }
            return String(format: complicationLocalized("Improving, %@ %@ over 30 days", "Poprawa, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        case .negative:
            if delta == 0 {
                return complicationLocalized("Worsening, stable over 30 days", "Pogorszenie, stabilnie w ostatnich 30 dniach")
            }
            return String(format: complicationLocalized("Worsening, %@ %@ over 30 days", "Pogorszenie, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        case .neutral:
            if delta == 0 {
                return complicationLocalized("Stable over 30 days", "Stabilnie w ostatnich 30 dniach")
            }
            return String(format: complicationLocalized("Stable, %@ %@ over 30 days", "Stabilnie, %@ %@ w ostatnich 30 dniach"), direction, magnitude)
        }
    }

    func accessibilityGoalDescription(for kind: ComplicationMetricKind) -> String? {
        guard let goal else { return nil }
        let targetDisplay = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: isMetric)
        let targetText = complicationFormattedMagnitude(for: kind, value: targetDisplay, isMetric: isMetric)
        return String(format: complicationLocalized("Goal %@", "Cel %@"), targetText)
    }

    static func load(for kind: ComplicationMetricKind) -> ComplicationMetricData? {
        guard let defaults = UserDefaults(suiteName: complicationAppGroupID) else { return nil }
        guard let data = defaults.data(forKey: "widget_data_\(kind.rawValue)") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ComplicationMetricData.self, from: data)
    }
}

private func complicationFormattedMagnitude(for kind: ComplicationMetricKind, value: Double, isMetric: Bool = true) -> String {
    let unit = kind.unitSymbol(isMetric: isMetric)
    let format = kind.unitCategory == .percent ? "%.1f%@" : "%.1f\u{202F}%@"
    return String(format: format, value, unit)
}

func complicationLocalized(_ english: String, _ polish: String) -> String {
    Locale.current.language.languageCode?.identifier == "pl" ? polish : english
}
