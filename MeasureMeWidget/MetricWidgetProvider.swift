import WidgetKit
import AppIntents

/// The app reloads all three widget kinds explicitly after every save and on startup, so the
/// timeline only has to survive until the copy that talks in days becomes stale. Refreshing
/// hourly just spent the system's per-widget budget re-rendering identical entries.
private func nextLocalMidnight(after date: Date = .now) -> Date {
    let calendar = Calendar.current
    return calendar.nextDate(
        after: date,
        matching: DateComponents(hour: 0, minute: 0, second: 0),
        matchingPolicy: .nextTime
    ) ?? calendar.date(byAdding: .hour, value: 6, to: date) ?? date
}

struct MetricWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = MetricEntry
    typealias Intent = MetricIntent

    func placeholder(in context: Context) -> MetricEntry {
        MetricEntry(date: .now, configuration: MetricIntent(),
                    data: nil, data2: nil, data3: nil)
    }

    func snapshot(for configuration: MetricIntent, in context: Context) async -> MetricEntry {
        MetricEntry(
            date: .now,
            configuration: configuration,
            data: WidgetMetricData.load(for: configuration.metric),
            data2: WidgetMetricData.load(for: configuration.metric2),
            data3: WidgetMetricData.load(for: configuration.metric3)
        )
    }

    func timeline(for configuration: MetricIntent, in context: Context) async -> Timeline<MetricEntry> {
        let entry = MetricEntry(
            date: .now,
            configuration: configuration,
            data: WidgetMetricData.load(for: configuration.metric),
            data2: WidgetMetricData.load(for: configuration.metric2),
            data3: WidgetMetricData.load(for: configuration.metric3)
        )
        let nextUpdate = nextLocalMidnight()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

struct SmartMetricEntry: TimelineEntry {
    let date: Date
    let configuration: SmartMetricIntent
    let selectedKind: WidgetMetricKind
    let data: WidgetMetricData?
    let premiumEnabled: Bool
}

struct SmartMetricWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = SmartMetricEntry
    typealias Intent = SmartMetricIntent

    func placeholder(in context: Context) -> SmartMetricEntry {
        SmartMetricEntry(
            date: .now,
            configuration: SmartMetricIntent(),
            selectedKind: .weight,
            data: WidgetMetricData.load(for: .weight),
            premiumEnabled: true
        )
    }

    func snapshot(for configuration: SmartMetricIntent, in context: Context) async -> SmartMetricEntry {
        makeEntry(configuration: configuration)
    }

    func timeline(for configuration: SmartMetricIntent, in context: Context) async -> Timeline<SmartMetricEntry> {
        let entry = makeEntry(configuration: configuration)
        let nextUpdate = nextLocalMidnight()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func makeEntry(configuration: SmartMetricIntent) -> SmartMetricEntry {
        let premium = widgetPremiumEnabled()
        let selection = selectMetric(strategy: configuration.strategy, trendWindow: configuration.trendWindow)
        return SmartMetricEntry(
            date: .now,
            configuration: configuration,
            selectedKind: selection,
            data: WidgetMetricData.load(for: selection),
            premiumEnabled: premium
        )
    }

    private func selectMetric(strategy: SmartMetricStrategy, trendWindow: WidgetTrendWindow) -> WidgetMetricKind {
        let allData = WidgetMetricData.allData()
        guard !allData.isEmpty else { return .weight }

        switch strategy {
        case .mostNeglected:
            return allData.max(by: { lhs, rhs in
                let lhsDate = lhs.data.latestSample?.date ?? .distantPast
                let rhsDate = rhs.data.latestSample?.date ?? .distantPast
                return lhsDate < rhsDate
            })?.kind ?? .weight
        case .mostVolatile:
            return allData.max(by: { lhs, rhs in
                volatilityScore(data: lhs.data, window: trendWindow) < volatilityScore(data: rhs.data, window: trendWindow)
            })?.kind ?? .weight
        }
    }

    private func volatilityScore(data: WidgetMetricData, window: WidgetTrendWindow) -> Double {
        let values = data.samples(for: window).map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0 }
        return max - min
    }
}

struct StreakEntry: TimelineEntry {
    let date: Date
    let configuration: StreakWidgetIntent
    let streak: WidgetStreakPayload?
    let premiumEnabled: Bool
}

struct StreakWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = StreakEntry
    typealias Intent = StreakWidgetIntent

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(
            date: .now,
            configuration: StreakWidgetIntent(),
            streak: WidgetStreakPayload(currentStreak: 3, maxStreak: 12, loggedToday: true),
            premiumEnabled: true
        )
    }

    func snapshot(for configuration: StreakWidgetIntent, in context: Context) async -> StreakEntry {
        StreakEntry(
            date: .now,
            configuration: configuration,
            streak: widgetStreakPayload(),
            premiumEnabled: widgetPremiumEnabled()
        )
    }

    func timeline(for configuration: StreakWidgetIntent, in context: Context) async -> Timeline<StreakEntry> {
        let entry = StreakEntry(
            date: .now,
            configuration: configuration,
            streak: widgetStreakPayload(),
            premiumEnabled: widgetPremiumEnabled()
        )
        let nextUpdate = nextLocalMidnight()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
