import SwiftUI

// MARK: - Trends Card

extension MetricDetailView {
    var trendPeriods: [TrendPeriod] {
        [
            TrendPeriod(days: 7, labelKey: "trends.period.7d"),
            TrendPeriod(days: 30, labelKey: "trends.period.30d"),
            TrendPeriod(days: 90, labelKey: "trends.period.90d"),
            TrendPeriod(days: nil, labelKey: "trends.period.alltime"),
        ]
    }

    static let trendPositive = Color(hex: "#16A34A")
    static let trendNegative = Color.appDanger

    var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(AppLocalization.string("trends.title", kind.title))
            AppGlassCard(
                depth: .elevated,
                cornerRadius: 20,
                tint: measurementsTheme.softTint,
                contentPadding: 16
            ) {
                HStack(spacing: 8) {
                    ForEach(trendPeriods) { period in
                        trendTile(period: period)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    func trendTile(period: TrendPeriod) -> some View {
        let result = sortedSamplesAscending.trendDelta(
            days: period.days,
            kind: kind,
            unitsSystem: unitsSystem
        )
        let outcome: MetricKind.TrendOutcome = {
            guard let result else { return .neutral }
            return kind.trendOutcome(from: result.oldestValue, to: result.newestValue, goal: currentGoal)
        }()
        let tileColor: Color = {
            switch outcome {
            case .positive: return Self.trendPositive
            case .negative: return Self.trendNegative
            case .neutral: return AppColorRoles.chartNeutral
            }
        }()
        let periodLabel = AppLocalization.string(period.labelKey)

        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(tileColor)
                .overlay(
                    Text(result.map { kind.formattedDisplayValue(abs($0.displayDelta), unitsSystem: unitsSystem, includeUnit: false) } ?? "—")
                        .font(AppTypography.dataDelta)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                )
                .frame(height: 44)

            Text(trendLabel(delta: result?.displayDelta, periodLabel: periodLabel))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    func trendLabel(delta: Double?, periodLabel: String) -> String {
        guard let delta, delta != 0 else {
            return AppLocalization.string("trends.no_change_in", periodLabel)
        }
        if kind.usesGainedLostVerb {
            return delta > 0
                ? AppLocalization.string("trends.gained_in", periodLabel)
                : AppLocalization.string("trends.lost_in", periodLabel)
        } else {
            return delta > 0
                ? AppLocalization.string("trends.increased_in", periodLabel)
                : AppLocalization.string("trends.decreased_in", periodLabel)
        }
    }
}
