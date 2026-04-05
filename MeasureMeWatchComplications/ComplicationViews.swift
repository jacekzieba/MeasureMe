import SwiftUI
import WidgetKit

struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var kind: ComplicationMetricKind {
        entry.configuration.metric
    }

    private var data: ComplicationMetricData? { entry.data }

    private var recentSamples: [ComplicationMetricData.SampleDTO] {
        data?.samples(for: entry.configuration.trendWindow) ?? []
    }

    var body: some View {
        switch family {
        case .accessoryCircular:    circularView
        case .accessoryInline:      inlineView
        case .accessoryCorner:      cornerView
        case .accessoryRectangular: rectangularView
        default:                    circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        VStack(spacing: 1) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)

            Text(shortValueText)
                .font(.system(size: 13, design: .rounded).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(complicationAccessibilityValue)
    }

    // MARK: - Inline

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .accessibilityHidden(true)
            Text(inlineValueText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(complicationAccessibilityValue)
    }

    // MARK: - Corner

    private var cornerView: some View {
        Text(shortValueWithUnit)
            .font(.system(size: 14, design: .rounded).weight(.bold).monospacedDigit())
            .minimumScaleFactor(0.5)
            .widgetCurvesContent()
            .widgetLabel {
                if let progress = goalProgress {
                    Gauge(value: progress, in: 0...1) {
                        Image(systemName: kind.systemImage)
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(trendGradient)
                } else {
                    Text(data?.trendStatusText(for: kind, recentSamples: recentSamples) ?? kind.shortName)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.displayName)
            .accessibilityValue(complicationAccessibilityValue)
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)

                Text(kind.shortName)
                    .font(.system(size: 10, weight: .semibold))

                Spacer()

                Text(shortValueWithUnit)
                    .font(.system(size: 12, design: .rounded).weight(.bold).monospacedDigit())
            }

            if let delta = data?.deltaText(for: kind, recentSamples: recentSamples) {
                Text(delta)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(trendColor)
            }

            Text(data?.trendStatusText(for: kind, recentSamples: recentSamples)
                 ?? complicationLocalized("Not enough data", "Brak danych"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            ComplicationSparklineView(samples: recentSamples)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(complicationAccessibilityValue)
    }

    // MARK: - Helpers

    private var shortValueText: String {
        guard let data, let val = data.latestDisplayValue(for: kind) else { return "—" }
        return String(format: "%.1f", val)
    }

    private var shortValueWithUnit: String {
        guard let data, let val = data.latestDisplayValue(for: kind) else { return "—" }
        let unit = kind.unitSymbol(isMetric: data.isMetric)
        return String(format: "%.1f%@", val, unit)
    }

    private var inlineValueText: String {
        guard let data else { return "\(kind.displayName): —" }
        return "\(kind.shortName) \(data.formattedValue(for: kind))"
    }

    private var goalProgress: Double? {
        guard let goal = data?.goal,
              let latest = data?.latestDisplayValue(for: kind) else { return nil }
        let start = goal.startValue ?? latest
        let target = kind.valueForDisplay(fromMetric: goal.targetValue, isMetric: data?.isMetric ?? true)
        let startDisplay = kind.valueForDisplay(fromMetric: start, isMetric: data?.isMetric ?? true)
        let total = abs(target - startDisplay)
        guard total > 0 else { return 1.0 }
        let progress = 1.0 - abs(target - latest) / total
        return min(max(progress, 0), 1)
    }

    private var trendColor: Color {
        guard let data else { return .secondary }
        switch data.trendOutcome(for: kind, recentSamples: recentSamples) {
        case .positive: return .green
        case .negative: return .red
        case .neutral:  return .secondary
        }
    }

    private var trendGradient: Gradient {
        Gradient(colors: [trendColor.opacity(0.5), trendColor])
    }

    private var complicationAccessibilityValue: String {
        let value = data?.formattedValue(for: kind) ?? "—"
        let trend = data?.accessibilityTrendDescription(for: kind, recentSamples: recentSamples)
            ?? complicationLocalized("Not enough data for trend", "Za mało danych, aby ocenić trend")
        if let goal = data?.accessibilityGoalDescription(for: kind) {
            return "\(value). \(trend). \(goal)"
        }
        return "\(value). \(trend)"
    }
}

// MARK: - Sparkline

private struct ComplicationSparklineView: View {
    let samples: [ComplicationMetricData.SampleDTO]

    var body: some View {
        GeometryReader { geo in
            if samples.count < 2 {
                Path { path in
                    let mid = geo.size.height / 2
                    path.move(to: CGPoint(x: 0, y: mid))
                    path.addLine(to: CGPoint(x: geo.size.width, y: mid))
                }
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                let points = normalizedPoints(in: geo.size)
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let values = samples.map(\.value)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let range = maxV - minV > 0 ? maxV - minV : 1
        let padding: CGFloat = 0.10
        let adjustedH = size.height * (1 - 2 * padding)

        return samples.enumerated().map { idx, s in
            let x = size.width * CGFloat(idx) / CGFloat(max(samples.count - 1, 1))
            let normalized = (s.value - minV) / range
            let y = size.height * padding + adjustedH * (1 - normalized)
            return CGPoint(x: x, y: y)
        }
    }
}
