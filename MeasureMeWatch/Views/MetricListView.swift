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
        } else {
            List {
                ForEach(activeMetrics) { kind in
                    MetricRowView(
                        kind: kind,
                        data: WatchMetricData.load(for: kind)
                    )
                    .listRowBackground(Color.white.opacity(0.06))
                }
            }
            .listStyle(.carousel)
        }
    }
}
