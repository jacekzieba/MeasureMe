import SwiftUI

struct MetricRowView: View {
    let kind: WatchMetricKind
    let data: WatchMetricData?

    private var recentSamples: [WatchMetricData.SampleDTO] {
        data?.last30DaySamples ?? []
    }

    private var trendColor: Color {
        guard let data else { return .white.opacity(0.3) }
        switch data.trendOutcome(for: kind, recentSamples: recentSamples) {
        case .positive: return .watchGreen
        case .negative: return .watchRed
        case .neutral:  return .white.opacity(0.4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: icon + name
            HStack(spacing: 5) {
                Image(systemName: kind.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.watchAccent)
                    .accessibilityHidden(true)

                Text(kind.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.watchTertiaryText)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Value
                Text(data?.formattedValue(for: kind) ?? "—")
                    .font(.system(.body, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                // Delta pill
                if let delta = data?.deltaText(for: kind, recentSamples: recentSamples) {
                    Text(delta)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(trendColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(trendColor.opacity(0.13), in: Capsule())
                }
            }

            Text(data?.trendStatusText(for: kind, recentSamples: recentSamples) ?? watchLocalized("Not enough data", "Brak danych"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.watchSubtleText)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let value = data?.formattedValue(for: kind) ?? "—"
        let trend = data?.accessibilityTrendDescription(for: kind, recentSamples: recentSamples)
            ?? watchLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        return "\(value). \(trend)"
    }
}
