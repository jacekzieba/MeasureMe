import SwiftUI
import WidgetKit

// MARK: - Colours (self-contained, no dependency on main app)

private extension Color {
    /// App accent: #FCA311
    static let widgetAccent = Color(red: 0.988, green: 0.639, blue: 0.067)
    /// Background navy: #14213D
    static let widgetNavy   = Color(red: 0.078, green: 0.129, blue: 0.239)
    /// Positive trend: #22C55E
    static let widgetGreen  = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// Negative trend: #EF4444
    static let widgetRed    = Color(red: 0.937, green: 0.267, blue: 0.267)
}

// MARK: - Shared sub-views

/// SF Symbol wrapped in a small accent-coloured circle badge.
private struct MetricIconBadge: View {
    let systemImage: String
    let size: BadgeSize

    enum BadgeSize {
        case regular   // small widget header
        case compact   // medium widget column
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(size == .regular ? .caption.weight(.semibold) : .system(size: 9, weight: .semibold))
            .foregroundStyle(Color.widgetAccent)
            .padding(size == .regular ? 5 : 3.5)
            .background(Color.widgetAccent.opacity(0.14), in: Circle())
    }
}

/// Delta text wrapped in a trend-coloured capsule badge.
private struct DeltaPill: View {
    let text: String
    let color: Color
    let compact: Bool

    var body: some View {
        Text(text)
            .font(compact
                  ? .system(size: 9, weight: .semibold)
                  : .caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, compact ? 1.5 : 2)
            .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: - MetricWidgetView

struct MetricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MetricEntry

    // Primary metric (small widget)
    private var kind: WidgetMetricKind { entry.configuration.metric }
    private var data: WidgetMetricData? { entry.data }

    private var primaryRecentSamples: [WidgetMetricData.SampleDTO] { data?.last30DaySamples ?? [] }
    private var latestValueText: String { valueTextFor(kind: kind, data: data) }
    private var deltaText: String? { data?.deltaText(for: kind, recentSamples: primaryRecentSamples) }
    private var trendColor: Color { colorFor(kind: kind, data: data, recentSamples: primaryRecentSamples) }
    private var sparklineSamples: [WidgetMetricData.SampleDTO] { primaryRecentSamples }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  smallBody
            case .systemMedium: mediumBody
            default:            smallBody
            }
        }
        .containerBackground(for: .widget) {
            Color.widgetNavy
        }
    }

    // MARK: - Small (2×2)

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon badge + name
            HStack(spacing: 6) {
                MetricIconBadge(systemImage: kind.systemImage, size: .regular)
                Text(kind.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Value
            Text(latestValueText)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Delta pill
            Group {
                if let delta = deltaText {
                    DeltaPill(text: delta, color: trendColor, compact: false)
                } else {
                    Text("widget.period.30d")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.top, 3)

            Spacer(minLength: 6)

            // Sparkline
            WidgetSparklineView(samples: sparklineSamples, trendColor: trendColor)
                .frame(height: 38)
        }
        .padding(16)
    }

    // MARK: - Medium (4×2): 3 metric columns

    private var mediumBody: some View {
        HStack(spacing: 0) {
            metricColumn(kind: entry.configuration.metric,  data: entry.data)
            columnDivider
            metricColumn(kind: entry.configuration.metric2, data: entry.data2)
            columnDivider
            metricColumn(kind: entry.configuration.metric3, data: entry.data3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func metricColumn(kind: WidgetMetricKind, data: WidgetMetricData?) -> some View {
        let recent = data?.last30DaySamples ?? []
        let trend = colorFor(kind: kind, data: data, recentSamples: recent)
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon badge + name
            HStack(spacing: 4) {
                MetricIconBadge(systemImage: kind.systemImage, size: .compact)
                Text(kind.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            // Value
            Text(valueTextFor(kind: kind, data: data))
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            // Delta pill
            Group {
                if let delta = data?.deltaText(for: kind, recentSamples: recent) {
                    DeltaPill(text: delta, color: trend, compact: true)
                } else {
                    Text("widget.period.30d")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.20))
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 0)

            // Sparkline
            WidgetSparklineView(samples: recent, trendColor: trend)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 5)
    }

    // MARK: - Helpers

    private func valueTextFor(kind: WidgetMetricKind, data: WidgetMetricData?) -> String {
        guard let val = data?.latestDisplayValue(for: kind) else { return "—" }
        let unit = kind.unitSymbol(isMetric: data?.isMetric ?? true)
        let fmt = kind.unitCategory == .percent ? "%.1f%@" : "%.1f\u{202F}%@"
        return String(format: fmt, val, unit)
    }

    private func colorFor(
        kind: WidgetMetricKind,
        data: WidgetMetricData?,
        recentSamples: [WidgetMetricData.SampleDTO]
    ) -> Color {
        guard let data else { return .white.opacity(0.3) }
        switch data.trendOutcome(for: kind, recentSamples: recentSamples) {
        case .positive: return .widgetGreen
        case .negative: return .widgetRed
        case .neutral:  return .white.opacity(0.4)
        }
    }
}
