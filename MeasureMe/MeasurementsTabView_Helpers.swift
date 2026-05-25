import SwiftUI
import Charts
import Accessibility

// MARK: - MetricGoalProgressSnapshot

struct MetricGoalProgressSnapshot {
    let progress: Double
    let percentage: Int
    let isAchieved: Bool

    init(goal: MetricGoal, currentValue: Double, baselineValue: Double) {
        let rawProgress: Double
        switch goal.direction {
        case .increase:
            let denominator = goal.targetValue - baselineValue
            rawProgress = denominator > 0 ? (currentValue - baselineValue) / denominator : 0
        case .decrease:
            let denominator = baselineValue - goal.targetValue
            rawProgress = denominator > 0 ? (baselineValue - currentValue) / denominator : 0
        }

        let clamped = min(max(rawProgress, 0), 1)
        self.progress = clamped
        self.percentage = Int((clamped * 100).rounded())
        self.isAchieved = goal.isAchieved(currentValue: currentValue) || clamped >= 1
    }
}

// MARK: - CompactGoalProgressPill

struct CompactGoalProgressPill: View {
    let progress: Double
    let percentage: Int
    let isAchieved: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColorRoles.surfaceInteractive)
                    Capsule()
                        .fill(isAchieved ? AppColorRoles.stateSuccess : accent)
                        .frame(width: proxy.size.width * max(0, min(progress, 1)))
                }
            }
            .frame(width: 28, height: 4)

            Text("\(percentage)%")
                .font(AppTypography.microBold)
                .monospacedDigit()
                .foregroundStyle(isAchieved ? AppColorRoles.stateSuccess : accent)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(AppColorRoles.surfaceInteractive, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("Progress"))
        .accessibilityValue("\(percentage)%")
    }
}

// MARK: - MetricValueText

struct MetricValueText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let parts = splitValue(text)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.value)
                .font(AppTypography.dataCompact)
                .monospacedDigit()
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func splitValue(_ text: String) -> (value: String, unit: String) {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (text, "") }
        return (parts[0], parts[1])
    }
}

// MARK: - MetricTileSparklineChart

struct MetricTileSparklineChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let samples: [MetricSample]
    let goal: MetricGoal?
    let accent: Color
    let yDomain: ClosedRange<Double>
    let xDomain: ClosedRange<Date>
    let displayValue: (Double) -> Double
    let yAxisLabel: (Double) -> String

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Date", sample.date),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", displayValue(sample.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            accent.opacity(colorScheme == .dark ? 0.32 : 0.22),
                            accent.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(samples) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", displayValue(sample.value))
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(accent)
            }

            if let latest = samples.last {
                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("Value", displayValue(latest.value))
                )
                .symbolSize(58)
                .foregroundStyle(accent)
            }

            if let goal {
                RuleMark(y: .value("Goal", displayValue(goal.targetValue)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(AppColorRoles.textTertiary.opacity(0.55))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7))
                    .foregroundStyle(AppColorRoles.borderSubtle.opacity(colorScheme == .dark ? 0.28 : 0.42))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(.clear)
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text(yAxisLabel(numericValue))
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColorRoles.textTertiary.opacity(colorScheme == .dark ? 0.78 : 0.88))
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
