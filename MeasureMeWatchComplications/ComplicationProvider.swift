import WidgetKit
import AppIntents
import SwiftUI

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let configuration: ComplicationMetricIntent
    let data: ComplicationMetricData?
}

struct ComplicationProvider: AppIntentTimelineProvider {
    typealias Entry = ComplicationEntry
    typealias Intent = ComplicationMetricIntent

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, configuration: ComplicationMetricIntent(), data: nil)
    }

    func snapshot(for configuration: ComplicationMetricIntent, in context: Context) async -> ComplicationEntry {
        let kind = configuration.metric
        let data = ComplicationMetricData.load(for: kind)
        return ComplicationEntry(date: .now, configuration: configuration, data: data)
    }

    func timeline(for configuration: ComplicationMetricIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        let kind = configuration.metric
        let data = ComplicationMetricData.load(for: kind)
        let entry = ComplicationEntry(date: .now, configuration: configuration, data: data)
        let nextUpdate = Date().addingTimeInterval(60 * 60)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func recommendations() -> [AppIntentRecommendation<ComplicationMetricIntent>] {
        let weight = ComplicationMetricIntent()
        weight.metric = .weight
        let bodyFat = ComplicationMetricIntent()
        bodyFat.metric = .bodyFat
        let waist = ComplicationMetricIntent()
        waist.metric = .waist
        return [
            AppIntentRecommendation(intent: weight, description: String(localized: "Weight")),
            AppIntentRecommendation(intent: bodyFat, description: String(localized: "Body Fat")),
            AppIntentRecommendation(intent: waist, description: String(localized: "Waist"))
        ]
    }
}
