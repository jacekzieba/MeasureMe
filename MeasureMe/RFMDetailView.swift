// RFMDetailView.swift
//
// **RFMDetailView**
// Szczegółowy widok dla Relative Fat Mass (RFM) - szacunkowego procentu tkanki tłuszczowej.
//
import SwiftUI

struct RFMDetailView: View {
    let result: HealthMetricsCalculator.RFMResult
    
    var body: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string("Relative Fat Mass"), theme: .health) {
            HealthInsightHeroCard(accent: Color(hex: result.category.color)) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocalization.string("Relative Fat Mass"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", result.rfm))
                            .font(AppTypography.displayLarge)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(AppLocalization.string("%"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

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
                    Text(AppLocalization.string("What is RFM?"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string("Relative Fat Mass (RFM) is an estimate of total body fat percentage based on your height and waist circumference. It provides a simple way to assess body composition without specialized equipment."))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WhyItMattersCard(items: [
                WhyItMattersItem(
                    icon: "figure.walk",
                    title: AppLocalization.string("Body composition"),
                    description: AppLocalization.string("RFM gives a quick read on fat percentage without special equipment.")
                ),
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Metabolic health"),
                    description: AppLocalization.string("Higher fat levels can increase metabolic strain over time.")
                ),
                WhyItMattersItem(
                    icon: "target",
                    title: AppLocalization.string("Tracking change"),
                    description: AppLocalization.string("Waist updates help you see meaningful shifts in composition.")
                )
            ])

            HealthInsightCard(tint: Color(hex: result.category.color).opacity(0.10)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("Reference Ranges"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    VStack(spacing: 8) {
                        ForEach(rfmRanges, id: \.title) { range in
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

            HealthInsightNoteCard(accent: Color(hex: "#3B82F6")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color(hex: "#3B82F6"))

                        Text(AppLocalization.string("Important"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }

                    Text(AppLocalization.string("RFM is an estimation tool and may not be accurate for athletes, pregnant women, or people with certain medical conditions. For the most accurate body composition analysis, consult with a healthcare professional."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var rfmRanges: [(title: String, range: String, color: String)] {
        switch result.gender {
        case .male:
            return [
                ("Normal fat level", "< 20%", "#22C55E"),
                ("Increased fat level", "20-25%", "#FCA311"),
                ("High fat level", "> 25%", "#EF4444")
            ]
        case .female:
            return [
                ("Normal fat level", "< 30%", "#22C55E"),
                ("Increased fat level", "30-35%", "#FCA311"),
                ("High fat level", "> 35%", "#EF4444")
            ]
        case .notSpecified:
            return [
                ("Normal fat level", "< 20%", "#22C55E"),
                ("Increased fat level", "20-25%", "#FCA311"),
                ("High fat level", "> 25%", "#EF4444")
            ]
        }
    }
}

#Preview {
    NavigationStack {
        RFMDetailView(
            result: HealthMetricsCalculator.RFMResult(
                rfm: 22.5,
                category: .increased,
                gender: .male
            )
        )
    }
}
