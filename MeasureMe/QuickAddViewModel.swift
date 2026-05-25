import SwiftUI
import SwiftData

@Observable @MainActor final class QuickAddViewModel {
    var samples: [MetricSample] = []
    var customDefinitions: [CustomMetricDefinition] = []

    func latestByKind() -> [MetricKind: (value: Double, date: Date)] {
        var latest: [MetricKind: (value: Double, date: Date)] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            if latest[kind] == nil {
                latest[kind] = (value: sample.value, date: sample.date)
            }
        }
        return latest
    }

    func activeCustomDefinitions(metricsStore: ActiveMetricsStore) -> [CustomMetricDefinition] {
        customDefinitions.filter { metricsStore.isCustomEnabled($0.identifier) }
    }

    func customLatestByIdentifier() -> [String: (value: Double, date: Date)] {
        var latest: [String: (value: Double, date: Date)] = [:]
        for sample in samples {
            guard sample.isCustomMetric else { continue }
            if latest[sample.kindRaw] == nil {
                latest[sample.kindRaw] = (value: sample.value, date: sample.date)
            }
        }
        return latest
    }
}
