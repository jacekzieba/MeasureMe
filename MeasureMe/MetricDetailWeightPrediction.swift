import SwiftUI

// MARK: - Weight Prediction Expanded Content

extension MetricDetailView {
    @ViewBuilder
    func weightPredictionExpandedContent(rates: GoalPredictionEngine.WeightPredictionRates) -> some View {
        VStack(spacing: 12) {
            // Trzy boxy z tempami
            HStack(spacing: 8) {
                // Commitment — read-only (edit via gear icon)
                predictionRateBox(
                    label: AppLocalization.string("prediction.commitment"),
                    value: rates.commitmentRate.map { formattedWeeklyRate($0) },
                    color: .appIndigo,
                    isTappable: false
                )

                // Current rate
                predictionRateBox(
                    label: AppLocalization.string("prediction.current_rate"),
                    value: rates.currentRate.map { formattedWeeklyRate($0) },
                    color: AppColorRoles.textSecondary,
                    isTappable: false
                )

                // Overall rate
                predictionRateBox(
                    label: AppLocalization.string("prediction.overall_rate"),
                    value: rates.overallRate.map { formattedWeeklyRate($0) },
                    color: AppColorRoles.textSecondary,
                    isTappable: false
                )
            }

            // Opis
            if let commitment = rates.commitmentRate, commitment > 0 {
                let unit = kind.unitSymbol(unitsSystem: unitsSystem)
                let rateStr = formattedWeeklyRate(commitment)
                Text(AppLocalization.string("prediction.description", rateStr, unit))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Date rows
            VStack(spacing: 6) {
                if let commitDate = rates.projectedDate(forRate: rates.commitmentRate) {
                    predictionDateRow(
                        label: AppLocalization.string("prediction.commitment"),
                        date: commitDate,
                        relativeLabel: rates.relativeLabel(for: commitDate),
                        color: .appIndigo
                    )
                }

                if let currentDate = rates.projectedDate(forRate: rates.currentRate) {
                    predictionDateRow(
                        label: AppLocalization.string("prediction.current_rate"),
                        date: currentDate,
                        relativeLabel: rates.relativeLabel(for: currentDate),
                        color: AppColorRoles.textSecondary
                    )
                }

                if let overallDate = rates.projectedDate(forRate: rates.overallRate) {
                    predictionDateRow(
                        label: AppLocalization.string("prediction.overall_rate"),
                        date: overallDate,
                        relativeLabel: rates.relativeLabel(for: overallDate),
                        color: AppColorRoles.textSecondary
                    )
                }
            }
        }
    }

    @ViewBuilder
    func predictionRateBox(
        label: String,
        value: String?,
        color: Color,
        isTappable: Bool,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = VStack(spacing: 4) {
            Text(label)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(isTappable ? .white.opacity(0.8) : AppColorRoles.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value ?? "—")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(isTappable ? .white : AppColorRoles.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTappable ? color : color.opacity(0.1))
        )

        if isTappable, let action {
            Button(action: action) { content }
        } else {
            content
        }
    }

    @ViewBuilder
    func predictionDateRow(
        label: String,
        date: Date,
        relativeLabel: String,
        color: Color
    ) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 24)

            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)

            Spacer()

            Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .textCase(.uppercase)

            Text(relativeLabel)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(measurementsTheme.accent)
                .textCase(.uppercase)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(color.opacity(0.06))
        )
    }

    func predictionIcon(for result: GoalPredictionResult) -> String {
        switch result {
        case .achieved: return "checkmark.circle.fill"
        case .onTrack: return "chart.line.uptrend.xyaxis"
        case .trendOpposite: return "exclamationmark.triangle.fill"
        case .flatTrend: return "equal.circle.fill"
        case .tooFarOut: return "clock.badge.exclamationmark"
        case .insufficientData: return "questionmark.circle"
        }
    }

    func predictionColor(for result: GoalPredictionResult) -> Color {
        switch result {
        case .achieved, .onTrack: return AppColorRoles.stateSuccess
        case .trendOpposite: return AppColorRoles.stateError
        case .flatTrend, .tooFarOut, .insufficientData: return AppColorRoles.textSecondary
        }
    }
}
