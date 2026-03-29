// ABSIDetailView.swift
//
// **ABSIDetailView**
// Szczegółowy widok dla A Body Shape Index (ABSI) - wskaźnika ryzyka zdrowotnego
// związanego z rozkładem tkanki tłuszczowej niezależnie od wagi.
//
import SwiftUI

struct ABSIDetailView: View {
    let result: HealthMetricsCalculator.ABSIResult
    
    var body: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string("Body Shape Risk"), theme: .health) {
            HealthInsightHeroCard(accent: Color(hex: result.category.color)) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocalization.string("Body Shape Risk"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(String(format: "%.3f", result.absi))
                        .font(AppTypography.displayLarge)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string(result.category.rawValue))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(Color.bestAccessibleTextColor(onHex: result.category.color))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: result.category.color), in: RoundedRectangle(cornerRadius: 8))

                    Text(AppLocalization.string(result.category.description))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .padding(.top, 4)
                }
            }

            HealthInsightCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("What is Body Shape Risk?"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string("A Body Shape Index (ABSI) measures the health risk associated with your abdominal fat distribution, independent of your total body weight. It focuses on health outcomes rather than appearance."))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppLocalization.string("Higher ABSI values indicate more abdominal fat relative to your BMI and height, which is associated with increased cardiovascular and metabolic health risks."))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }

            WhyItMattersCard(items: [
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Central fat focus"),
                    description: AppLocalization.string("ABSI highlights abdominal fat, which is linked to cardiometabolic risk.")
                ),
                WhyItMattersItem(
                    icon: "waveform.path.ecg",
                    title: AppLocalization.string("Beyond weight"),
                    description: AppLocalization.string("It adds context beyond scale weight or BMI alone.")
                ),
                WhyItMattersItem(
                    icon: "target",
                    title: AppLocalization.string("Guides action"),
                    description: AppLocalization.string("Waist changes can shift risk category over time.")
                )
            ])

            HealthInsightCard(tint: Color(hex: result.category.color).opacity(0.10)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("Risk Categories"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    VStack(spacing: 8) {
                        ForEach(absiRanges, id: \.title) { range in
                            HStack {
                                Circle()
                                    .fill(Color(hex: range.color))
                                    .frame(width: 12, height: 12)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocalization.string(range.title))
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(AppColorRoles.textPrimary)

                                    Text(range.range)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            HealthInsightNoteCard(accent: AppColorRoles.accentPrimary) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(AppColorRoles.accentPrimary)

                        Text(AppLocalization.string("Health Note"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }

                    Text(AppLocalization.string("ABSI is a research-based indicator and should be considered alongside other health metrics. It is not a medical diagnosis. Consult with healthcare professionals for personalized health assessments and recommendations."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var absiRanges: [(title: String, range: String, color: String)] {
        switch result.gender {
        case .male:
            return [
                ("Low risk", "< 0.075", AppColorRoles.stateSuccessHex),
                ("Moderate risk", "0.075-0.085", "#FCA311"),
                ("High risk", "> 0.085", "#EF4444")
            ]
        case .female:
            return [
                ("Low risk", "< 0.070", AppColorRoles.stateSuccessHex),
                ("Moderate risk", "0.070-0.080", "#FCA311"),
                ("High risk", "> 0.080", "#EF4444")
            ]
        case .notSpecified:
            return [
                ("Low risk", "< 0.075", AppColorRoles.stateSuccessHex),
                ("Moderate risk", "0.075-0.085", "#FCA311"),
                ("High risk", "> 0.085", "#EF4444")
            ]
        }
    }
}

#Preview {
    NavigationStack {
        ABSIDetailView(
            result: HealthMetricsCalculator.ABSIResult(
                absi: 0.078,
                category: .moderate,
                gender: .male
            )
        )
    }
}
