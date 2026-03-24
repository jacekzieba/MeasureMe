import SwiftUI
import WidgetKit

struct MeasureMeComplication: Widget {
    let kind: String = "MeasureMeComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ComplicationMetricIntent.self,
            provider: ComplicationProvider()
        ) { entry in
            ComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("MeasureMe")
        .description("Shows the latest value for a body metric.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}
