import WidgetKit

struct MetricEntry: TimelineEntry {
    let date: Date
    let configuration: MetricIntent
    let data: WidgetMetricData?
    let data2: WidgetMetricData?
    let data3: WidgetMetricData?
}
