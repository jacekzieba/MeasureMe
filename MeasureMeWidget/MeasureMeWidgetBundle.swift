import WidgetKit
import SwiftUI

@main
struct MeasureMeWidgetBundle: WidgetBundle {
    var body: some Widget {
        MetricWidget()
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
