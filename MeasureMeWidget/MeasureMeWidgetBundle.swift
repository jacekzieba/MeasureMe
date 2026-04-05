import WidgetKit
import SwiftUI

@main
struct MeasureMeWidgetBundle: WidgetBundle {
    var body: some Widget {
        MetricWidget()
        SmartMetricWidget()
        StreakWidget()
    }
}

// MARK: - MetricWidget

struct MetricWidget: Widget {
    let kind: String = "MetricWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MetricIntent.self,
            provider: MetricWidgetProvider()
        ) { entry in
            MetricWidgetView(entry: entry)
        }
        .configurationDisplayName("Metric")
        .description("Shows your selected metric with trend chart and 30-day change.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct SmartMetricWidget: Widget {
    let kind: String = "SmartMetricWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SmartMetricIntent.self,
            provider: SmartMetricWidgetProvider()
        ) { entry in
            SmartMetricWidgetView(entry: entry)
        }
        .configurationDisplayName("Smart Metric")
        .description("Automatically picks the metric that needs your attention.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StreakWidget: Widget {
    let kind: String = "StreakWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: StreakWidgetIntent.self,
            provider: StreakWidgetProvider()
        ) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Shows your current streak and logging status.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
