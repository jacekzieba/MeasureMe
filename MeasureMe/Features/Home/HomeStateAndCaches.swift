import SwiftUI
import SwiftData

extension HomeView {
    static func deltaText(
        samples: [MetricSample],
        kind: MetricKind,
        unitsSystem: String,
        days: Int,
        now: Date = Date()
    ) -> String? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
        let kindSamples = samples.filter { $0.date >= start }
        guard let newest = kindSamples.first,
              let oldest = kindSamples.last,
              newest.persistentModelID != oldest.persistentModelID else {
            return nil
        }
        let newestValue = kind.valueForDisplay(fromMetric: newest.value, unitsSystem: unitsSystem)
        let oldestValue = kind.valueForDisplay(fromMetric: oldest.value, unitsSystem: unitsSystem)
        let delta = newestValue - oldestValue
        return String(format: "%+.1f %@", delta, kind.unitSymbol(unitsSystem: unitsSystem))
    }

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
        let shown = kind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%.1f %@", shown, unit)
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

struct PressableTileStyle: ButtonStyle {
    @AppSetting("animationsEnabled") private var animationsEnabled: Bool = true
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
