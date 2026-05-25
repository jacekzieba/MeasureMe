import SwiftUI
import Charts
import SwiftData
import Accessibility

// MARK: - MetricChartTile

struct MetricChartTile: View {
    private let measurementsTheme = FeatureTheme.measurements
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: MetricKind
    let unitsSystem: String
    @AppSetting(\.profile.userName) private var userName: String = ""

    @Query private var samples: [MetricSample]
    @Query private var goals: [MetricGoal]

    @State private var shortInsight: String?
    @State private var isLoadingInsight = false
    // Chart scrubbing removed from tile - available only in MetricDetailView

    init(kind: MetricKind, unitsSystem: String) {
        self.kind = kind
        self.unitsSystem = unitsSystem

        let kindValue = kind.rawValue
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? .distantPast
        _samples = Query(
            filter: #Predicate<MetricSample> {
                $0.kindRaw == kindValue && $0.date >= startDate
            },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
        _goals = Query(
            filter: #Predicate<MetricGoal> {
                $0.kindRaw == kindValue
            }
        )
    }

    // Current goal for this metric
    private var currentGoal: MetricGoal? {
        goals.first
    }

    // MARK: - Data

    private var startDate30: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? .distantPast
    }

    private var recentSamples: [MetricSample] {
        samples.filter { $0.date >= startDate30 }
    }

    private var latest: MetricSample? {
        recentSamples.last
    }

    private var trendInfo: (delta: Double, relativeText: String, outcome: MetricKind.TrendOutcome)? {
        guard recentSamples.count >= 2,
              let lastSample = recentSamples.last else { return nil }

        let targetDate = Calendar.current.date(byAdding: .day, value: -30, to: lastSample.date) ?? startDate30
        let baselineSample = recentSamples.min {
            abs($0.date.timeIntervalSince(targetDate)) < abs($1.date.timeIntervalSince(targetDate))
        }

        guard let baselineSample,
              baselineSample.persistentModelID != lastSample.persistentModelID else { return nil }

        let last = displayValue(lastSample.value)
        let baseline = displayValue(baselineSample.value)
        let delta = last - baseline
        let outcome = kind.trendOutcome(from: baselineSample.value, to: lastSample.value, goal: currentGoal)
        return (delta, AppLocalization.string("trend.relative.30d"), outcome)
    }

    // MARK: - UI

    private var appleIntelligenceAvailable: Bool {
        AppleIntelligenceSupport.isAvailable()
    }

    private var canUseAppleIntelligence: Bool {
        premiumStore.isPremium && appleIntelligenceAvailable
    }

    var body: some View {
        if recentSamples.isEmpty {
            // MARK: - Compact empty tile (no data)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            kind.iconView(size: 20, tint: measurementsTheme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .layoutPriority(1)

                                Text(AppLocalization.string("measurements.metric.nodata"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                Haptics.light()
                                router.presentedSheet = .addSample(kind: kind)
                            } label: {
                                Text(AppLocalization.string("Add"))
                            }
                            .buttonStyle(LiquidCapsuleButtonStyle())
                            .frame(minHeight: 44)

                            Spacer(minLength: 0)

                            NavigationLink {
                                MetricDetailView(kind: kind)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.title3)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                kind.iconView(size: 20, tint: measurementsTheme.accent)

                                Text(kind.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .layoutPriority(1)
                            }

                            Text(AppLocalization.string("measurements.metric.nodata"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textTertiary)
                        }

                        Spacer(minLength: 8)

                        Button {
                            Haptics.light()
                            router.presentedSheet = .addSample(kind: kind)
                        } label: {
                            Text(AppLocalization.string("Add"))
                        }
                        .buttonStyle(LiquidCapsuleButtonStyle())

                        NavigationLink {
                            MetricDetailView(kind: kind)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundStyle(AppColorRoles.textTertiary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                    }
                }
            }
            .padding(14)
            .background(
                AppGlassBackground(
                    depth: .elevated,
                    cornerRadius: 16,
                    tint: measurementsTheme.softTint
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.string("accessibility.metric.summary.nodata", kind.title))
            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
        } else {
            // MARK: - Full tile with chart
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        kind.iconView(size: 24, tint: metricAccent)

                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .layoutPriority(1)

                        Spacer(minLength: 8)

                        if let goalProgress {
                            CompactGoalProgressPill(
                                progress: goalProgress.progress,
                                percentage: goalProgress.percentage,
                                isAchieved: goalProgress.isAchieved,
                                accent: metricAccent
                            )
                        }

                        NavigationLink {
                            MetricDetailView(kind: kind)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(AppTypography.iconMedium)
                                .foregroundStyle(AppColorRoles.textTertiary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                    }

                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let latest {
                                MetricValueText(valueString(metricValue: latest.value))

                                if let trendInfo {
                                    HStack(spacing: 5) {
                                        Image(systemName: trendInfo.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            .font(AppTypography.microEmphasis)
                                        Text(kind.formattedDisplayValue(abs(trendInfo.delta), unitsSystem: unitsSystem))
                                            .monospacedDigit()
                                        Text(AppLocalization.string("trend.vs.relative", trendInfo.relativeText))
                                            .foregroundStyle(AppColorRoles.textTertiary)
                                    }
                                    .font(AppTypography.captionEmphasis)
                                    .foregroundStyle(trendColor(for: trendInfo.outcome))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                }
                            } else {
                                Text(AppLocalization.string("—"))
                                    .font(AppTypography.dataCompact)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                        }
                        .frame(width: 126, alignment: .leading)

                        MetricTileSparklineChart(
                            samples: recentSamples,
                            goal: currentGoal,
                            accent: metricAccent,
                            yDomain: yDomain,
                            xDomain: xDomain,
                            displayValue: displayValue,
                            yAxisLabel: { kind.formattedDisplayValue($0, unitsSystem: unitsSystem, includeUnit: false) }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                        .accessibilityChartDescriptor(MetricChartAXDescriptor(descriptor: chartDescriptor))
                    }
                }
                .padding(16)

                if let footerInsightText {
                    Divider()
                        .overlay(AppColorRoles.borderSubtle.opacity(0.7))

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(metricAccent)
                            .padding(.top, 2)

                        Text(footerInsightText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("insight.card.text.compact")

                        if premiumStore.isPremium && !appleIntelligenceAvailable {
                            Spacer(minLength: 4)
                            NavigationLink {
                                FAQView()
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(
                AppGlassBackground(
                    depth: .elevated,
                    cornerRadius: 22,
                    tint: measurementsTheme.softTint
                )
            )
            .task(id: insightInput) {
                await loadInsightIfNeeded()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
        }
    }

    // MARK: - Helpers

    private func displayValue(_ metricValue: Double) -> Double {
        kind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    private func valueString(metricValue: Double) -> String {
        kind.formattedMetricValue(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    private var metricAccent: Color {
        switch kind {
        case .weight, .leanBodyMass:
            return AppColorRoles.accentPrimary
        case .bodyFat:
            return Color.appRose
        case .waist, .hips:
            return Color.appTeal
        case .height:
            return Color.appCyan
        case .neck, .shoulders, .bust, .chest:
            return Color.appIndigo
        case .leftBicep, .rightBicep, .leftForearm, .rightForearm:
            return Color.appEmerald
        case .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return Color.appAmber
        }
    }

    private var goalProgress: MetricGoalProgressSnapshot? {
        guard let goal = currentGoal, let latest else { return nil }
        let baseline = baselineValue(for: goal)
        return MetricGoalProgressSnapshot(goal: goal, currentValue: latest.value, baselineValue: baseline)
    }

    private var footerInsightText: String? {
        if canUseAppleIntelligence {
            if isLoadingInsight { return AppLocalization.aiString("Generating insight...") }
            if let shortInsight { return shortInsight }
        }
        if premiumStore.isPremium && !appleIntelligenceAvailable {
            return AppLocalization.aiString("AI Insights aren't available right now.")
        }
        return localInsightText
    }

    private var localInsightText: String? {
        if let trendInfo {
            let deltaText = kind.formattedDisplayValue(abs(trendInfo.delta), unitsSystem: unitsSystem)
            let direction = trendInfo.delta >= 0
                ? AppLocalization.aiString("up")
                : AppLocalization.aiString("down")
            if let progress = goalProgress {
                if progress.isAchieved {
                    return AppLocalization.aiString("Goal reached. Last 30 days are %@ %@, so keep checking consistency before changing the target.", direction, deltaText)
                }
                return AppLocalization.aiString("%d%% toward goal. Last 30 days are %@ %@, which helps judge whether the current pace is realistic.", progress.percentage, direction, deltaText)
            }
            switch trendInfo.outcome {
            case .positive:
                return AppLocalization.aiString("Last 30 days moved %@ %@ in a favorable direction. Keep the same measurement rhythm to confirm the trend.", direction, deltaText)
            case .negative:
                return AppLocalization.aiString("Last 30 days moved %@ %@ against the preferred direction. Check whether training, recovery, or intake changed recently.", direction, deltaText)
            case .neutral:
                return AppLocalization.aiString("This metric is broadly steady over 30 days. More consistent check-ins will make subtle changes easier to trust.")
            }
        }
        return AppLocalization.aiString("Add more check-ins to build a reliable 30-day trend for this metric.")
    }

    private var yDomain: ClosedRange<Double> {
        var values = recentSamples.map { displayValue($0.value) }

        // Add goal value to the range if a goal exists
        if let goal = currentGoal {
            values.append(displayValue(goal.targetValue))
        }

        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 1)
        let padding = span * 0.15
        return (minV - padding)...(maxV + padding)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = recentSamples.first?.date,
              let last = recentSamples.last?.date else {
            let start = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
            return start...AppClock.now
        }
        if first == last {
            let start = Calendar.current.date(byAdding: .hour, value: -12, to: first) ?? first
            let end = Calendar.current.date(byAdding: .hour, value: 12, to: first) ?? first
            return start...end
        }
        return first...last
    }

    private func baselineValue(for goal: MetricGoal) -> Double {
        if let startValue = goal.startValue { return startValue }
        let sorted = recentSamples.sorted { $0.date < $1.date }
        let anchorDate = goal.startDate ?? goal.createdDate
        if let baseline = sorted.last(where: { $0.date <= anchorDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? latest?.value ?? goal.targetValue
    }

    private func trendColor(for outcome: MetricKind.TrendOutcome) -> Color {
        switch outcome {
        case .positive:
            return AppColorRoles.chartPositive
        case .negative:
            return AppColorRoles.chartNegative
        case .neutral:
            return AppColorRoles.textTertiary
        }
    }

    private func goalLabelPosition(for goalValue: Double) -> AnnotationPosition {
        let minV = yDomain.lowerBound
        let maxV = yDomain.upperBound
        let span = max(maxV - minV, 0.0001)
        let rel = (goalValue - minV) / span
        if rel > 0.85 { return .bottom }
        if rel < 0.15 { return .top }
        return .top
    }

    private var insightInput: MetricInsightInput? {
        guard canUseAppleIntelligence, let latest else { return nil }
        return MetricInsightInput(
            userName: userName.isEmpty ? nil : userName,
            metricTitle: kind.englishTitle,
            measurementContext: kind.insightMeasurementContext,
            latestValueText: valueString(metricValue: latest.value),
            timeframeLabel: "Last 30 days",
            sampleCount: recentSamples.count,
            delta7DaysText: recentSamples.deltaText(days: 7, kind: kind, unitsSystem: unitsSystem),
            delta14DaysText: nil,
            delta30DaysText: recentSamples.deltaText(days: 30, kind: kind, unitsSystem: unitsSystem),
            delta90DaysText: nil,
            goalStatusText: goalStatusText,
            goalDirectionText: currentGoal?.direction.rawValue,
            defaultFavorableDirectionText: kind.defaultFavorableDirectionWhenNoGoal.rawValue
        )
    }

    private var goalStatusText: String? {
        guard let goal = currentGoal, let latest else { return nil }
        if goal.isAchieved(currentValue: latest.value) {
            return "Goal reached"
        }
        let remaining = displayValue(abs(goal.remainingToGoal(currentValue: latest.value)))
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return "\(remaining) \(unit) away from goal"
    }

    private var accessibilitySummary: String {
        if let latest {
            let value = valueString(metricValue: latest.value)
            if let trendInfo {
                let deltaText = kind.formattedDisplayValue(abs(trendInfo.delta), unitsSystem: unitsSystem)
                return AppLocalization.string("accessibility.metric.summary.trend", kind.title, value, deltaText, trendInfo.relativeText)
            }
            return AppLocalization.string("accessibility.metric.summary.value", kind.title, value)
        }
        return AppLocalization.string("accessibility.metric.summary.nodata", kind.title)
    }

    @MainActor
    private func loadInsightIfNeeded() async {
        guard let input = insightInput else {
            shortInsight = nil
            isLoadingInsight = false
            return
        }

        isLoadingInsight = true
        let generated = await MetricInsightService.shared.generateInsight(for: input)
        shortInsight = generated?.shortText
        isLoadingInsight = false
    }

    private var chartDescriptor: AXChartDescriptor {
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let points: [(String, Double)] = recentSamples.map { sample in
            let label = dateFormatter.string(from: sample.date)
            return (label, displayValue(sample.value))
        }

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: AppLocalization.string("Date"),
            categoryOrder: points.map(\.0)
        )

        let values = points.map(\.1)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1

        let yAxis = AXNumericDataAxisDescriptor(
            title: "\(kind.title) (\(unit))",
            range: minValue...maxValue,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                kind.formattedDisplayValue(value, unitsSystem: unitsSystem)
            }
        )

        let series = AXDataSeriesDescriptor(
            name: kind.title,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.0, y: $0.1) }
        )

        let summary: String
        if let first = values.first, let last = values.last {
            let trend = last == first
                ? AppLocalization.string("trend.steady")
                : (last > first ? AppLocalization.string("trend.up") : AppLocalization.string("trend.down"))
            summary = AppLocalization.string(
                "chart.summary.metric",
                kind.title,
                AppLocalization.string("Last 30 days").lowercased(),
                kind.formattedDisplayValue(first, unitsSystem: unitsSystem, includeUnit: false),
                kind.formattedDisplayValue(last, unitsSystem: unitsSystem, includeUnit: false),
                trend
            )
        } else {
            summary = AppLocalization.string("chart.summary.empty", kind.title)
        }

        return AXChartDescriptor(
            title: AppLocalization.string("chart.title.metric", kind.title),
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
