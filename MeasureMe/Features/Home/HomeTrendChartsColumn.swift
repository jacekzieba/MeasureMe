import SwiftUI

/// Trend charts for the key metrics, shown beside the dashboard when Home has regular width
/// (an open iPhone Duo). Reuses the Measurements chart tiles, so both screens draw the same charts.
struct HomeTrendChartsColumn: View {
    let identifiers: [String]
    let customDefinitions: [String: CustomMetricDefinition]
    let unitsSystem: String
    let bottomPadding: CGFloat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("home.trends.title"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                ForEach(identifiers, id: \.self) { id in
                    if let kind = MetricKind(rawValue: id) {
                        MetricChartTile(kind: kind, unitsSystem: unitsSystem)
                    } else if let definition = customDefinitions[id] {
                        CustomMetricChartTile(definition: definition, theme: FeatureTheme.measurements)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
        }
        .accessibilityIdentifier("home.trendCharts")
        // `MetricChartTile` links by value and custom tiles open through `selectCustomMetricDetail`;
        // Home registers both destinations on its root.
    }
}
