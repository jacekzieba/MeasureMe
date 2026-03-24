import WidgetKit
import AppIntents

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let configuration: ComplicationMetricIntent
    let data: WatchMetricData?
}

struct ComplicationProvider: AppIntentTimelineProvider {
    typealias Entry = ComplicationEntry
    typealias Intent = ComplicationMetricIntent

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, configuration: ComplicationMetricIntent(), data: nil)
    }

    func snapshot(for configuration: ComplicationMetricIntent, in context: Context) async -> ComplicationEntry {
        let kind = configuration.metric.watchMetricKind
        let data = WatchMetricData.load(for: kind)
        return ComplicationEntry(date: .now, configuration: configuration, data: data)
    }

    func timeline(for configuration: ComplicationMetricIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        let kind = configuration.metric.watchMetricKind
        let data = WatchMetricData.load(for: kind)
        let entry = ComplicationEntry(date: .now, configuration: configuration, data: data)
        let nextUpdate = Date().addingTimeInterval(60 * 60) // refresh in 1 hour
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
