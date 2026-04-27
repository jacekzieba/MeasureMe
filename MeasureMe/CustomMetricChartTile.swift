import SwiftUI
import Charts
import SwiftData

struct CustomMetricChartTile: View {
    let definition: CustomMetricDefinition
    let theme: FeatureTheme

    @Query private var samples: [MetricSample]
    @Query private var goals: [MetricGoal]

    init(definition: CustomMetricDefinition, theme: FeatureTheme) {
        self.definition = definition
        self.theme = theme

        let identifier = definition.identifier
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? .distantPast
        _samples = Query(
            filter: #Predicate<MetricSample> {
                $0.kindRaw == identifier && $0.date >= startDate
            },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
        _goals = Query(
            filter: #Predicate<MetricGoal> {
                $0.kindRaw == identifier
            }
        )
    }

    private var currentGoal: MetricGoal? { goals.first }
    private var latest: MetricSample? { samples.last }

    private var goalProgress: MetricGoalProgressSnapshot? {
        guard let goal = currentGoal, let latest else { return nil }
        return MetricGoalProgressSnapshot(
            goal: goal,
            currentValue: latest.value,
            baselineValue: baselineValue(for: goal)
        )
    }

    private var trendInfo: (delta: Double, outcome: MetricKind.TrendOutcome)? {
        guard samples.count >= 2,
              let last = samples.last,
              let first = samples.first,
              first.persistentModelID != last.persistentModelID else { return nil }
        let delta = last.value - first.value
        let outcome: MetricKind.TrendOutcome
        if delta == 0 {
            outcome = .neutral
        } else if definition.favorsDecrease {
            outcome = delta < 0 ? .positive : .negative
        } else {
            outcome = delta > 0 ? .positive : .negative
        }
        return (delta, outcome)
    }

    var body: some View {
        if samples.isEmpty {
            emptyTile
        } else {
            fullTile
        }
    }

    // MARK: - Empty Tile

    private var emptyTile: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: definition.sfSymbolName)
                        .font(.body)
                        .foregroundStyle(theme.accent)

                    Text(definition.name)
                        .font(AppTypography.bodyEmphasis)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                Text(AppLocalization.string("measurements.metric.nodata"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }

            Spacer(minLength: 8)

            NavigationLink {
                CustomMetricDetailView(definition: definition)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(AppColorRoles.textTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            AppGlassBackground(
                depth: .elevated,
                cornerRadius: 16,
                tint: theme.softTint
            )
        )
    }

    // MARK: - Full Tile

    private var fullTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: definition.sfSymbolName)
                        .font(AppTypography.iconLarge)
                        .foregroundStyle(theme.accent)

                    Text(definition.name)
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
                            accent: theme.accent
                        )
                    }

                    NavigationLink {
                        CustomMetricDetailView(definition: definition)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(AppTypography.iconMedium)
                            .foregroundStyle(AppColorRoles.textTertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let latest {
                            MetricValueText(String(format: "%.1f %@", latest.value, definition.unitLabel))

                            if let trendInfo {
                                HStack(spacing: 5) {
                                    Image(systemName: trendInfo.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(AppTypography.microEmphasis)
                                    Text(String(format: "%.1f %@", abs(trendInfo.delta), definition.unitLabel))
                                        .monospacedDigit()
                                    Text(AppLocalization.string("trend.relative.30d"))
                                        .foregroundStyle(AppColorRoles.textTertiary)
                                }
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(trendColor(for: trendInfo.outcome))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            }
                        }
                    }
                    .frame(width: 126, alignment: .leading)

                    MetricTileSparklineChart(
                        samples: samples,
                        goal: currentGoal,
                        accent: theme.accent,
                        yDomain: yDomain,
                        xDomain: xDomain,
                        displayValue: { $0 },
                        yAxisLabel: { String(format: "%.1f", $0) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                }
            }
            .padding(16)

            Divider()
                .overlay(AppColorRoles.borderSubtle.opacity(0.7))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(theme.accent)
                    .padding(.top, 2)

                Text(footerInsightText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            AppGlassBackground(
                depth: .elevated,
                cornerRadius: 22,
                tint: theme.softTint
            )
        )
    }

    // MARK: - Helpers

    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.value)
        guard let minVal = values.min(), let maxVal = values.max() else {
            return 0...1
        }
        let padding = max((maxVal - minVal) * 0.15, 0.5)
        return (minVal - padding)...(maxVal + padding)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = samples.first?.date,
              let last = samples.last?.date else {
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

    private var footerInsightText: String {
        guard let trendInfo else {
            return AppLocalization.aiString("Add more check-ins to build a reliable 30-day trend for this metric.")
        }
        let deltaText = String(format: "%.1f %@", abs(trendInfo.delta), definition.unitLabel)
        let direction = trendInfo.delta >= 0 ? AppLocalization.aiString("up") : AppLocalization.aiString("down")
        if let goalProgress {
            if goalProgress.isAchieved {
                return AppLocalization.aiString("Goal reached. Last 30 days are %@ %@, so keep checking consistency before changing the target.", direction, deltaText)
            }
            return AppLocalization.aiString("%d%% toward goal. Last 30 days are %@ %@, which helps judge whether the current pace is realistic.", goalProgress.percentage, direction, deltaText)
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

    private func baselineValue(for goal: MetricGoal) -> Double {
        if let startValue = goal.startValue { return startValue }
        let sorted = samples.sorted { $0.date < $1.date }
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
}
