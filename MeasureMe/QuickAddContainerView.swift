import SwiftUI
import SwiftData

struct QuickAddContainerView: View {

    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]

    @Query(sort: \CustomMetricDefinition.sortOrder)
    private var customDefinitions: [CustomMetricDefinition]

    @State private var viewModel = QuickAddViewModel()

    let onSaved: () -> Void

    var body: some View {
        QuickAddSheetView(
            kinds: metricsStore.activeKinds,
            latest: viewModel.latestByKind(),
            unitsSystem: unitsSystem,
            customDefinitions: viewModel.activeCustomDefinitions(metricsStore: metricsStore),
            customLatest: viewModel.customLatestByIdentifier(),
            onSaved: onSaved
        )
        .onChange(of: samples) { _, newValue in
            viewModel.samples = newValue
        }
        .onChange(of: customDefinitions) { _, newValue in
            viewModel.customDefinitions = newValue
        }
        .onAppear {
            viewModel.samples = samples
            viewModel.customDefinitions = customDefinitions
        }
    }
}
