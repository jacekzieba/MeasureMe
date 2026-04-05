import SwiftUI
import WidgetKit

private extension Color {
    static let widgetAccent = Color(red: 0.988, green: 0.639, blue: 0.067)
    static let widgetGreen = Color(red: 0.133, green: 0.773, blue: 0.369)
    static let widgetRed = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let widgetInk = Color(red: 0.020, green: 0.031, blue: 0.086)
    static let widgetDayBlue = Color(red: 0.933, green: 0.957, blue: 1.000)
    static let widgetNightNavy = Color(red: 0.078, green: 0.129, blue: 0.239)
}

private enum WidgetAppearance {
    case system
    case light
    case dark

    init(rawValue: String?) {
        switch rawValue {
        case "light": self = .light
        case "dark": self = .dark
        default: self = .system
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
    let textSubtle: Color
    let divider: Color

    init(scheme: ColorScheme) {
        if scheme == .dark {
            canvas = .widgetNightNavy
            textPrimary = .white
            textSecondary = Color.white.opacity(0.80)
            textSubtle = Color.white.opacity(0.58)
            divider = Color.white.opacity(0.12)
        } else {
            canvas = .widgetDayBlue
            textPrimary = .widgetInk
            textSecondary = Color.widgetInk.opacity(0.80)
            textSubtle = Color.widgetInk.opacity(0.56)
            divider = Color.widgetInk.opacity(0.12)
        }
    }
}

private struct MetricMainCard: View {
    let kind: WidgetMetricKind
    let data: WidgetMetricData?
    let trendWindow: WidgetTrendWindow
    let displayMode: WidgetDisplayMode
    let palette: WidgetPalette
    let interactionTarget: WidgetInteractionTarget

    private var recent: [WidgetMetricData.SampleDTO] { data?.samples(for: trendWindow) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(Color.widgetAccent)
                Text(kind.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if interactionTarget == .quickAdd {
                    Button(intent: OpenQuickAddFromWidgetIntent(metric: kind)) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.widgetAccent)
                }
            }

            Text(valueText)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if displayMode == .goalProgress {
                goalBlock
            } else {
                trendBlock
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var valueText: String {
        guard let value = data?.latestDisplayValue(for: kind) else { return "—" }
        return kind.formattedDisplayValue(value, isMetric: data?.isMetric ?? true)
    }

    @ViewBuilder
    private var trendBlock: some View {
        if let delta = data?.deltaText(for: kind, recentSamples: recent) {
            Text(delta)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(trendColor)
        } else {
            Text("\(trendWindow.days)d")
                .font(.caption2)
                .foregroundStyle(palette.textSubtle)
        }

        Text(data?.trendStatusText(for: kind, recentSamples: recent) ?? widgetLocalized("Not enough data", "Brak danych"))
            .font(.caption2)
            .foregroundStyle(palette.textSubtle)

        WidgetSparklineView(samples: recent, trendColor: trendColor)
            .frame(height: 36)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var goalBlock: some View {
        if let progress = data?.goalProgress(for: kind) {
            Gauge(value: progress) {
                Text(widgetLocalized("Goal", "Cel"))
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
            }
            .tint(trendColor)
            .gaugeStyle(.linearCapacity)

            if let goalText = data?.accessibilityGoalDescription(for: kind) {
                Text(goalText)
                    .font(.caption2)
                    .foregroundStyle(palette.textSubtle)
                    .lineLimit(1)
            }
        } else {
            Text(widgetLocalized("No goal set", "Brak ustawionego celu"))
                .font(.caption2)
                .foregroundStyle(palette.textSubtle)
        }
    }

    private var trendColor: Color {
        guard let data else { return palette.textSubtle }
        switch data.trendOutcome(for: kind, recentSamples: recent) {
        case .positive: return .widgetGreen
        case .negative: return .widgetRed
        case .neutral: return palette.textSubtle
        }
    }

    private var accessibilityValue: String {
        let trend = data?.accessibilityTrendDescription(for: kind, recentSamples: recent)
            ?? widgetLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        return "\(valueText). \(trend)"
    }
}

struct MetricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: MetricEntry

    private var effectiveColorScheme: ColorScheme {
        switch WidgetAppearance.current() {
        case .system: return colorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var palette: WidgetPalette { WidgetPalette(scheme: effectiveColorScheme) }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                MetricMainCard(
                    kind: entry.configuration.metric,
                    data: entry.data,
                    trendWindow: entry.configuration.trendWindow,
                    displayMode: entry.configuration.displayMode,
                    palette: palette,
                    interactionTarget: entry.configuration.interactionTarget
                )
                .padding(14)
            case .systemMedium:
                mediumBody
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            case .accessoryInline:
                accessoryInline
            case .accessoryCircular:
                accessoryCircular
            case .accessoryRectangular:
                accessoryRectangular
            default:
                MetricMainCard(
                    kind: entry.configuration.metric,
                    data: entry.data,
                    trendWindow: entry.configuration.trendWindow,
                    displayMode: entry.configuration.displayMode,
                    palette: palette,
                    interactionTarget: entry.configuration.interactionTarget
                )
                .padding(14)
            }
        }
        .containerBackground(for: .widget) { palette.canvas }
    }

    private var mediumBody: some View {
        HStack(spacing: 0) {
            MetricMainCard(
                kind: entry.configuration.metric,
                data: entry.data,
                trendWindow: entry.configuration.trendWindow,
                displayMode: entry.configuration.displayMode,
                palette: palette,
                interactionTarget: entry.configuration.interactionTarget
            )
            if entry.configuration.mediumLayout == .threeColumns {
                divider
                MetricMainCard(
                    kind: entry.configuration.metric2,
                    data: entry.data2,
                    trendWindow: entry.configuration.trendWindow,
                    displayMode: entry.configuration.displayMode,
                    palette: palette,
                    interactionTarget: entry.configuration.interactionTarget
                )
                divider
                MetricMainCard(
                    kind: entry.configuration.metric3,
                    data: entry.data3,
                    trendWindow: entry.configuration.trendWindow,
                    displayMode: entry.configuration.displayMode,
                    palette: palette,
                    interactionTarget: entry.configuration.interactionTarget
                )
            } else {
                divider
                MetricMainCard(
                    kind: entry.configuration.metric2,
                    data: entry.data2,
                    trendWindow: entry.configuration.trendWindow,
                    displayMode: entry.configuration.displayMode,
                    palette: palette,
                    interactionTarget: entry.configuration.interactionTarget
                )
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(palette.divider).frame(width: 0.5).padding(.vertical, 6)
    }

    private var accessoryInline: some View {
        let kind = entry.configuration.metric
        let recent = entry.data?.samples(for: entry.configuration.trendWindow) ?? []
        let value = entry.data?.latestDisplayValue(for: kind)
        let formatted = value.map { kind.formattedDisplayValue($0, isMetric: entry.data?.isMetric ?? true) } ?? "—"
        let status = entry.data?.trendStatusText(for: kind, recentSamples: recent) ?? "—"
        return Text("\(kind.displayName): \(formatted) · \(status)")
    }

    private var accessoryCircular: some View {
        let kind = entry.configuration.metric
        let value = entry.data?.latestDisplayValue(for: kind)
        let short = value.map { String(format: "%.1f", $0) } ?? "—"
        return VStack(spacing: 2) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(short)
                .font(.system(size: 12, design: .rounded).weight(.bold).monospacedDigit())
                .lineLimit(1)
        }
    }

    private var accessoryRectangular: some View {
        let kind = entry.configuration.metric
        let recent = entry.data?.samples(for: entry.configuration.trendWindow) ?? []
        let value = entry.data?.latestDisplayValue(for: kind)
        let formatted = value.map { kind.formattedDisplayValue($0, isMetric: entry.data?.isMetric ?? true) } ?? "—"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: kind.systemImage)
                Text(kind.displayName)
                Spacer(minLength: 0)
                Text(formatted)
                    .monospacedDigit()
            }
            if let delta = entry.data?.deltaText(for: kind, recentSamples: recent) {
                Text(delta)
                    .foregroundStyle(.secondary)
            }
            if entry.configuration.interactionTarget == .quickAdd {
                Button(intent: OpenQuickAddFromWidgetIntent(metric: kind)) {
                    Text(widgetLocalized("Quick Add", "Szybkie dodawanie"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.widgetAccent)
            }
        }
    }
}

struct SmartMetricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SmartMetricEntry

    var body: some View {
        Group {
            if !entry.premiumEnabled {
                premiumLockedView
            } else {
                MetricMainCard(
                    kind: entry.selectedKind,
                    data: entry.data,
                    trendWindow: entry.configuration.trendWindow,
                    displayMode: entry.configuration.displayMode,
                    palette: WidgetPalette(scheme: .dark),
                    interactionTarget: entry.configuration.interactionTarget
                )
                .padding(12)
            }
        }
        .containerBackground(for: .widget) {
            Color.widgetNightNavy
        }
    }

    private var premiumLockedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(widgetLocalized("Smart Widget", "Smart Widget"))
                .font(.headline)
            Text(widgetLocalized("Premium required", "Wymaga Premium"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if family == .systemSmall || family == .systemMedium {
                Button(intent: OpenQuickAddFromWidgetIntent(metric: nil)) {
                    Text(widgetLocalized("Open app", "Otwórz aplikację"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.widgetAccent)
            }
        }
        .padding(12)
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        Group {
            if !entry.premiumEnabled {
                locked
            } else {
                content
            }
        }
        .containerBackground(for: .widget) { Color.widgetNightNavy }
    }

    private var content: some View {
        let streak = entry.streak
        return VStack(alignment: .leading, spacing: 6) {
            Text(widgetLocalized("Streak", "Seria"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(streak?.currentStreak ?? 0)")
                .font(.system(size: family == .systemSmall ? 34 : 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text((streak?.loggedToday ?? false)
                 ? widgetLocalized("Logged this week", "Zalogowano w tym tygodniu")
                 : widgetLocalized("Not logged yet", "Jeszcze nie zalogowano"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(intent: OpenQuickAddFromWidgetIntent(metric: nil)) {
                Text(widgetLocalized("Quick Add", "Szybkie dodawanie"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.widgetAccent)
        }
        .padding(12)
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(widgetLocalized("Streak", "Seria"))
                .font(.headline)
            Text(widgetLocalized("Premium required", "Wymaga Premium"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
