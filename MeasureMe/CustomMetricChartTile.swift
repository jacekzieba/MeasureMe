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
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: definition.sfSymbolName)
                        .font(.body)
                        .foregroundStyle(theme.accent)

                    Text(definition.name)
                        .font(AppTypography.bodyEmphasis)
                }

                Spacer()

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

            // Value + trend
            if let latest {
                Text(String(format: "%.1f %@", latest.value, definition.unitLabel))
                    .font(AppTypography.dataCompact)
                    .monospacedDigit()
                    .foregroundStyle(AppColorRoles.textPrimary)

                if let trendInfo {
                    HStack(spacing: 6) {
                        Image(systemName: trendInfo.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%.1f %@", abs(trendInfo.delta), definition.unitLabel))
                            .monospacedDigit()
                        Text(AppLocalization.string("trend.relative.30d"))
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        trendInfo.outcome == .positive
                        ? AppColorRoles.chartPositive
                        : (trendInfo.outcome == .negative ? AppColorRoles.chartNegative : AppColorRoles.textTertiary)
                    )
                }

                // Goal info
                if let goal = currentGoal {
                    let isAchieved = goal.isAchieved(currentValue: latest.value)
                    let remaining = abs(goal.remainingToGoal(currentValue: latest.value))

                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(AppTypography.micro)
                        Text(isAchieved
                             ? AppLocalization.string("Goal reached")
                             : AppLocalization.string("goal.remaining", remaining, definition.unitLabel))
                            .monospacedDigit()
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(isAchieved ? AppColorRoles.stateSuccess : theme.accent)
                }
            }

            // Chart
            Chart {
                ForEach(samples) { s in
                    AreaMark(
                        x: .value("Date", s.date),
                        yStart: .value("Baseline", yDomain.lowerBound),
                        yEnd: .value("Value", s.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                theme.accent.opacity(0.28),
                                theme.accent.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                ForEach(samples) { s in
                    LineMark(
                        x: .value("Date", s.date),
                        y: .value("Value", s.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let goal = currentGoal {
                    RuleMark(y: .value("Goal", goal.targetValue))
                        .foregroundStyle(theme.accent.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    // MARK: - Helpers

    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.value)
        guard let minVal = values.min(), let maxVal = values.max() else {
            return 0...1
        }
        let padding = max((maxVal - minVal) * 0.15, 0.5)
        return (minVal - padding)...(maxVal + padding)
    }
}
