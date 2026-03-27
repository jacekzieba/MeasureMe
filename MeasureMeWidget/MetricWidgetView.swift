import SwiftUI
import WidgetKit

// MARK: - Colours (self-contained, no dependency on main app)

private extension Color {
    /// App accent: #FCA311
    static let widgetAccent = Color(red: 0.988, green: 0.639, blue: 0.067)
    /// Positive trend: #22C55E
    static let widgetGreen  = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// Negative trend: #EF4444
    static let widgetRed    = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let widgetInk = Color(red: 0.020, green: 0.031, blue: 0.086)
    static let widgetPaper = Color(red: 0.969, green: 0.973, blue: 0.984)
    static let widgetDayBlue = Color(red: 0.933, green: 0.957, blue: 1.000)
    static let widgetNightNavy = Color(red: 0.078, green: 0.129, blue: 0.239)
}

private enum WidgetAppearance {
    case system
    case light
    case dark

    init(rawValue: String?) {
        switch rawValue {
        case "light":
            self = .light
        case "dark":
            self = .dark
        default:
            self = .system
        }
    }

    static func current() -> WidgetAppearance {
        let defaults = UserDefaults(suiteName: widgetAppGroupID)
        return WidgetAppearance(rawValue: defaults?.string(forKey: "appAppearance"))
    }
}

private struct WidgetPalette {
    let canvas: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textSubtle: Color
    let divider: Color
    let badgeBackground: Color

    init(scheme: ColorScheme) {
        if scheme == .dark {
            canvas = .widgetNightNavy
            textPrimary = .white
            textSecondary = Color.white.opacity(0.82)
            textTertiary = Color.white.opacity(0.68)
            textSubtle = Color.white.opacity(0.56)
            divider = Color.white.opacity(0.10)
            badgeBackground = Color.widgetAccent.opacity(0.14)
        } else {
            canvas = Color.widgetDayBlue
            textPrimary = .widgetInk
            textSecondary = Color.widgetInk.opacity(0.80)
            textTertiary = Color.widgetInk.opacity(0.64)
            textSubtle = Color.widgetInk.opacity(0.50)
            divider = Color.widgetInk.opacity(0.10)
            badgeBackground = Color.widgetAccent.opacity(0.18)
        }
    }
}

// MARK: - Shared sub-views

/// SF Symbol wrapped in a small accent-coloured circle badge.
private struct MetricIconBadge: View {
    let systemImage: String
    let size: BadgeSize
    let palette: WidgetPalette

    enum BadgeSize {
        case regular   // small widget header
        case compact   // medium widget column
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(size == .regular ? .caption.weight(.semibold) : .system(size: 9, weight: .semibold))
            .foregroundStyle(Color.widgetAccent)
            .padding(size == .regular ? 5 : 3.5)
            .background(palette.badgeBackground, in: Circle())
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

private struct TrendStatusLabel: View {
    let text: String
    let compact: Bool
    let palette: WidgetPalette

    var body: some View {
        Text(text)
            .font(compact ? .system(size: 9, weight: .medium) : .caption2.weight(.medium))
            .foregroundStyle(palette.textSubtle)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - MetricWidgetView

struct MetricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: MetricEntry

    // Primary metric (small widget)
    private var kind: WidgetMetricKind { entry.configuration.metric }
    private var data: WidgetMetricData? { entry.data }

    private var primaryRecentSamples: [WidgetMetricData.SampleDTO] { data?.last30DaySamples ?? [] }
    private var latestValueText: String { valueTextFor(kind: kind, data: data) }
    private var deltaText: String? { data?.deltaText(for: kind, recentSamples: primaryRecentSamples) }
    private var trendColor: Color { colorFor(kind: kind, data: data, recentSamples: primaryRecentSamples) }
    private var sparklineSamples: [WidgetMetricData.SampleDTO] { primaryRecentSamples }
    private var palette: WidgetPalette { WidgetPalette(scheme: effectiveColorScheme) }

    private var effectiveColorScheme: ColorScheme {
        switch WidgetAppearance.current() {
        case .system:
            return colorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  smallBody
            case .systemMedium: mediumBody
            default:            smallBody
            }
        }
        .containerBackground(for: .widget) {
            palette.canvas
        }
    }

    // MARK: - Small (2×2)

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon badge + name
            HStack(spacing: 6) {
                MetricIconBadge(systemImage: kind.systemImage, size: .regular, palette: palette)
                Text(kind.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Value
            Text(latestValueText)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Delta pill
            Group {
                if let delta = deltaText {
                    DeltaPill(text: delta, color: trendColor, compact: false)
                } else {
                    Text("widget.period.30d")
                        .font(.caption2)
                        .foregroundStyle(palette.textSubtle)
                }
            }
            .padding(.top, 3)

            TrendStatusLabel(
                text: data?.trendStatusText(for: kind, recentSamples: primaryRecentSamples)
                    ?? widgetLocalized("Not enough data", "Brak danych"),
                compact: false,
                palette: palette
            )
            .padding(.top, 3)

            Spacer(minLength: 6)

            // Sparkline
            WidgetSparklineView(samples: sparklineSamples, trendColor: trendColor)
                .frame(height: 38)
                .accessibilityHidden(true)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(widgetAccessibilityValue(kind: kind, data: data, recentSamples: primaryRecentSamples))
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
            .fill(palette.divider)
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
                MetricIconBadge(systemImage: kind.systemImage, size: .compact, palette: palette)
                Text(kind.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            // Value
            Text(valueTextFor(kind: kind, data: data))
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            // Delta pill
            Group {
                if let delta = data?.deltaText(for: kind, recentSamples: recent) {
                    DeltaPill(text: delta, color: trend, compact: true)
                } else {
                    Text("widget.period.30d")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSubtle)
                }
            }
            .padding(.top, 2)

            TrendStatusLabel(
                text: data?.trendStatusText(for: kind, recentSamples: recent)
                    ?? widgetLocalized("Not enough data", "Brak danych"),
                compact: true,
                palette: palette
            )
            .padding(.top, 2)

            Spacer(minLength: 0)

            // Sparkline
            WidgetSparklineView(samples: recent, trendColor: trend)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(widgetAccessibilityValue(kind: kind, data: data, recentSamples: recent))
    }

    // MARK: - Helpers

    private func valueTextFor(kind: WidgetMetricKind, data: WidgetMetricData?) -> String {
        guard let val = data?.latestDisplayValue(for: kind) else { return "—" }
        return kind.formattedDisplayValue(val, isMetric: data?.isMetric ?? true)
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

    private func widgetAccessibilityValue(
        kind: WidgetMetricKind,
        data: WidgetMetricData?,
        recentSamples: [WidgetMetricData.SampleDTO]
    ) -> String {
        let value = valueTextFor(kind: kind, data: data)
        let trend = data?.accessibilityTrendDescription(for: kind, recentSamples: recentSamples)
            ?? widgetLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        if let goal = data?.accessibilityGoalDescription(for: kind) {
            return "\(value). \(trend). \(goal)"
        }
        return "\(value). \(trend)"
    }
}
