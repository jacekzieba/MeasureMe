import SwiftUI

struct PhysiqueIndicatorsSection: View {
    @AppSetting(\.profile.userGender) private var userGenderRaw: String = "notSpecified"
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0

    @AppSetting(\.indicators.showPhysiqueSWR) private var showPhysiqueSWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueCWR) private var showPhysiqueCWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueSHR) private var showPhysiqueSHR: Bool = true
    @AppSetting(\.indicators.showPhysiqueHWR) private var showPhysiqueHWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueBWR) private var showPhysiqueBWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueWHtR) private var showPhysiqueWHtR: Bool = true
    @AppSetting(\.indicators.showPhysiqueBodyFat) private var showPhysiqueBodyFat: Bool = true
    @AppSetting(\.indicators.showPhysiqueRFM) private var showPhysiqueRFM: Bool = true

    let latestWaist: Double?
    let latestHeight: Double?
    let latestWeight: Double?
    let latestBodyFat: Double?
    let latestShoulders: Double?
    let latestChest: Double?
    let latestBust: Double?
    let latestHips: Double?

    private var userGender: Gender {
        Gender(rawValue: userGenderRaw) ?? .notSpecified
    }

    private var effectiveHeight: Double? {
        if manualHeight > 0 { return manualHeight }
        return latestHeight
    }

    private var swr: PhysiqueIndicatorsCalculator.RatioResult? {
        PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: latestShoulders, waistCm: latestWaist)
    }

    private var cwr: GenderDependentResult<PhysiqueIndicatorsCalculator.RatioResult>? {
        PhysiqueIndicatorsCalculator.calculateCWR(chestCm: latestChest, waistCm: latestWaist, gender: userGender)
    }

    private var hwr: GenderDependentResult<PhysiqueIndicatorsCalculator.RatioResult>? {
        PhysiqueIndicatorsCalculator.calculateHWR(hipsCm: latestHips, waistCm: latestWaist, gender: userGender)
    }

    private var bwr: GenderDependentResult<PhysiqueIndicatorsCalculator.RatioResult>? {
        PhysiqueIndicatorsCalculator.calculateBWR(
            bustCm: latestBust,
            chestCm: latestChest,
            waistCm: latestWaist,
            gender: userGender
        )
    }

    private var shr: GenderDependentResult<PhysiqueIndicatorsCalculator.BalanceResult>? {
        PhysiqueIndicatorsCalculator.calculateSHR(shouldersCm: latestShoulders, hipsCm: latestHips, gender: userGender)
    }

    private var whtrVisual: PhysiqueIndicatorsCalculator.HybridWHtRResult? {
        PhysiqueIndicatorsCalculator.classifyWHtRVisual(waistCm: latestWaist, heightCm: effectiveHeight)
    }

    private var bodyFatVisual: GenderDependentResult<PhysiqueIndicatorsCalculator.VisualBodyFatResult>? {
        PhysiqueIndicatorsCalculator.classifyBodyFat(percent: latestBodyFat, gender: userGender)
    }

    private var rfmVisual: GenderDependentResult<PhysiqueIndicatorsCalculator.VisualBodyFatResult>? {
        let rfm = HealthMetricsCalculator.calculateRFMWithGenderRequirement(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            gender: userGender
        )
        guard let rfm else { return nil }
        switch rfm {
        case .requiresGender:
            return .requiresGender
        case .value(let value):
            return PhysiqueIndicatorsCalculator.classifyRFM(rfm: value.rfm, gender: userGender)
        }
    }

    private var hasAnyEnabled: Bool {
        let proportionsEnabled = showPhysiqueSWR || showPhysiqueCWR || showPhysiqueSHR || showPhysiqueHWR || showPhysiqueBWR
        let hybridsEnabled = showPhysiqueWHtR || showPhysiqueBodyFat || showPhysiqueRFM
        return proportionsEnabled || hybridsEnabled
    }

    var body: some View {
        VStack(spacing: 12) {
            if !hasAnyEnabled {
                noMetricsEnabledView
            } else {
                if showAnyProportions {
                    PhysiqueSectionCard(title: AppLocalization.string("Proportion ratios"), icon: "figure.strengthtraining.traditional") {
                        VStack(spacing: 8) {
                            proportionRows
                        }
                    }
                }

                if showAnyHybrids {
                    PhysiqueSectionCard(title: AppLocalization.string("Hybrid metrics"), icon: "ruler") {
                        VStack(spacing: 8) {
                            hybridRows
                        }
                    }
                }
            }
        }
    }

    private var showAnyProportions: Bool {
        switch userGender {
        case .male:
            return showPhysiqueSWR || showPhysiqueCWR || showPhysiqueSHR
        case .female:
            return showPhysiqueHWR || showPhysiqueBWR || showPhysiqueSHR
        case .notSpecified:
            return showPhysiqueSWR || showPhysiqueCWR || showPhysiqueHWR || showPhysiqueBWR || showPhysiqueSHR
        }
    }

    private var showAnyHybrids: Bool {
        showPhysiqueWHtR || showPhysiqueBodyFat || showPhysiqueRFM
    }

    @ViewBuilder
    private var proportionRows: some View {
        switch userGender {
        case .male:
            if showPhysiqueSWR {
                if let swr {
                    PhysiqueMetricRow(
                        title: AppLocalization.string("Shoulder-to-Waist Ratio"),
                        value: String(format: "%.2f", swr.value),
                        category: AppLocalization.string(swr.category.rawValue),
                        categoryColor: swr.category.color,
                        destination: PhysiqueRatioDetailView(
                            title: AppLocalization.string("Shoulder-to-Waist Ratio"),
                            shortCode: "SWR",
                            formula: AppLocalization.string("formula.swr"),
                            valueText: String(format: "%.2f", swr.value),
                            categoryName: AppLocalization.string(swr.category.rawValue),
                            categoryColor: swr.category.color,
                            summary: AppLocalization.string("Simplest V-taper indicator: wider upper body relative to waist."),
                            improve: AppLocalization.string("Lower waist and build delts/lats for a stronger silhouette."),
                            ranges: [
                                PhysiqueRange(title: AppLocalization.string("Average"), value: "1.30 - 1.44", color: "#60A5FA"),
                                PhysiqueRange(title: AppLocalization.string("Athletic"), value: "1.45 - 1.59", color: "#22C55E"),
                                PhysiqueRange(title: AppLocalization.string("Top"), value: ">= 1.60", color: "#FCA311")
                            ]
                        )
                    )
                } else {
                    missingRow(
                        title: AppLocalization.string("Shoulder-to-Waist Ratio"),
                        requirements: [AppLocalization.string("Shoulders"), AppLocalization.string("Waist")]
                    )
                }
            }

            if showPhysiqueCWR {
                switch cwr {
                case .value(let result):
                    PhysiqueMetricRow(
                        title: AppLocalization.string("Chest-to-Waist Ratio"),
                        value: String(format: "%.2f", result.value),
                        category: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        destination: PhysiqueRatioDetailView(
                            title: AppLocalization.string("Chest-to-Waist Ratio"),
                            shortCode: "CWR",
                            formula: AppLocalization.string("formula.cwr"),
                            valueText: String(format: "%.2f", result.value),
                            categoryName: AppLocalization.string(result.category.rawValue),
                            categoryColor: result.category.color,
                            summary: AppLocalization.string("Shows how much upper torso dominates over waist."),
                            improve: AppLocalization.string("Build upper chest and back while reducing waist."),
                            ranges: [
                                PhysiqueRange(title: AppLocalization.string("Average"), value: "1.10 - 1.19", color: "#60A5FA"),
                                PhysiqueRange(title: AppLocalization.string("Athletic"), value: "1.20 - 1.29", color: "#22C55E"),
                                PhysiqueRange(title: AppLocalization.string("Top"), value: ">= 1.30", color: "#FCA311")
                            ]
                        )
                    )
                case .requiresGender:
                    requiresGenderRow(title: AppLocalization.string("Chest-to-Waist Ratio"))
                case .none:
                    missingRow(
                        title: AppLocalization.string("Chest-to-Waist Ratio"),
                        requirements: [AppLocalization.string("Chest"), AppLocalization.string("Waist")]
                    )
                }
            }

            if showPhysiqueSHR {
                switch shr {
                case .value(let result):
                    PhysiqueMetricRow(
                        title: AppLocalization.string("Shoulder-to-Hip Ratio"),
                        value: String(format: "%.2f", result.value),
                        category: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        destination: PhysiqueRatioDetailView(
                            title: AppLocalization.string("Shoulder-to-Hip Ratio"),
                            shortCode: "SHR",
                            formula: AppLocalization.string("formula.shr"),
                            valueText: String(format: "%.2f", result.value),
                            categoryName: AppLocalization.string(result.category.rawValue),
                            categoryColor: result.category.color,
                            summary: AppLocalization.string("Upper-to-lower body balance. This is preference-dependent, not good/bad."),
                            improve: AppLocalization.string("Adjust upper or lower body training based on your aesthetic goal."),
                            ranges: [
                                PhysiqueRange(title: AppLocalization.string("Lower-body dominant"), value: "< 1.00", color: "#60A5FA"),
                                PhysiqueRange(title: AppLocalization.string("Balanced frame"), value: "1.00 - 1.25", color: "#22C55E"),
                                PhysiqueRange(title: AppLocalization.string("Upper-body dominant"), value: "> 1.25", color: "#FCA311")
                            ]
                        )
                    )
                case .requiresGender:
                    requiresGenderRow(title: AppLocalization.string("Shoulder-to-Hip Ratio"))
                case .none:
                    missingRow(
                        title: AppLocalization.string("Shoulder-to-Hip Ratio"),
                        requirements: [AppLocalization.string("Shoulders"), AppLocalization.string("Hips")]
                    )
                }
            }

        case .female:
            if showPhysiqueHWR {
                switch hwr {
                case .value(let result):
                    PhysiqueMetricRow(
                        title: AppLocalization.string("Hip-to-Waist Ratio"),
                        value: String(format: "%.2f", result.value),
                        category: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        destination: PhysiqueRatioDetailView(
                            title: AppLocalization.string("Hip-to-Waist Ratio"),
                            shortCode: "HWR",
                            formula: AppLocalization.string("formula.hwr"),
                            valueText: String(format: "%.2f", result.value),
                            categoryName: AppLocalization.string(result.category.rawValue),
                            categoryColor: result.category.color,
                            summary: AppLocalization.string("Higher value means narrower waist relative to hips."),
                            improve: AppLocalization.string("Lower waist and build glutes/legs progressively."),
                            ranges: [
                                PhysiqueRange(title: AppLocalization.string("Average"), value: "1.25 - 1.34", color: "#60A5FA"),
                                PhysiqueRange(title: AppLocalization.string("Athletic"), value: "1.35 - 1.49", color: "#22C55E"),
                                PhysiqueRange(title: AppLocalization.string("Top"), value: ">= 1.50", color: "#FCA311")
                            ]
                        )
                    )
                case .requiresGender:
                    requiresGenderRow(title: AppLocalization.string("Hip-to-Waist Ratio"))
                case .none:
                    missingRow(
                        title: AppLocalization.string("Hip-to-Waist Ratio"),
                        requirements: [AppLocalization.string("Hips"), AppLocalization.string("Waist")]
                    )
                }
            }

            if showPhysiqueBWR {
                switch bwr {
                case .value(let result):
                    PhysiqueMetricRow(
                        title: AppLocalization.string("Bust-to-Waist Ratio"),
                        value: String(format: "%.2f", result.value),
                        category: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        destination: PhysiqueRatioDetailView(
                            title: AppLocalization.string("Bust-to-Waist Ratio"),
                            shortCode: "BWR",
                            formula: AppLocalization.string("formula.bwr"),
                            valueText: String(format: "%.2f", result.value),
                            categoryName: AppLocalization.string(result.category.rawValue),
                            categoryColor: result.category.color,
                            summary: AppLocalization.string("Upper torso to waist proportion used in visual silhouette assessment."),
                            improve: AppLocalization.string("Improve posture, upper body training, and reduce waist gradually."),
                            ranges: [
                                PhysiqueRange(title: AppLocalization.string("Average"), value: "1.10 - 1.19", color: "#60A5FA"),
                                PhysiqueRange(title: AppLocalization.string("Athletic"), value: "1.20 - 1.29", color: "#22C55E"),
                                PhysiqueRange(title: AppLocalization.string("Top"), value: ">= 1.30", color: "#FCA311")
                            ]
                        )
                    )
                case .requiresGender:
                    requiresGenderRow(title: AppLocalization.string("Bust-to-Waist Ratio"))
                case .none:
                    missingRow(
                        title: AppLocalization.string("Bust-to-Waist Ratio"),
                        requirements: [AppLocalization.string("Bust or chest"), AppLocalization.string("Waist")]
                    )
                }
            }

            if showPhysiqueSHR {
                switch shr {
                case .value(let result):
                    PhysiqueMetricRow(
                        title: AppLocalization.string("Shoulder-to-Hip Ratio"),
                        value: String(format: "%.2f", result.value),
                        category: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        destination: PhysiqueRatioDetailView(
                            title: AppLocalization.string("Shoulder-to-Hip Ratio"),
                            shortCode: "SHR",
                            formula: AppLocalization.string("formula.shr"),
                            valueText: String(format: "%.2f", result.value),
                            categoryName: AppLocalization.string(result.category.rawValue),
                            categoryColor: result.category.color,
                            summary: AppLocalization.string("Upper-to-lower balance is goal-dependent and should be tracked as trend."),
                            improve: AppLocalization.string("Build delts/back or lower body depending on your desired look."),
                            ranges: [
                                PhysiqueRange(title: AppLocalization.string("Lower-body dominant"), value: "< 1.00", color: "#60A5FA"),
                                PhysiqueRange(title: AppLocalization.string("Balanced frame"), value: "1.00 - 1.25", color: "#22C55E"),
                                PhysiqueRange(title: AppLocalization.string("Upper-body dominant"), value: "> 1.25", color: "#FCA311")
                            ]
                        )
                    )
                case .requiresGender:
                    requiresGenderRow(title: AppLocalization.string("Shoulder-to-Hip Ratio"))
                case .none:
                    missingRow(
                        title: AppLocalization.string("Shoulder-to-Hip Ratio"),
                        requirements: [AppLocalization.string("Shoulders"), AppLocalization.string("Hips")]
                    )
                }
            }

        case .notSpecified:
            PhysiqueRequiresGenderCard()
        }
    }

    @ViewBuilder
    private var hybridRows: some View {
        if showPhysiqueWHtR {
            if let whtrVisual {
                PhysiqueMetricRow(
                    title: AppLocalization.string("Waist-Height Ratio"),
                    value: String(format: "%.2f", whtrVisual.ratio),
                    category: AppLocalization.string(whtrVisual.category.rawValue),
                    categoryColor: whtrVisual.category.color,
                    destination: PhysiqueRatioDetailView(
                        title: AppLocalization.string("Waist-Height Ratio"),
                        shortCode: "WHtR",
                        formula: AppLocalization.string("formula.whtr"),
                        valueText: String(format: "%.2f", whtrVisual.ratio),
                        categoryName: AppLocalization.string(whtrVisual.category.rawValue),
                        categoryColor: whtrVisual.category.color,
                        summary: AppLocalization.string("In physique view, WHtR is a visibility filter for proportions and definition."),
                        improve: AppLocalization.string("Lower waist while maintaining strength to improve visual definition."),
                        ranges: [
                            PhysiqueRange(title: AppLocalization.string("Visible definition"), value: "<= 0.50", color: "#22C55E"),
                            PhysiqueRange(title: AppLocalization.string("Soft definition"), value: "0.50 - 0.59", color: "#FCA311"),
                            PhysiqueRange(title: AppLocalization.string("Hidden proportions"), value: ">= 0.60", color: "#EF4444")
                        ]
                    )
                )
            } else {
                missingRow(
                    title: AppLocalization.string("Waist-Height Ratio"),
                    requirements: [AppLocalization.string("Waist"), AppLocalization.string("Height")]
                )
            }
        }

        if showPhysiqueBodyFat {
            switch bodyFatVisual {
            case .value(let result):
                PhysiqueMetricRow(
                    title: AppLocalization.string("Body Fat Percentage"),
                    value: String(format: "%.1f%%", result.percent),
                    category: AppLocalization.string(result.category.rawValue),
                    categoryColor: result.category.color,
                    destination: PhysiqueRatioDetailView(
                        title: AppLocalization.string("Body Fat Percentage"),
                        shortCode: "BF%",
                        formula: AppLocalization.string("formula.bf"),
                        valueText: String(format: "%.1f%%", result.percent),
                        categoryName: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        summary: AppLocalization.string("In physique view, BF% mostly controls sharpness and visible muscle separation."),
                        improve: AppLocalization.string("Reduce gradually to protect lean mass and visual quality."),
                        ranges: bodyFatRanges(for: userGender)
                    )
                )
            case .requiresGender:
                requiresGenderRow(title: AppLocalization.string("Body Fat Percentage"))
            case .none:
                missingRow(
                    title: AppLocalization.string("Body Fat Percentage"),
                    requirements: [AppLocalization.string("Body Fat Percentage")]
                )
            }
        }

        if showPhysiqueRFM {
            switch rfmVisual {
            case .value(let result):
                PhysiqueMetricRow(
                    title: AppLocalization.string("Relative Fat Mass"),
                    value: String(format: "%.1f%%", result.percent),
                    category: AppLocalization.string(result.category.rawValue),
                    categoryColor: result.category.color,
                    destination: PhysiqueRatioDetailView(
                        title: AppLocalization.string("Relative Fat Mass"),
                        shortCode: "RFM",
                        formula: AppLocalization.string("formula.rfm"),
                        valueText: String(format: "%.1f%%", result.percent),
                        categoryName: AppLocalization.string(result.category.rawValue),
                        categoryColor: result.category.color,
                        summary: AppLocalization.string("RFM acts as a body-fat estimator interpreted through a visual lens in this section."),
                        improve: AppLocalization.string("Main lever is waist reduction while preserving muscle."),
                        ranges: bodyFatRanges(for: userGender)
                    )
                )
            case .requiresGender:
                requiresGenderRow(title: AppLocalization.string("Relative Fat Mass"))
            case .none:
                missingRow(
                    title: AppLocalization.string("Relative Fat Mass"),
                    requirements: [AppLocalization.string("Waist"), AppLocalization.string("Height")]
                )
            }
        }
    }

    private func bodyFatRanges(for gender: Gender) -> [PhysiqueRange] {
        switch gender {
        case .male:
            return [
                PhysiqueRange(title: AppLocalization.string("Athletes"), value: "6 - 13%", color: "#22C55E"),
                PhysiqueRange(title: AppLocalization.string("Fitness"), value: "14 - 17%", color: "#34D399"),
                PhysiqueRange(title: AppLocalization.string("Average"), value: "18 - 24%", color: "#FCA311"),
                PhysiqueRange(title: AppLocalization.string("High"), value: ">= 25%", color: "#EF4444")
            ]
        case .female:
            return [
                PhysiqueRange(title: AppLocalization.string("Athletes"), value: "14 - 20%", color: "#22C55E"),
                PhysiqueRange(title: AppLocalization.string("Fitness"), value: "21 - 24%", color: "#34D399"),
                PhysiqueRange(title: AppLocalization.string("Average"), value: "25 - 31%", color: "#FCA311"),
                PhysiqueRange(title: AppLocalization.string("High"), value: ">= 32%", color: "#EF4444")
            ]
        case .notSpecified:
            return [
                PhysiqueRange(title: AppLocalization.string("Set gender"), value: AppLocalization.string("Required for range interpretation"), color: "#FCA311")
            ]
        }
    }

    private func requiresGenderRow(title: String) -> some View {
        PhysiqueMetricRow(
            title: title,
            value: "—",
            category: AppLocalization.string("Set gender"),
            categoryColor: "#FCA311",
            destination: GenderRequiredMetricView(metricName: title)
        )
    }

    private func missingRow(title: String, requirements: [String]) -> some View {
        PhysiqueMetricRow(
            title: title,
            value: "—",
            category: AppLocalization.string("Add data"),
            categoryColor: "#FCA311",
            destination: PhysiqueMissingDataDetailView(metricName: title, requirements: requirements)
        )
    }

    private var noMetricsEnabledView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color(hex: "#14B8A6"))
                Text(AppLocalization.string("No indicators selected"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }

            Text(AppLocalization.string("Enable physique indicators in Settings to see results here."))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.8))

            NavigationLink {
                SettingsView()
            } label: {
                Text(AppLocalization.string("Go to Settings"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#14B8A6"), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#0B1220"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "#14B8A6").opacity(0.35), lineWidth: 1)
                )
        )
    }
}

