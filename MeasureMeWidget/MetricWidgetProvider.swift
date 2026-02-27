import WidgetKit
import AppIntents

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
            data:  WidgetMetricData.load(for: configuration.metric),
            data2: WidgetMetricData.load(for: configuration.metric2),
            data3: WidgetMetricData.load(for: configuration.metric3)
        )
    }

    func timeline(for configuration: MetricIntent, in context: Context) async -> Timeline<MetricEntry> {
        let entry = MetricEntry(
            date: .now,
            configuration: configuration,
            data:  WidgetMetricData.load(for: configuration.metric),
            data2: WidgetMetricData.load(for: configuration.metric2),
            data3: WidgetMetricData.load(for: configuration.metric3)
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
