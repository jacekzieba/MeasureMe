import SwiftUI
import SwiftData

struct QuickAddContainerView: View {

    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]

    let onSaved: () -> Void

    var body: some View {
        QuickAddSheetView(
            kinds: metricsStore.activeKinds,
            latest: latestByKind,
            unitsSystem: unitsSystem,
            onSaved: onSaved
        )
    }
    
    private var latestByKind: [MetricKind: (value: Double, date: Date)] {
        var latest: [MetricKind: (value: Double, date: Date)] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else {
                AppLog.debug("⚠️ Ignoring MetricSample with invalid kindRaw: \(sample.kindRaw)")
                continue
            }
            if latest[kind] == nil {
                latest[kind] = (value: sample.value, date: sample.date)
            }
        }
        return latest
    }
}
