import SwiftUI
import Charts

/// Krok 0 onboardingu — wybór celu i podgląd trendów.
struct OnboardingWelcomeStep: View {
    @Binding var selectedGoals: Set<OnboardingView.WelcomeGoal>
    let onGoalToggled: (OnboardingView.WelcomeGoal) -> Void

    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                onboardingSlideHeader(title: OnboardingView.Step.welcome.title, subtitle: OnboardingView.Step.welcome.subtitle)
                Spacer(minLength: 0)
                Image("BrandMark")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }

            goalSelector
            examplePreview
        }
    }

    // MARK: - Goal selector

    private var goalSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.systemString("What's your goal?"))
                .font(AppTypography.headlineEmphasis)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .foregroundStyle(Color.appWhite)

            VStack(spacing: 5) {
                ForEach(OnboardingView.WelcomeGoal.allCases, id: \.self) { goal in
                    goalOptionRow(goal)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func goalOptionRow(_ goal: OnboardingView.WelcomeGoal) -> some View {
        let isSelected = selectedGoals.contains(goal)
        return Button {
            onGoalToggled(goal)
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Text(goal.title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.86))

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.appAccent : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 7)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.appAccent.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
        .accessibilityLabel(goal.title)
        .accessibilityValue(isSelected ? AppLocalization.systemString("Selected") : AppLocalization.systemString("Not selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Example preview

    private var examplePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 20, height: 20)
                    .background(Color.appAccent.opacity(0.18))
                    .clipShape(Circle())

                Text(AppLocalization.systemString("onboarding.example.label"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.96))
            }

            trendPreview
            insightPreview
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appAccent.opacity(0.26), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityHint(AppLocalization.systemString("Sample trend card to preview how progress insights will look."))
    }

    private var insightPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetricInsightCard(
                text: AppLocalization.systemString("You're trending down steadily. Keep 3 strength sessions and 8k+ steps this week."),
                compact: true,
                isLoading: false
            )
        }
    }

    // MARK: - Trend chart

    private struct TrendPoint: Identifiable {
        let id: Int
        let week: Int
        let value: Double
    }

    private var trendPoints: [TrendPoint] {
        [
            TrendPoint(id: 0, week: 1, value: 82.4),
            TrendPoint(id: 1, week: 2, value: 82.3),
            TrendPoint(id: 2, week: 3, value: 82.0),
            TrendPoint(id: 3, week: 4, value: 82.1),
            TrendPoint(id: 4, week: 5, value: 81.8),
            TrendPoint(id: 5, week: 6, value: 81.6),
            TrendPoint(id: 6, week: 7, value: 81.7),
            TrendPoint(id: 7, week: 8, value: 81.3),
            TrendPoint(id: 8, week: 9, value: 81.1),
            TrendPoint(id: 9, week: 10, value: 81.0),
            TrendPoint(id: 10, week: 11, value: 80.9),
            TrendPoint(id: 11, week: 12, value: 80.6),
            TrendPoint(id: 12, week: 13, value: 80.7),
            TrendPoint(id: 13, week: 14, value: 80.4),
            TrendPoint(id: 14, week: 15, value: 80.2),
            TrendPoint(id: 15, week: 16, value: 80.1),
            TrendPoint(id: 16, week: 17, value: 79.9),
            TrendPoint(id: 17, week: 18, value: 79.7)
        ]
    }

    private var goalValue: Double { 79.0 }

    private var xAxisValues: [Int] { [1, 4, 7, 10, 13, 16, 18] }

    private var lastTrendPoint: TrendPoint? { trendPoints.last }

    private var weekDomain: ClosedRange<Int> {
        guard let firstWeek = trendPoints.first?.week,
              let lastWeek = trendPoints.last?.week,
              firstWeek < lastWeek else {
            return 1...2
        }
        return firstWeek...lastWeek
    }

    private var trendDomain: ClosedRange<Double> {
        let values = (trendPoints.map(\.value) + [goalValue]).filter(\.isFinite)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        let padding = max((maxValue - minValue) * 0.18, 0.5)
        let lower = minValue - padding
        let upper = maxValue + padding
        guard lower.isFinite, upper.isFinite, lower < upper else {
            return 0...1
        }
        return lower...upper
    }

    private var trendChartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 150 : 94
    }

    private var trendPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(AppLocalization.systemString("onboarding.trend.delta"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color(hex: "#22C55E"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#22C55E").opacity(0.16))
                    .clipShape(Capsule(style: .continuous))

                Text(AppLocalization.systemString("onboarding.goal.badge", goalValue))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color(hex: "#22C55E"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#22C55E").opacity(0.16))
                    .clipShape(Capsule(style: .continuous))
            }

            Chart {
                RuleMark(y: .value("Goal", goalValue))
                    .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [5, 4]))
                    .foregroundStyle(Color(hex: "#22C55E").opacity(0.9))

                ForEach(trendPoints) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        yStart: .value("Baseline", trendDomain.lowerBound),
                        yEnd: .value("Weight", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.28), Color.appAccent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Weight", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.appAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    if let lastPoint = lastTrendPoint, lastPoint.id == point.id {
                        PointMark(
                            x: .value("Week", point.week),
                            y: .value("Weight", point.value)
                        )
                        .symbolSize(44)
                        .foregroundStyle(Color.appAccent)

                        PointMark(
                            x: .value("Week", point.week),
                            y: .value("Goal", goalValue)
                        )
                        .symbolSize(36)
                        .foregroundStyle(Color(hex: "#22C55E"))
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .padding(.bottom, 8)
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.18))
                    AxisValueLabel {
                        if let week = value.as(Int.self) {
                            Text(AppLocalization.systemString("onboarding.week.label", week))
                                .font(AppTypography.micro)
                                .foregroundStyle(Color.appGray)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 1)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(Color.white.opacity(0.18))
                }
            }
            .chartXScale(domain: weekDomain)
            .chartYScale(domain: trendDomain)
            .frame(height: trendChartHeight)
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
