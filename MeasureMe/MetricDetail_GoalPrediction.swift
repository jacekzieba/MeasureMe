import SwiftUI
import SwiftData

// MARK: - Goal Prediction Section

extension MetricDetailView {

    @ViewBuilder
    var goalPredictionSection: some View {
        if currentGoal != nil {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(AppLocalization.string("metric.goal.prediction.title"))
                if premiumStore.isPremium {
                    if let result = goalPredictionResult, let text = goalForecastText {
                        AppGlassCard(
                            depth: .elevated,
                            cornerRadius: 20,
                            tint: measurementsTheme.softTint,
                            contentPadding: 16
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                // Header row z chevronem (expand tylko dla wagi)
                                HStack(spacing: 8) {
                                    Image(systemName: predictionIcon(for: result))
                                        .foregroundStyle(predictionColor(for: result))
                                    Text(AppLocalization.string("metric.goal.prediction.title"))
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(AppColorRoles.textPrimary)

                                    Spacer()

                                    if kind == .weight {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                isPredictionExpanded.toggle()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(isPredictionExpanded
                                                     ? AppLocalization.string("prediction.collapse")
                                                     : AppLocalization.string("prediction.expand"))
                                                    .font(AppTypography.caption)
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .rotationEffect(.degrees(isPredictionExpanded ? -180 : 0))
                                            }
                                            .foregroundStyle(AppColorRoles.textSecondary)
                                        }
                                        .buttonStyle(.borderless)

                                        Button {
                                            let current = weightPredictionRates?.commitmentRate ?? 0
                                            commitmentInput = current > 0
                                                ? String(format: "%.2f", displayValue(current))
                                                : ""
                                            isEditingCommitment = true
                                        } label: {
                                            Image(systemName: "gearshape")
                                                .font(.system(size: 16))
                                                .foregroundStyle(AppColorRoles.textSecondary)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }

                                Text(text)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)

                                // Expanded content (weight only)
                                if kind == .weight, let rates = weightPredictionRates {
                                    weightPredictionExpandedContent(rates: rates)
                                        .frame(maxHeight: isPredictionExpanded ? .none : 0, alignment: .top)
                                        .clipped()
                                        .opacity(isPredictionExpanded ? 1 : 0)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    PremiumLockedCard(
                        title: AppLocalization.string("metric.goal.premium.locked.title"),
                        message: AppLocalization.string("metric.goal.premium.locked.message")
                    ) {
                        premiumStore.presentPaywall(reason: .feature("Goal Prediction"))
                    }
                }
            }
            .alert(AppLocalization.string("prediction.commitment.edit_title"), isPresented: $isEditingCommitment) {
                TextField("0.50", text: $commitmentInput)
                    .keyboardType(.decimalPad)
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Save")) {
                    if let value = Double(commitmentInput.replacingOccurrences(of: ",", with: ".")),
                       value > 0 {
                        updateCommitmentRate(value)
                    }
                }
            } message: {
                let unit = kind.unitSymbol(unitsSystem: unitsSystem)
                Text(AppLocalization.string("prediction.commitment.edit_message", unit))
            }
        }
    }
}
