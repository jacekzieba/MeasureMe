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

                Text(kind.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
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
        }
        .padding(.vertical, 4)
    }
}
