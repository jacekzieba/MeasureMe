// ComputedMetricDetailView.swift
//
// **ComputedMetricDetailView**
// Unified detail view for all computed health indicator metrics.
// Replaces BMIDetailView, WHtRDetailView, WHRDetailView,
// ABSIDetailView, BodyFatDetailView, ConicityDetailView.
//
import SwiftUI

// MARK: - Configuration

/// Configuration for a computed metric detail view.
enum ComputedMetricConfig {

    // MARK: - Classic scaffold (ZStack + AppScreenBackground)

    case bmi(result: HealthMetricsCalculator.BMIResult)
    case whtr(result: HealthMetricsCalculator.WHtRResult)
    case whr(result: HealthMetricsCalculator.WHRResult, gender: Gender)

    // MARK: - Insight scaffold (SettingsScrollDetailScaffold)

    case absi(result: HealthMetricsCalculator.ABSIResult)
    case bodyFat(value: Double, gender: Gender)
    case conicity(result: HealthMetricsCalculator.ConicityResult)
}

// MARK: - ComputedMetricDetailView

struct ComputedMetricDetailView: View {
    let config: ComputedMetricConfig
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch config {
        case .bmi, .whtr, .whr:
            classicScaffoldView
        case .absi, .bodyFat, .conicity:
            insightScaffoldView
        }
    }

    // MARK: - Classic Scaffold (BMI / WHtR / WHR)

    private var classicScaffoldView: some View {
        ZStack(alignment: .top) {
            AppScreenBackground()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string(classicTitle))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(AppLocalization.string(classicAbbreviation))
                            .font(AppTypography.body)
                            .foregroundStyle(Color.appAccent)
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Current value
                    classicCurrentValueCard

                    // Description
                    classicDescriptionCard

                    // Why It Matters
                    WhyItMattersCard(items: classicWhyItMattersItems)

                    // Legend
                    classicLegendCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle(AppLocalization.string(classicAbbreviation))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Classic — titles

    private var classicTitle: String {
        switch config {
        case .bmi: return "Body Mass Index"
        case .whtr: return "Waist-to-Height Ratio"
        case .whr: return "Waist-to-Hip Ratio"
        default: return ""
        }
    }

    private var classicAbbreviation: String {
        switch config {
        case .bmi: return "BMI"
        case .whtr: return "WHtR"
        case .whr: return "WHR"
        default: return ""
        }
    }

    // MARK: Classic — current value card

    private var classicCurrentValueCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                Text(classicFormattedValue)
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Spacer()

                Text(AppLocalization.string(classicCategoryRawValue))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.bestAccessibleTextColor(onHex: classicCategoryColor))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: classicCategoryColor), in: RoundedRectangle(cornerRadius: AppRadius.sm))
            }

            // BMI-specific age group info
            if case .bmi(let result) = config, let age = result.age {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(AppTypography.caption)
                    Text(AppLocalization.string("bmi.age.group", age, result.ageGroup.displayName))
                        .font(AppTypography.caption)
                }
                .foregroundStyle(AppColorRoles.textSecondary)
            }

            Text(AppLocalization.string(classicCategoryDescription))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(hex: "#14213D").opacity(0.5),
                        Color(hex: "#000000").opacity(0.3)
                    ]
                    : [
                        AppColorRoles.surfaceElevated,
                        AppColorRoles.surfaceElevated
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: classicCategoryColor).opacity(colorScheme == .dark ? 0.3 : 0.18), lineWidth: 1.5)
        )
    }

    private var classicFormattedValue: String {
        switch config {
        case .bmi(let result): return String(format: "%.1f", result.bmi)
        case .whtr(let result): return String(format: "%.2f", result.ratio)
        case .whr(let result, _): return String(format: "%.2f", result.ratio)
        default: return ""
        }
    }

    private var classicCategoryRawValue: String {
        switch config {
        case .bmi(let result): return result.category.rawValue
        case .whtr(let result): return result.category.rawValue
        case .whr(let result, _): return result.category.rawValue
        default: return ""
        }
    }

    private var classicCategoryColor: String {
        switch config {
        case .bmi(let result): return result.category.color
        case .whtr(let result): return result.category.color
        case .whr(let result, _): return result.category.color
        default: return ""
        }
    }

    private var classicCategoryDescription: String {
        switch config {
        case .bmi(let result): return result.category.description(for: result.ageGroup)
        case .whtr(let result): return result.category.description
        case .whr(let result, _): return result.category.description
        default: return ""
        }
    }

    // MARK: Classic — description card

    private var classicDescriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.appAccent)

                Text(AppLocalization.string(classicAboutTitle))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }

            Text(AppLocalization.string(classicDescriptionKey))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(hex: "#14213D").opacity(0.4),
                        Color(hex: "#000000")
                    ]
                    : [
                        AppColorRoles.surfacePrimary,
                        AppColorRoles.surfacePrimary
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appAccent.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 1)
        )
    }

    private var classicAboutTitle: String {
        switch config {
        case .bmi: return "About BMI"
        case .whtr: return "About WHtR"
        case .whr: return "About WHR"
        default: return ""
        }
    }

    private var classicDescriptionKey: String {
        switch config {
        case .bmi: return "health.bmi.description"
        case .whtr: return "health.whtr.description"
        case .whr: return "health.whr.description"
        default: return ""
        }
    }

    // MARK: Classic — why it matters items

    private var classicWhyItMattersItems: [WhyItMattersItem] {
        switch config {
        case .bmi:
            return [
                WhyItMattersItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: AppLocalization.string("Quick context"),
                    description: AppLocalization.string("BMI gives a fast, broad view of weight status over time.")
                ),
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Risk signal"),
                    description: AppLocalization.string("Large shifts can correlate with cardiometabolic risk.")
                ),
                WhyItMattersItem(
                    icon: "figure.strengthtraining.traditional",
                    title: AppLocalization.string("Use with context"),
                    description: AppLocalization.string("Pair it with waist and body fat for a fuller picture.")
                )
            ]
        case .whtr:
            return [
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Cardio health"),
                    description: AppLocalization.string("WHtR reflects central fat, a strong signal for cardiovascular risk.")
                ),
                WhyItMattersItem(
                    icon: "bolt.heart.fill",
                    title: AppLocalization.string("Metabolic risk"),
                    description: AppLocalization.string("Higher ratios are linked to insulin resistance and metabolic strain.")
                ),
                WhyItMattersItem(
                    icon: "target",
                    title: AppLocalization.string("Actionable"),
                    description: AppLocalization.string("Waist changes can move this ratio quickly, making it useful for progress.")
                )
            ]
        case .whr:
            return [
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Cardio health"),
                    description: AppLocalization.string("WHtR reflects central fat, a strong signal for cardiovascular risk.")
                ),
                WhyItMattersItem(
                    icon: "bolt.heart.fill",
                    title: AppLocalization.string("Metabolic risk"),
                    description: AppLocalization.string("Higher ratios are linked to insulin resistance and metabolic strain.")
                ),
                WhyItMattersItem(
                    icon: "target",
                    title: AppLocalization.string("Actionable"),
                    description: AppLocalization.string("Waist changes can move this ratio quickly, making it useful for progress.")
                )
            ]
        default:
            return []
        }
    }

    // MARK: Classic — legend card

    @ViewBuilder
    private var classicLegendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.appAccent)

                classicLegendHeader
            }

            VStack(spacing: 12) {
                ForEach(classicLegendRows, id: \.title) { item in
                    LegendRow(
                        title: item.title,
                        range: item.range,
                        description: item.description
                    )
                }
            }

            // BMI child disclaimer
            if case .bmi(let result) = config, result.ageGroup == .child {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.appAccent)

                    Text(AppLocalization.string("Note: For children and adolescents, BMI interpretation should ideally use age and gender-specific percentile charts. These simplified ranges are approximations."))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }

            // WHR gender notice
            if case .whr(_, let gender) = config, gender == .notSpecified {
                whrGenderNoticeCard
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(hex: "#14213D").opacity(0.4),
                        Color(hex: "#000000")
                    ]
                    : [
                        AppColorRoles.surfacePrimary,
                        AppColorRoles.surfacePrimary
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appAccent.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var classicLegendHeader: some View {
        switch config {
        case .bmi(let result):
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string("BMI Ranges"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("bmi.for.agegroup", result.ageGroup.displayName))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
        case .whtr:
            Text(AppLocalization.string("WHtR Ranges"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
        case .whr(_, let gender):
            Text(gender == .male
                ? AppLocalization.string("WHR Ranges (Male)")
                : AppLocalization.string("WHR Ranges (Female)"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
        default:
            EmptyView()
        }
    }

    private var classicLegendRows: [(title: String, range: String, description: String)] {
        switch config {
        case .bmi(let result):
            return HealthMetricsReference.bmiRanges(for: result.ageGroup)
        case .whtr:
            return HealthMetricsReference.whtrRanges
        case .whr(_, let gender):
            return gender == .male ? HealthMetricsReference.whrRangesMale : HealthMetricsReference.whrRangesFemale
        default:
            return []
        }
    }

    private var whrGenderNoticeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark")
                    .foregroundStyle(Color.appAccent)

                Text(AppLocalization.string("Gender not specified"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }

            Text(AppLocalization.string("WHR thresholds differ between males and females. Set your gender in Settings for more accurate ranges."))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppLocalization.string("Currently showing female ranges (more conservative)."))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textTertiary)
                .italic()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.appAccent.opacity(colorScheme == .dark ? 0.10 : 0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appAccent.opacity(colorScheme == .dark ? 0.3 : 0.16), lineWidth: 1)
        )
    }

    // MARK: - Insight Scaffold (ABSI / BodyFat / Conicity)

    private var insightScaffoldView: some View {
        SettingsScrollDetailScaffold(title: AppLocalization.string(insightTitle), theme: .health) {
            HealthInsightHeroCard(accent: Color(hex: insightCategoryColor)) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocalization.string(insightTitle))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    insightHeroValueRow

                    Text(AppLocalization.string(insightCategoryRawValue))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(Color.bestAccessibleTextColor(onHex: insightCategoryColor))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: insightCategoryColor), in: RoundedRectangle(cornerRadius: 8))

                    insightHeroFooter
                }
            }

            HealthInsightCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string(insightWhatIsTitle))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string(insightDescriptionParagraph1))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppLocalization.string(insightDescriptionParagraph2))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }

            WhyItMattersCard(items: insightWhyItMattersItems)

            HealthInsightCard(tint: Color(hex: insightCategoryColor).opacity(0.10)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string(insightRangesTitle))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    VStack(spacing: 8) {
                        ForEach(insightRanges, id: \.title) { range in
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

            HealthInsightNoteCard(accent: insightNoteAccentColor) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: insightNoteIcon)
                            .foregroundStyle(insightNoteAccentColor)

                        Text(AppLocalization.string(insightNoteTitle))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }

                    Text(AppLocalization.string(insightNoteText))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Insight — hero row

    @ViewBuilder
    private var insightHeroValueRow: some View {
        switch config {
        case .absi(let result):
            Text(String(format: "%.3f", result.absi))
                .font(AppTypography.displayLarge)
                .foregroundStyle(AppColorRoles.textPrimary)
        case .bodyFat(let value, _):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", value))
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("%"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
        case .conicity(let result):
            Text(String(format: "%.2f", result.conicity))
                .font(AppTypography.displayLarge)
                .foregroundStyle(AppColorRoles.textPrimary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var insightHeroFooter: some View {
        switch config {
        case .bodyFat:
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(AppTypography.caption)
                Text(AppLocalization.string("From HealthKit"))
                    .font(AppTypography.caption)
            }
            .foregroundStyle(AppColorRoles.textTertiary)
            .padding(.top, 4)
        case .absi(let result):
            Text(AppLocalization.string(result.category.description))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .padding(.top, 4)
        case .conicity(let result):
            Text(AppLocalization.string(result.category.description))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .padding(.top, 4)
        default:
            EmptyView()
        }
    }

    // MARK: Insight — category

    private var insightCategoryRawValue: String {
        switch config {
        case .absi(let result): return result.category.rawValue
        case .bodyFat(let value, let gender): return bodyFatCategory(value: value, gender: gender).name
        case .conicity(let result): return result.category.rawValue
        default: return ""
        }
    }

    private var insightCategoryColor: String {
        switch config {
        case .absi(let result): return result.category.color
        case .bodyFat(let value, let gender): return bodyFatCategory(value: value, gender: gender).color
        case .conicity(let result): return result.category.color
        default: return ""
        }
    }

    // MARK: Insight — title strings

    private var insightTitle: String {
        switch config {
        case .absi: return "Body Shape Risk"
        case .bodyFat: return "Body Fat Percentage"
        case .conicity: return "Central Fat Risk"
        default: return ""
        }
    }

    private var insightWhatIsTitle: String {
        switch config {
        case .absi: return "What is Body Shape Risk?"
        case .bodyFat: return "What is Body Fat Percentage?"
        case .conicity: return "What is Central Fat Risk?"
        default: return ""
        }
    }

    private var insightDescriptionParagraph1: String {
        switch config {
        case .absi:
            return "A Body Shape Index (ABSI) measures the health risk associated with your abdominal fat distribution, independent of your total body weight. It focuses on health outcomes rather than appearance."
        case .bodyFat:
            return "Body fat percentage is the proportion of your body weight that is fat tissue. It provides a more accurate picture of your body composition than weight or BMI alone."
        case .conicity:
            return "The Conicity Index is an indicator of central (abdominal) fat accumulation. It evaluates how your body mass is distributed around your waist relative to your height and weight."
        default:
            return ""
        }
    }

    private var insightDescriptionParagraph2: String {
        switch config {
        case .absi:
            return "Higher ABSI values indicate more abdominal fat relative to your BMI and height, which is associated with increased cardiovascular and metabolic health risks."
        case .bodyFat:
            return "This data is sourced from the Health app, which may collect it from compatible scales, fitness devices, or manual entries."
        case .conicity:
            return "Higher values indicate more fat concentrated in the abdominal area, which is associated with increased risk of cardiovascular disease, type 2 diabetes, and metabolic syndrome."
        default:
            return ""
        }
    }

    private var insightRangesTitle: String {
        switch config {
        case .absi: return "Risk Categories"
        case .bodyFat(_, let gender): return AppLocalization.string("reference.ranges.gender", gender.displayName)
        case .conicity: return "Risk Categories"
        default: return ""
        }
    }

    // MARK: Insight — why it matters

    private var insightWhyItMattersItems: [WhyItMattersItem] {
        switch config {
        case .absi:
            return [
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
            ]
        case .bodyFat:
            return [
                WhyItMattersItem(
                    icon: "figure.walk",
                    title: AppLocalization.string("Composition focus"),
                    description: AppLocalization.string("Body fat percentage shows how weight is split between fat and lean mass.")
                ),
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Metabolic health"),
                    description: AppLocalization.string("Very high levels can add cardiometabolic strain over time.")
                ),
                WhyItMattersItem(
                    icon: "target",
                    title: AppLocalization.string("Progress clarity"),
                    description: AppLocalization.string("It helps track recomposition even when scale weight is steady.")
                )
            ]
        case .conicity:
            return [
                WhyItMattersItem(
                    icon: "heart.fill",
                    title: AppLocalization.string("Central fat"),
                    description: AppLocalization.string("Conicity highlights abdominal fat linked to cardiometabolic risk.")
                ),
                WhyItMattersItem(
                    icon: "waveform.path.ecg",
                    title: AppLocalization.string("Risk insight"),
                    description: AppLocalization.string("It can reveal risk even when weight looks stable.")
                ),
                WhyItMattersItem(
                    icon: "target",
                    title: AppLocalization.string("Trackable"),
                    description: AppLocalization.string("Waist changes help move this index in a healthier direction.")
                )
            ]
        default:
            return []
        }
    }

    // MARK: Insight — ranges

    private var insightRanges: [(title: String, range: String, color: String)] {
        switch config {
        case .absi(let result):
            return absiRanges(gender: result.gender)
        case .bodyFat(let value, let gender):
            return bodyFatRanges(gender: gender)
        case .conicity(let result):
            return conicityRanges(gender: result.gender)
        default:
            return []
        }
    }

    private func absiRanges(gender: Gender) -> [(title: String, range: String, color: String)] {
        switch gender {
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

    private func bodyFatRanges(gender: Gender) -> [(title: String, range: String, color: String)] {
        switch gender {
        case .male:
            return [
                ("Essential", "< 10%", "#3B82F6"),
                ("Athletic", "10-20%", AppColorRoles.stateSuccessHex),
                ("Fitness", "20-25%", "#FCA311"),
                ("High", "> 25%", "#EF4444")
            ]
        case .female:
            return [
                ("Essential", "< 20%", "#3B82F6"),
                ("Athletic", "20-30%", AppColorRoles.stateSuccessHex),
                ("Fitness", "30-35%", "#FCA311"),
                ("High", "> 35%", "#EF4444")
            ]
        case .notSpecified:
            return [
                ("Low", "< 15%", "#3B82F6"),
                ("Normal", "15-25%", AppColorRoles.stateSuccessHex),
                ("Elevated", "25-30%", "#FCA311"),
                ("High", "> 30%", "#EF4444")
            ]
        }
    }

    private func conicityRanges(gender: Gender) -> [(title: String, range: String, color: String)] {
        switch gender {
        case .male:
            return [
                ("Low risk", "< 1.20", AppColorRoles.stateSuccessHex),
                ("Moderate risk", "1.20-1.30", "#FCA311"),
                ("High risk", "> 1.30", "#EF4444")
            ]
        case .female:
            return [
                ("Low risk", "< 1.15", AppColorRoles.stateSuccessHex),
                ("Moderate risk", "1.15-1.25", "#FCA311"),
                ("High risk", "> 1.25", "#EF4444")
            ]
        case .notSpecified:
            return [
                ("Low risk", "< 1.20", AppColorRoles.stateSuccessHex),
                ("Moderate risk", "1.20-1.30", "#FCA311"),
                ("High risk", "> 1.30", "#EF4444")
            ]
        }
    }

    // MARK: Insight — note card

    private var insightNoteAccentColor: Color {
        switch config {
        case .bodyFat: return Color(hex: "#3B82F6")
        default: return AppColorRoles.accentPrimary
        }
    }

    private var insightNoteIcon: String {
        switch config {
        case .bodyFat: return "info.circle.fill"
        default: return "heart.text.square.fill"
        }
    }

    private var insightNoteTitle: String {
        switch config {
        case .bodyFat: return "Important"
        default: return "Health Note"
        }
    }

    private var insightNoteText: String {
        switch config {
        case .absi:
            return "ABSI is a research-based indicator and should be considered alongside other health metrics. It is not a medical diagnosis. Consult with healthcare professionals for personalized health assessments and recommendations."
        case .bodyFat:
            return "Body fat percentage measurements can vary depending on the measurement method. For the most accurate assessment, use the same device consistently and measure under similar conditions."
        case .conicity:
            return "The Conicity Index is a screening tool and should be interpreted alongside other health indicators. It is not a medical diagnosis. Consult with healthcare professionals for comprehensive health assessments."
        default:
            return ""
        }
    }

    // MARK: - Body Fat helpers

    private func bodyFatCategory(value: Double, gender: Gender) -> (name: String, color: String) {
        switch gender {
        case .male:
            if value < 10 { return ("Essential", "#3B82F6") }
            else if value < 20 { return ("Athletic", AppColorRoles.stateSuccessHex) }
            else if value < 25 { return ("Fitness", "#FCA311") }
            else { return ("High", "#EF4444") }
        case .female:
            if value < 20 { return ("Essential", "#3B82F6") }
            else if value < 30 { return ("Athletic", AppColorRoles.stateSuccessHex) }
            else if value < 35 { return ("Fitness", "#FCA311") }
            else { return ("High", "#EF4444") }
        case .notSpecified:
            if value < 15 { return ("Low", "#3B82F6") }
            else if value < 25 { return ("Normal", AppColorRoles.stateSuccessHex) }
            else if value < 30 { return ("Elevated", "#FCA311") }
            else { return ("High", "#EF4444") }
        }
    }
}

// MARK: - LegendRow (previously in WHtRDetailView)

struct LegendRow: View {
    let title: String
    let range: String
    let description: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Kolorowa kropka
                Circle()
                    .fill(colorForCategory(title))
                    .frame(width: 10, height: 10)

                // Nazwa kategorii
                Text(AppLocalization.string(title))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Spacer()

                // Zakres
                Text(range)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        colorScheme == .dark ? Color(hex: "#14213D").opacity(0.5) : AppColorRoles.surfaceInteractive,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }

            // Opis
            Text(AppLocalization.string(description))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .padding(.leading, 22)
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        if category.contains("Normal") {
            return AppColorRoles.stateSuccess
        } else if category.contains("Overweight") || category.contains("Increased") {
            return Color(hex: "#FCA311")
        } else if category.contains("Underweight") {
            return Color(hex: "#3B82F6")
        } else {
            return Color(hex: "#EF4444")
        }
    }
}

// MARK: - Convenience typealiases (backward-compat shims)
// These allow call sites to migrate at their own pace.
// Usage: replace old view names with ComputedMetricDetailView(config: .xxx).

typealias BMIDetailView = _BMIDetailViewShim
typealias BodyFatDetailView = _BodyFatDetailViewShim
typealias ABSIDetailView = _ABSIDetailViewShim
typealias WHtRDetailView = _WHtRDetailViewShim
typealias WHRDetailView = _WHRDetailViewShim
typealias ConicityDetailView = _ConicityDetailViewShim

struct _BMIDetailViewShim: View {
    let result: HealthMetricsCalculator.BMIResult
    var body: some View { ComputedMetricDetailView(config: .bmi(result: result)) }
}

struct _BodyFatDetailViewShim: View {
    let value: Double
    let gender: Gender
    var body: some View { ComputedMetricDetailView(config: .bodyFat(value: value, gender: gender)) }
}

struct _ABSIDetailViewShim: View {
    let result: HealthMetricsCalculator.ABSIResult
    var body: some View { ComputedMetricDetailView(config: .absi(result: result)) }
}

struct _WHtRDetailViewShim: View {
    let result: HealthMetricsCalculator.WHtRResult
    var body: some View { ComputedMetricDetailView(config: .whtr(result: result)) }
}

struct _WHRDetailViewShim: View {
    let result: HealthMetricsCalculator.WHRResult
    let gender: Gender
    var body: some View { ComputedMetricDetailView(config: .whr(result: result, gender: gender)) }
}

struct _ConicityDetailViewShim: View {
    let result: HealthMetricsCalculator.ConicityResult
    var body: some View { ComputedMetricDetailView(config: .conicity(result: result)) }
}
