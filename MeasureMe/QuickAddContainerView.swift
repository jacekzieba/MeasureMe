import SwiftUI
import SwiftData

struct QuickAddContainerView: View {

    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]

    @Query(sort: \CustomMetricDefinition.sortOrder)
    private var customDefinitions: [CustomMetricDefinition]

    let onSaved: () -> Void

    var body: some View {
        QuickAddSheetView(
            kinds: metricsStore.activeKinds,
            latest: latestByKind,
            unitsSystem: unitsSystem,
            customDefinitions: activeCustomDefinitions,
            customLatest: customLatestByIdentifier,
            onSaved: onSaved
        )
    }

    private var latestByKind: [MetricKind: (value: Double, date: Date)] {
        var latest: [MetricKind: (value: Double, date: Date)] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            if latest[kind] == nil {
                latest[kind] = (value: sample.value, date: sample.date)
            }
        }
        return latest
    }

    private var activeCustomDefinitions: [CustomMetricDefinition] {
        customDefinitions.filter { metricsStore.isCustomEnabled($0.identifier) }
    }

    private var customLatestByIdentifier: [String: (value: Double, date: Date)] {
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
