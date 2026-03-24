import SwiftUI

struct MetricListView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    private var activeMetrics: [WatchMetricKind] {
        connectivity.activeMetrics
    }

    var body: some View {
        if activeMetrics.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Metrics", table: "Watch"),
                      systemImage: "ruler")
            } description: {
                Text(String(localized: "Enable metrics on your iPhone to see them here.", table: "Watch"))
                    .font(.caption2)
            }
            .accessibilityLabel(String(localized: "No Metrics", table: "Watch"))
            .accessibilityValue(String(localized: "Enable metrics on your iPhone to see them here.", table: "Watch"))
        } else {
            List {
                ForEach(activeMetrics) { kind in
                    let data = WatchMetricData.load(for: kind)
                    NavigationLink {
                        MetricDetailView(kind: kind, data: data)
                    } label: {
                        MetricRowView(kind: kind, data: data)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    .accessibilityHint(watchLocalized("Shows metric details", "Pokazuje szczegóły metryki"))
                }
            }
            .listStyle(.carousel)
        }
    }
}
