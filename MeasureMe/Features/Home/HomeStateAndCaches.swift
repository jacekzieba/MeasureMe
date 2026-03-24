import SwiftUI
import SwiftData

extension HomeView {
    static func isAfterPhotoSyncCursor(
        photoDate: Date,
        photoID: String,
        cursorDate: Double,
        cursorID: String
    ) -> Bool {
        let photoTime = photoDate.timeIntervalSince1970
        if photoTime > cursorDate {
            return true
        }
        if photoTime < cursorDate {
            return false
        }
        return photoID > cursorID
    }

    static func newestPhotoSyncCursor(candidates: [(date: Date, id: String)]) -> (date: Double, id: String)? {
        guard let newest = candidates.max(by: { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id < rhs.id
        }) else { return nil }
        return (newest.date.timeIntervalSince1970, newest.id)
    }
}

struct HomeKeyMetricRow: View {
    let kind: MetricKind
    let latest: MetricSample?
    let goal: MetricGoal?
    let samples: [MetricSample]
    let unitsSystem: String

    private let cornerRadius: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    kind.iconView(font: AppTypography.metricTitle, size: 16, tint: Color.appAccent)

                    ViewThatFits(in: .vertical) {
                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let latest {
                    Text(valueString(metricValue: latest.value))
                        .font(AppTypography.metricValue)
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)

                    if let goal = goal {
                        HomeGoalProgressBar(
                            goal: goal,
                            latest: latest,
                            baselineValue: baselineValue(for: goal),
                            format: { valueString(metricValue: $0) }
                        )
                    } else {
                        Text(AppLocalization.string("Set a goal to see progress."))
                            .font(AppTypography.micro)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text(AppLocalization.string("—"))
                        .font(AppTypography.metricValue)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(AppLocalization.string("No data yet"))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 8)

            if !samples.isEmpty {
                MiniSparklineChart(samples: samples, kind: kind, goal: goal)
                    .frame(width: 90, height: 44)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 90, height: 44)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: cornerRadius,
                tint: Color.appAccent.opacity(0.10)
            )
        )
    }

    private func valueString(metricValue: Double) -> String {
        kind.formattedMetricValue(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    private func baselineValue(for goal: MetricGoal) -> Double {
        if let sv = goal.startValue { return sv }
        guard !samples.isEmpty else { return latest?.value ?? goal.targetValue }
        let sorted = samples.sorted { $0.date < $1.date }
        if let baseline = sorted.last(where: { $0.date <= goal.createdDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? (latest?.value ?? goal.targetValue)
    }
}

private struct HomeGoalProgressBar: View {
    let goal: MetricGoal
    let latest: MetricSample
    let baselineValue: Double
    let format: (Double) -> String

    var body: some View {
        let currentVal = latest.value
        let goalVal = goal.targetValue
        let progress: Double
        let isAchieved: Bool
        switch goal.direction {
        case .increase:
            let denominator = goalVal - baselineValue
            if denominator <= 0 {
                progress = 0.0
                isAchieved = false
            } else {
                let raw = (currentVal - baselineValue) / denominator
                progress = min(max(raw, 0.0), 1.0)
                isAchieved = progress >= 1.0
            }
        case .decrease:
            let denominator = baselineValue - goalVal
            if denominator <= 0 {
                progress = 0.0
                isAchieved = false
            } else {
                let raw = (baselineValue - currentVal) / denominator
                progress = min(max(raw, 0.0), 1.0)
                isAchieved = progress >= 1.0
            }
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLocalization.string("Progress"))
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(AppTypography.microEmphasis.monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(isAchieved ? Color(hex: "#22C55E") : Color(hex: "#FCA311"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(isAchieved ? Color(hex: "#22C55E") : Color(hex: "#FCA311"))
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                }
            }
            .frame(height: 6)

            HStack {
                Text(AppLocalization.string("progress.now", format(currentVal)))
                    .font(AppTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(AppLocalization.string("progress.goal", format(goalVal)))
                    .font(AppTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Custom Metric Sparkline (no MetricKind dependency)

/// Sparkline chart for custom metrics. Uses favorsDecrease to determine trend color.
struct CustomMiniSparklineChart: View {
    private let recentSamples: [MetricSample]
    private let trendColor: Color

    init(samples: [MetricSample], favorsDecrease: Bool, goal: MetricGoal?) {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
        let filtered = samples
            .filter { $0.date >= thirtyDaysAgo }
            .sorted { $0.date < $1.date }
        self.recentSamples = filtered

        if filtered.count >= 2, let first = filtered.first?.value, let last = filtered.last?.value {
            let outcome: MetricKind.TrendOutcome
            if let goal {
                let startDist = abs(goal.targetValue - first)
                let endDist = abs(goal.targetValue - last)
                if endDist < startDist { outcome = .positive }
                else if endDist > startDist { outcome = .negative }
                else { outcome = .neutral }
            } else {
                let delta = last - first
                if delta == 0 { outcome = .neutral }
                else if favorsDecrease { outcome = delta < 0 ? .positive : .negative }
                else { outcome = delta > 0 ? .positive : .negative }
            }
            switch outcome {
            case .positive: self.trendColor = Color(hex: "#22C55E").opacity(0.85)
            case .negative: self.trendColor = Color(hex: "#EF4444").opacity(0.85)
            case .neutral:  self.trendColor = Color.gray.opacity(0.5)
            }
        } else {
            self.trendColor = Color.gray.opacity(0.5)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)
            if points.isEmpty {
                Path { path in
                    let midY = geometry.size.height / 2
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: midY))
                }
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                ZStack(alignment: .bottom) {
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: CGPoint(x: firstPoint.x, y: geometry.size.height))
                        path.addLine(to: firstPoint)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        if let lastPoint = points.last {
                            path.addLine(to: CGPoint(x: lastPoint.x, y: geometry.size.height))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [trendColor.opacity(0.15), trendColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: firstPoint)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(trendColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !recentSamples.isEmpty else { return [] }
        let values = recentSamples.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        let useRange = range > 0 ? range : 1
        let padding: CGFloat = 0.1
        let adjustedHeight = size.height * (1 - 2 * padding)
        return recentSamples.enumerated().map { index, sample in
            let x = recentSamples.count > 1
                ? size.width * CGFloat(index) / CGFloat(recentSamples.count - 1)
                : size.width / 2
            let normalizedValue = (sample.value - minValue) / useRange
            let y = size.height * padding + adjustedHeight * (1 - normalizedValue)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Home Custom Key Metric Row

struct HomeCustomKeyMetricRow: View {
    let definition: CustomMetricDefinition
    let latest: MetricSample?
    let goal: MetricGoal?
    let samples: [MetricSample]

    private let cornerRadius: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: definition.sfSymbolName)
                        .font(AppTypography.metricTitle)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Color.appAccent)

                    ViewThatFits(in: .vertical) {
                        Text(definition.name)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(definition.name)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let latest {
                    Text(formattedValue(latest.value))
                        .font(AppTypography.metricValue)
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)

                    if let goal {
                        HomeGoalProgressBar(
                            goal: goal,
                            latest: latest,
                            baselineValue: baselineValue(for: goal),
                            format: { formattedValue($0) }
                        )
                    } else {
                        Text(AppLocalization.string("Set a goal to see progress."))
                            .font(AppTypography.micro)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text(AppLocalization.string("—"))
                        .font(AppTypography.metricValue)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(AppLocalization.string("No data yet"))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 8)

            if !samples.isEmpty {
                CustomMiniSparklineChart(
                    samples: samples,
                    favorsDecrease: definition.favorsDecrease,
                    goal: goal
                )
                .frame(width: 90, height: 44)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 90, height: 44)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: cornerRadius,
                tint: Color.appAccent.opacity(0.10)
            )
        )
    }

    private func formattedValue(_ value: Double) -> String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(definition.unitLabel)"
    }

    private func baselineValue(for goal: MetricGoal) -> Double {
        if let sv = goal.startValue { return sv }
        guard !samples.isEmpty else { return latest?.value ?? goal.targetValue }
        let sorted = samples.sorted { $0.date < $1.date }
        if let baseline = sorted.last(where: { $0.date <= goal.createdDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? (latest?.value ?? goal.targetValue)
    }
}

struct PressableTileStyle: ButtonStyle {
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
        configuration.label
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
            .opacity(configuration.isPressed && shouldAnimate ? 0.9 : 1)
    }
}

struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
