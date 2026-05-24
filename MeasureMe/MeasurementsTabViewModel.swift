import SwiftUI
import SwiftData

@Observable @MainActor final class MeasurementsTabViewModel {
    var samples: [MetricSample] = []
    var customDefinitions: [CustomMetricDefinition] = []

    var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    var cachedCustomSamples: [String: [MetricSample]] = [:]
    var cachedCustomLatest: [String: MetricSample] = [:]

    func rebuildCaches() {
        var grouped: [MetricKind: [MetricSample]] = [:]
        var latest: [MetricKind: MetricSample] = [:]
        var customGrouped: [String: [MetricSample]] = [:]
        var customLatest: [String: MetricSample] = [:]

        for sample in samples {
            if sample.kindRaw.hasPrefix("custom_") {
                customGrouped[sample.kindRaw, default: []].append(sample)
                if customLatest[sample.kindRaw] == nil {
                    customLatest[sample.kindRaw] = sample
                }
                continue
            }
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            grouped[kind, default: []].append(sample)
            if latest[kind] == nil {
                latest[kind] = sample
            }
        }

        cachedSamplesByKind = grouped
        cachedLatestByKind = latest
        cachedCustomSamples = customGrouped
        cachedCustomLatest = customLatest
    }
}

@Observable @MainActor final class MetricChartTileViewModel {
    var samples: [MetricSample] = []
    var goals: [MetricGoal] = []

    var currentGoal: MetricGoal? { goals.first }
    var latest: MetricSample? { samples.last }
}
