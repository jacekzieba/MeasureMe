import SwiftUI

struct MetricListView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    private var activeMetrics: [WatchMetricKind] {
        connectivity.activeMetrics
    }

    var body: some View {
        if activeMetrics.isEmpty {
            ContentUnavailableView {
                Label(WatchLocalization.string("No Metrics"),
                      systemImage: "ruler")
            } description: {
                Text(WatchLocalization.string("Enable metrics on your iPhone to see them here."))
                    .font(.caption2)
            }
            .accessibilityLabel(WatchLocalization.string("No Metrics"))
            .accessibilityValue(WatchLocalization.string("Enable metrics on your iPhone to see them here."))
        } else {
            List {
                ForEach(activeMetrics) { kind in
                    let data = WatchMetricData.load(for: kind)
                    NavigationLink {
                        MetricDetailView(kind: kind, data: data, unitsSystem: connectivity.unitsSystem)
                    } label: {
                        MetricRowView(kind: kind, data: data, unitsSystem: connectivity.unitsSystem)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    .accessibilityHint(watchLocalized("Shows metric details", "Pokazuje szczegóły metryki"))
                }
            }
            .listStyle(.carousel)
        }
    }
}