private struct PhysiqueSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: "#14B8A6"))
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#0B1220"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "#14B8A6").opacity(0.3), lineWidth: 1)
                )
        )
    }
}

private struct PhysiqueMetricRow<Destination: View>: View {
    let title: String
    let value: String
    let category: String
    let categoryColor: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(category)
                        .font(AppTypography.micro)
                        .foregroundStyle(Color.bestAccessibleTextColor(onHex: categoryColor))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 4))
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text(value)
                        .font(AppTypography.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(minHeight: 44)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PhysiqueRequiresGenderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(Color(hex: "#FCA311"))
                Text(AppLocalization.string("Set gender to unlock these indicators"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("physique.requires.gender.title")
            }

            Text(AppLocalization.string("Physique ratio interpretation in this section is sex-specific. Set your profile gender to view values and ranges."))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.82))

            NavigationLink {
                SettingsView()
            } label: {
                Text(AppLocalization.string("Open profile settings"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#FCA311"), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("physique.requires.gender.cta")
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct PhysiqueRange {
    let title: String
    let value: String
    let color: String
}

private struct PhysiqueRatioDetailView: View {
    let title: String
    let shortCode: String
    let formula: String
    let valueText: String
    let categoryName: String
    let categoryColor: String
    let summary: String
    let improve: String
    let ranges: [PhysiqueRange]

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 340, tint: Color(hex: "#14B8A6").opacity(0.16))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                        Text(shortCode)
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color(hex: "#14B8A6"))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(valueText)
                            .font(AppTypography.displayLarge)
                            .foregroundStyle(.white)
                        Text(categoryName)
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color.bestAccessibleTextColor(onHex: categoryColor))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    infoCard(title: AppLocalization.string("Formula"), body: formula)
                    infoCard(title: AppLocalization.string("What it means"), body: summary)
                    infoCard(title: AppLocalization.string("How to improve"), body: improve)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLocalization.string("Reference ranges"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)

                        ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: range.color))
                                    .frame(width: 10, height: 10)
                                Text(range.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(.white)
                                Spacer(minLength: 8)
                                Text(range.value)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(title)
        .physiqueIndicatorDetailNavigationStyle()
    }

    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
            Text(body)
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct PhysiqueMissingDataDetailView: View {
    @EnvironmentObject private var router: AppRouter
    let metricName: String
    let requirements: [String]

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 320, tint: Color(hex: "#14B8A6").opacity(0.16))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(metricName)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)

                    Text(AppLocalization.string("To calculate this indicator, add:"))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.82))

                    ForEach(requirements, id: \.self) { requirement in
                        Text("• \(requirement)")
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    Button {
                        Haptics.light()
                        router.presentedSheet = .composer(mode: .newPost)
                    } label: {
                        Text(AppLocalization.string("Add measurement"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#14B8A6"), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .navigationTitle(metricName)
        .physiqueIndicatorDetailNavigationStyle()
    }
}

private struct GenderRequiredMetricView: View {
    let metricName: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 320, tint: Color(hex: "#FCA311").opacity(0.18))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(metricName)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)

                    Text(AppLocalization.string("Set your gender in Profile to unlock this indicator and its ranges."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Text(AppLocalization.string("Open profile settings"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#FCA311"), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .navigationTitle(metricName)
        .physiqueIndicatorDetailNavigationStyle()
    }
}

private extension View {
    func physiqueIndicatorDetailNavigationStyle() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
