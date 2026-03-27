import SwiftUI

private let healthAccentGradient = LinearGradient(
    colors: [
        Color.dynamic(light: Color(hex: "#1FAF9F"), dark: Color(hex: "#7BF0DA")),
        Color.dynamic(light: Color(hex: "#0F766E"), dark: Color(hex: "#27B7A7"))
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct HealthMetricsSection: View {
    enum DisplayMode {
        case summaryOnly
        case indicatorsOnly
        case full
    }

    @AppSetting(\.profile.userName) private var userName: String = ""
    @EnvironmentObject private var premiumStore: PremiumStore
    @AppSetting(\.profile.userGender) private var userGenderRaw: String = "notSpecified"
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    @AppSetting(\.profile.userAge) private var userAgeValue: Int = 0

    // Core Metrics visibility
    @AppSetting(\.indicators.showWHtROnHome) private var showWHtROnHome: Bool = true
    @AppSetting(\.indicators.showRFMOnHome) private var showRFMOnHome: Bool = true
    @AppSetting(\.indicators.showBMIOnHome) private var showBMIOnHome: Bool = true

    // Body Composition visibility
    @AppSetting(\.indicators.showBodyFatOnHome) private var showBodyFatOnHome: Bool = true
    @AppSetting(\.indicators.showLeanMassOnHome) private var showLeanMassOnHome: Bool = true

    // Health distribution and risk visibility
    @AppSetting(\.indicators.showWHROnHome) private var showWHROnHome: Bool = true
    @AppSetting(\.indicators.showWaistRiskOnHome) private var showWaistRiskOnHome: Bool = true
    @AppSetting(\.indicators.showABSIOnHome) private var showABSIOnHome: Bool = true
    @AppSetting(\.indicators.showBodyShapeScoreOnHome) private var showBodyShapeScoreOnHome: Bool = true
    @AppSetting(\.indicators.showCentralFatRiskOnHome) private var showCentralFatRiskOnHome: Bool = true

    // Legacy migration
    @AppSetting(\.indicators.showConicityOnHome) private var showConicityOnHome: Bool = true
    @AppSetting(\.health.healthIndicatorsV2Migrated) private var hasMigratedHealthIndicatorsV2: Bool = false

    #if DEBUG
    private var uiTestForcePremium: Bool { UITestArgument.isPresent(.forcePremium) }
    private var uiTestBypassHealthSummaryGuards: Bool { UITestArgument.isPresent(.bypassHealthSummaryGuards) }
    #endif

    let latestWaist: Double?
    let latestHeight: Double?
    let latestWeight: Double?
    let latestHips: Double?
    let latestBodyFat: Double?
    let latestLeanMass: Double?
    let weightDelta7dText: String?
    let waistDelta7dText: String?
    let displayMode: DisplayMode
    let title: String
    private let runSideEffects: Bool

    init(
        latestWaist: Double?,
        latestHeight: Double?,
        latestWeight: Double?,
        latestHips: Double? = nil,
        latestBodyFat: Double?,
        latestLeanMass: Double?,
        weightDelta7dText: String? = nil,
        waistDelta7dText: String? = nil,
        displayMode: DisplayMode = .full,
        title: String = "Health",
        runSideEffects: Bool = true
    ) {
        self.latestWaist = latestWaist
        self.latestHeight = latestHeight
        self.latestWeight = latestWeight
        self.latestHips = latestHips
        self.latestBodyFat = latestBodyFat
        self.latestLeanMass = latestLeanMass
        self.weightDelta7dText = weightDelta7dText
        self.waistDelta7dText = waistDelta7dText
        self.displayMode = displayMode
        self.title = title
        self.runSideEffects = runSideEffects
    }

    @State private var healthInsightText: String?
    @State private var isLoadingInsight = false

    private var userGender: Gender {
        Gender(rawValue: userGenderRaw) ?? .notSpecified
    }

    private var userAge: Int? {
        userAgeValue > 0 ? userAgeValue : nil
    }

    private var effectiveHeight: Double? {
        manualHeight > 0 ? manualHeight : latestHeight
    }

    private var whtrResult: HealthMetricsCalculator.WHtRResult? {
        HealthMetricsCalculator.calculateWHtR(waistCm: latestWaist, heightCm: effectiveHeight)
    }

    private var rfmResult: GenderDependentResult<HealthMetricsCalculator.RFMResult>? {
        HealthMetricsCalculator.calculateRFMWithGenderRequirement(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            gender: userGender
        )
    }

    private var bmiResult: HealthMetricsCalculator.BMIResult? {
        HealthMetricsCalculator.calculateBMI(weightKg: latestWeight, heightCm: effectiveHeight, age: userAge)
    }

    private var whrResult: GenderDependentResult<HealthMetricsCalculator.WHRResult>? {
        HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: latestWaist,
            hipsCm: latestHips,
            gender: userGender
        )
    }

    private var waistRiskResult: GenderDependentResult<HealthMetricsCalculator.WaistRiskResult>? {
        HealthMetricsCalculator.calculateWaistRisk(waistCm: latestWaist, gender: userGender)
    }

    private var absiResult: GenderDependentResult<HealthMetricsCalculator.ABSIResult>? {
        HealthMetricsCalculator.calculateABSIWithGenderRequirement(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            weightKg: latestWeight,
            gender: userGender
        )
    }

    private var bodyShapeScoreResult: GenderDependentResult<HealthMetricsCalculator.BodyShapeRiskResult>? {
        HealthMetricsCalculator.calculateBodyShapeRisk(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            weightKg: latestWeight,
            gender: userGender
        )
    }

    private var centralFatRiskResult: HealthMetricsCalculator.CentralFatRiskResult? {
        HealthMetricsCalculator.calculateCentralFatRisk(waistCm: latestWaist, heightCm: effectiveHeight)
    }

    private var hasAnyMetricEnabled: Bool {
        anyCoreMetricEnabled || anyBodyCompositionEnabled || anyDistributionEnabled || anyRiskEnabled
    }

    private var anyCoreMetricEnabled: Bool {
        showWHtROnHome || showRFMOnHome || showBMIOnHome
    }

    private var anyBodyCompositionEnabled: Bool {
        showBodyFatOnHome || showLeanMassOnHome
    }

    private var anyDistributionEnabled: Bool {
        showWHROnHome || showWaistRiskOnHome
    }

    private var anyRiskEnabled: Bool {
        showABSIOnHome || showBodyShapeScoreOnHome || showCentralFatRiskOnHome
    }

    private var missingMetrics: [String] {
        var missing: [String] = []
        if latestWaist == nil { missing.append("Waist") }
        if effectiveHeight == nil { missing.append("Height") }
        if latestWeight == nil { missing.append("Weight") }
        return missing
    }

    private var hasSummaryMeasurementData: Bool {
        [latestWeight, latestWaist, latestBodyFat, latestLeanMass].contains { value in
            guard let value else { return false }
            return value > 0
        }
    }

    private var supportsAppleIntelligence: Bool {
        premiumStore.isPremium && AppleIntelligenceSupport.isAvailable()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Text(AppLocalization.string(title))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Spacer()

                    if !hasAnyMetricEnabled {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                    .font(AppTypography.micro)
                                Text(AppLocalization.string("Settings"))
                                    .font(AppTypography.sectionAction)
                            }
                            .foregroundStyle(HealthIndicatorPalette.accent)
                        }
                    } else if !missingMetrics.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                                .font(AppTypography.micro)
                            Text(AppLocalization.string("Missing data"))
                                .font(AppTypography.sectionAction)
                        }
                        .foregroundStyle(HealthIndicatorPalette.accent)
                    }
                }
            }

            switch displayMode {
            case .summaryOnly:
                summaryContent
            case .indicatorsOnly:
                indicatorsContent
            case .full:
                VStack(spacing: 12) {
                    summaryContent
                    indicatorsContent
                }
            }
        }
        .task(id: healthInsightInput) {
            guard runSideEffects else {
                healthInsightText = nil
                isLoadingInsight = false
                return
            }
            await loadHealthInsightIfNeeded()
        }
        .onAppear {
            guard runSideEffects else { return }
            Task { @MainActor in
                migrateLegacyVisibilityIfNeeded()
            }
        }
    }

    private var effectivePremium: Bool {
        #if DEBUG
        premiumStore.isPremium || uiTestForcePremium
        #else
        premiumStore.isPremium
        #endif
    }

    private var bypassGuards: Bool {
        #if DEBUG
        uiTestBypassHealthSummaryGuards
        #else
        false
        #endif
    }

    @ViewBuilder
    private var summaryContent: some View {
        if !effectivePremium {
            EmptyView()
        } else if !AppleIntelligenceSupport.isAvailable() && !bypassGuards {
            Text(AppLocalization.string("AI Insights aren't available right now."))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        } else if !hasAnyMetricEnabled && !bypassGuards {
            Text(AppLocalization.string("Enable health indicators in Settings to generate your summary."))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        } else if !hasSummaryMeasurementData && !bypassGuards {
            Text(AppLocalization.string("AI summary needs measurement data. Add your first measurement to get personalized insights."))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(HealthIndicatorPalette.accent)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())

                    Text(healthInsightText ?? AppLocalization.string("Generating your health summary..."))
                        .font(AppTypography.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .redacted(reason: isLoadingInsight ? .placeholder : [])
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("home.health.ai.text")
                }

                HStack {
                    Text(AppLocalization.string("AI generated"))
                        .font(AppTypography.micro)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isLoadingInsight {
                        Button {
                            Task { await refreshHealthInsight() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(AppTypography.micro)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(AppLocalization.string("Refresh insight"))
                        .accessibilityIdentifier("home.health.ai.refresh")
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var indicatorsContent: some View {
        if !hasAnyMetricEnabled {
            noMetricsEnabledView
        } else {
            VStack(spacing: 12) {
                if !missingMetrics.isEmpty {
                    missingDataBanner
                }

                if anyCoreMetricEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Core indicators"),
                        icon: "heart.text.square.fill",
                        content: {
                            VStack(spacing: 8) {
                                if showWHtROnHome {
                                    if let whtrResult {
                                        let style = softCategoryStyle(whtrResult.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Waist-Height Ratio"),
                                            value: String(format: "%.2f", whtrResult.ratio),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: WHtRDetailView(result: whtrResult)
                                        )
                                    } else {
                                        missingMetricRow(kind: .whtr, title: AppLocalization.string("Waist-Height Ratio"))
                                    }
                                }

                                if showRFMOnHome {
                                    switch rfmResult {
                                    case .value(let rfm):
                                        let style = softCategoryStyle(rfm.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Relative Fat Mass"),
                                            value: String(format: "%.1f%%", rfm.rfm),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: RFMDetailView(result: rfm)
                                        )
                                    case .requiresGender:
                                        genderRequiredRow(title: AppLocalization.string("Relative Fat Mass"))
                                    case .none:
                                        missingMetricRow(kind: .rfm, title: AppLocalization.string("Relative Fat Mass"))
                                    }
                                }

                                if showBMIOnHome {
                                    if let bmiResult {
                                        let style = softCategoryStyle(bmiResult.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Body Mass Index"),
                                            value: String(format: "%.1f", bmiResult.bmi),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: BMIDetailView(result: bmiResult)
                                        )
                                    } else {
                                        missingMetricRow(kind: .bmi, title: AppLocalization.string("Body Mass Index"))
                                    }
                                }
                            }
                        }
                    )
                }

                if anyBodyCompositionEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Body composition"),
                        icon: "figure.stand",
                        content: {
                            VStack(spacing: 8) {
                                if showBodyFatOnHome {
                                    if let latestBodyFat {
                                        switch PhysiqueIndicatorsCalculator.classifyBodyFat(percent: latestBodyFat, gender: userGender) {
                                        case .value(let categorized):
                                            HealthMetricRow(
                                                title: AppLocalization.string("Body Fat Percentage"),
                                                value: String(format: "%.1f%%", latestBodyFat),
                                                category: AppLocalization.string(categorized.category.rawValue),
                                                categoryColor: categorized.category.color,
                                                destination: BodyFatDetailView(value: latestBodyFat, gender: userGender)
                                            )
                                        case .requiresGender:
                                            genderRequiredRow(title: AppLocalization.string("Body Fat Percentage"))
                                        case .none:
                                            missingMetricRow(kind: .bodyFat, title: AppLocalization.string("Body Fat Percentage"))
                                        }
                                    } else {
                                        missingMetricRow(kind: .bodyFat, title: AppLocalization.string("Body Fat Percentage"))
                                    }
                                }

                                if showLeanMassOnHome {
                                    if let leanMass = latestLeanMass {
                                        let display = formatWeight(leanMass)
                                        if let lbmPercent = leanMassPercentage() {
                                            let category = leanMassCategory(lbmPercent)
                                            HealthMetricRow(
                                                title: AppLocalization.string("Lean Body Mass"),
                                                value: String(format: "%.1f%%", lbmPercent),
                                                category: category.name,
                                                categoryColor: category.color,
                                                destination: LeanMassDetailView(
                                                    value: leanMass,
                                                    percentage: lbmPercent,
                                                    totalWeight: latestWeight,
                                                    age: userAge,
                                                    unitsSystem: unitsSystem
                                                )
                                            )
                                        } else {
                                            HealthMetricRow(
                                                title: AppLocalization.string("Lean Body Mass"),
                                                value: display,
                                                category: AppLocalization.string("From HealthKit"),
                                                categoryColor: "#3B82F6",
                                                destination: LeanMassDetailView(
                                                    value: leanMass,
                                                    percentage: nil,
                                                    totalWeight: latestWeight,
                                                    age: userAge,
                                                    unitsSystem: unitsSystem
                                                )
                                            )
                                        }
                                    } else {
                                        missingMetricRow(kind: .leanMass, title: AppLocalization.string("Lean Body Mass"))
                                    }
                                }
                            }
                        }
                    )
                }

                if anyDistributionEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Fat distribution"),
                        icon: "ruler",
                        content: {
                            VStack(spacing: 8) {
                                if showWHROnHome {
                                    switch whrResult {
                                    case .value(let whr):
                                        let style = softCategoryStyle(whr.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Waist-to-Hip Ratio"),
                                            value: String(format: "%.2f", whr.ratio),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: WHRDetailView(result: whr, gender: userGender)
                                        )
                                    case .requiresGender:
                                        genderRequiredRow(title: AppLocalization.string("Waist-to-Hip Ratio"))
                                    case .none:
                                        missingMetricRow(kind: .whr, title: AppLocalization.string("Waist-to-Hip Ratio"))
                                    }
                                }

                                if showWaistRiskOnHome {
                                    switch waistRiskResult {
                                    case .value(let risk):
                                        let style = softCategoryStyle(risk.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Waist circumference"),
                                            value: formatLength(risk.waistCm, kind: .waist),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: WaistRiskDetailView(result: risk, unitsSystem: unitsSystem)
                                        )
                                    case .requiresGender:
                                        genderRequiredRow(title: AppLocalization.string("Waist circumference"))
                                    case .none:
                                        missingMetricRow(kind: .waistRisk, title: AppLocalization.string("Waist circumference"))
                                    }
                                }
                            }
                        }
                    )
                }

                if anyRiskEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Risk signals"),
                        icon: "exclamationmark.shield.fill",
                        content: {
                            VStack(spacing: 8) {
                                if showABSIOnHome {
                                    switch absiResult {
                                    case .value(let absi):
                                        let style = softCategoryStyle(absi.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("ABSI (technical)"),
                                            value: String(format: "%.3f", absi.absi),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: ABSIDetailView(result: absi)
                                        )
                                    case .requiresGender:
                                        genderRequiredRow(title: AppLocalization.string("ABSI (technical)"))
                                    case .none:
                                        missingMetricRow(kind: .absi, title: AppLocalization.string("ABSI (technical)"))
                                    }
                                }

                                if showBodyShapeScoreOnHome {
                                    switch bodyShapeScoreResult {
                                    case .value(let score):
                                        let style = softCategoryStyle(score.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Body Shape Risk"),
                                            value: String(format: "%.2f", score.score),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: BodyShapeRiskScoreDetailView(result: score)
                                        )
                                    case .requiresGender:
                                        genderRequiredRow(title: AppLocalization.string("Body Shape Risk"))
                                    case .none:
                                        missingMetricRow(kind: .bodyShapeScore, title: AppLocalization.string("Body Shape Risk"))
                                    }
                                }

                                if showCentralFatRiskOnHome {
                                    if let centralFatRiskResult {
                                        let style = softCategoryStyle(centralFatRiskResult.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Central Fat Risk"),
                                            value: String(format: "%.2f", centralFatRiskResult.score),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: CentralFatRiskDetailView(result: centralFatRiskResult)
                                        )
                                    } else {
                                        missingMetricRow(kind: .centralFatRisk, title: AppLocalization.string("Central Fat Risk"))
                                    }
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private func migrateLegacyVisibilityIfNeeded() {
        guard !hasMigratedHealthIndicatorsV2 else { return }

        let defaults = AppSettingsStore.shared
        if defaults.object(forKey: AppSettingsKeys.Indicators.showCentralFatRiskOnHome) == nil {
            showCentralFatRiskOnHome = showConicityOnHome
        }
        if defaults.object(forKey: AppSettingsKeys.Indicators.showBodyShapeScoreOnHome) == nil {
            showBodyShapeScoreOnHome = showABSIOnHome
        }
        hasMigratedHealthIndicatorsV2 = true
    }

    private func formatWeight(_ kg: Double) -> String {
        if unitsSystem == "imperial" {
            return String(format: "%.1f lb", kg * 2.20462)
        }
        return String(format: "%.1f kg", kg)
    }

    private func leanMassPercentage() -> Double? {
        guard let leanMass = latestLeanMass, let weight = latestWeight, weight > 0 else { return nil }
        return (leanMass / weight) * 100.0
    }

    private func leanMassCategory(_ lbmPercent: Double) -> (name: String, color: String) {
        guard let age = userAge else {
            return lbmPercent >= 80
                ? (AppLocalization.string("In range"), AppColorRoles.stateSuccessHex)
                : (AppLocalization.string("Below range"), AppColorRoles.stateInfoHex)
        }

        if age >= 19 && age <= 39 {
            if lbmPercent >= 80 && lbmPercent <= 92 { return (AppLocalization.string("In range"), AppColorRoles.stateSuccessHex) }
            if lbmPercent > 92 { return (AppLocalization.string("Above range"), AppColorRoles.stateWarningHex) }
            return (AppLocalization.string("Below range"), AppColorRoles.stateInfoHex)
        }
        if age >= 40 && age <= 59 {
            if lbmPercent >= 78 && lbmPercent <= 89 { return (AppLocalization.string("In range"), AppColorRoles.stateSuccessHex) }
            if lbmPercent > 89 { return (AppLocalization.string("Above range"), AppColorRoles.stateWarningHex) }
            return (AppLocalization.string("Below range"), AppColorRoles.stateInfoHex)
        }
        if lbmPercent >= 75 && lbmPercent <= 87 { return (AppLocalization.string("In range"), AppColorRoles.stateSuccessHex) }
        if lbmPercent > 87 { return (AppLocalization.string("Above range"), AppColorRoles.stateWarningHex) }
        return (AppLocalization.string("Below range"), AppColorRoles.stateInfoHex)
    }

    private var missingDataBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HealthIndicatorPalette.accent)
                Text(AppLocalization.string("Missing data"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }
            Text(AppLocalization.string("To calculate all indicators, add:"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
            ForEach(missingMetrics, id: \.self) { metric in
                Text("• \(AppLocalization.string(metric))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    private enum MissingIndicatorKind {
        case whtr
        case rfm
        case bmi
        case bodyFat
        case leanMass
        case whr
        case waistRisk
        case absi
        case bodyShapeScore
        case centralFatRisk
    }

    private func formatLength(_ cm: Double, kind: MetricKind) -> String {
        kind.formattedMetricValue(fromMetric: cm, unitsSystem: unitsSystem)
    }

    @ViewBuilder
    private func missingMetricRow(kind: MissingIndicatorKind, title: String) -> some View {
        HealthMetricRow(
            title: title,
            value: "—",
            category: AppLocalization.string("Add data"),
            categoryColor: HealthIndicatorPalette.placeholderHex,
            destination: HealthIndicatorMissingDataView(indicatorTitle: title, missingItems: missingInputs(for: kind))
        )
    }

    @ViewBuilder
    private func genderRequiredRow(title: String) -> some View {
        HealthMetricRow(
            title: title,
            value: "—",
            category: AppLocalization.string("Set gender"),
            categoryColor: HealthIndicatorPalette.placeholderHex,
            destination: GenderRequiredIndicatorView(indicatorTitle: title)
        )
    }

    private func missingInputs(for kind: MissingIndicatorKind) -> [String] {
        func appendIfMissing(_ value: Double?, key: String, into list: inout [String]) {
            if value == nil { list.append(AppLocalization.string(key)) }
        }

        var items: [String] = []

        switch kind {
        case .whtr:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
            appendIfMissing(effectiveHeight, key: "Height", into: &items)
        case .rfm:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
            appendIfMissing(effectiveHeight, key: "Height", into: &items)
        case .bmi:
            appendIfMissing(latestWeight, key: "Weight", into: &items)
            appendIfMissing(effectiveHeight, key: "Height", into: &items)
        case .bodyFat:
            appendIfMissing(latestBodyFat, key: "Body Fat Percentage", into: &items)
        case .leanMass:
            appendIfMissing(latestLeanMass, key: "Lean Body Mass", into: &items)
        case .whr:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
            appendIfMissing(latestHips, key: "Hips", into: &items)
        case .waistRisk:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
        case .absi, .bodyShapeScore:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
            appendIfMissing(effectiveHeight, key: "Height", into: &items)
            appendIfMissing(latestWeight, key: "Weight", into: &items)
        case .centralFatRisk:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
            appendIfMissing(effectiveHeight, key: "Height", into: &items)
        }

        return items
    }

    private var healthInsightInput: HealthInsightInput? {
        guard displayMode != .indicatorsOnly else { return nil }
        guard effectivePremium else { return nil }
        guard supportsAppleIntelligence || bypassGuards else { return nil }
        guard hasAnyMetricEnabled || bypassGuards else { return nil }
        guard hasSummaryMeasurementData || bypassGuards else { return nil }

        var coreRFM: String?
        if case .value(let rfm) = rfmResult {
            coreRFM = String(format: "%.1f%%", rfm.rfm)
        }

        return HealthInsightInput(
            userName: userName.isEmpty ? nil : userName,
            ageText: userAge.map { "\($0)" },
            genderText: userGender.rawValue,
            latestWeightText: latestWeight.map { formatWeight($0) },
            latestWaistText: latestWaist.map { formatLength($0, kind: .waist) },
            latestBodyFatText: latestBodyFat.map { String(format: "%.1f%%", $0) },
            latestLeanMassText: latestLeanMass.map { formatWeight($0) },
            weightDelta7dText: weightDelta7dText,
            waistDelta7dText: waistDelta7dText,
            coreWHtRText: whtrResult.map { String(format: "%.2f", $0.ratio) },
            coreBMIText: bmiResult.map { String(format: "%.1f", $0.bmi) },
            coreRFMText: coreRFM
        )
    }

    private func softCategoryStyle(_ raw: String) -> (name: String, color: String) {
        switch raw.lowercased() {
        case "low risk":
            return (AppLocalization.string("Excellence"), AppColorRoles.stateSuccessHex)
        case "moderate risk":
            return (AppLocalization.string("Keep steady"), AppColorRoles.stateWarningHex)
        case "high risk":
            return (AppLocalization.string("Worth attention"), AppColorRoles.stateErrorHex)
        case "increased risk":
            return (AppLocalization.string("Worth attention"), AppColorRoles.stateWarningHex)
        case "underweight":
            return (AppLocalization.string("Building up"), AppColorRoles.stateInfoHex)
        case "normal weight":
            return (AppLocalization.string("On track"), AppColorRoles.stateSuccessHex)
        case "high weight", "overweight":
            return (AppLocalization.string("Room to improve"), AppColorRoles.stateWarningHex)
        case "obese":
            return (AppLocalization.string("Focus area"), AppColorRoles.stateErrorHex)
        case "normal fat level":
            return (AppLocalization.string("On track"), AppColorRoles.stateSuccessHex)
        case "high fat level":
            return (AppLocalization.string("Focus area"), AppColorRoles.stateErrorHex)
        case "low":
            return (AppLocalization.string("Excellence"), AppColorRoles.stateSuccessHex)
        case "moderate":
            return (AppLocalization.string("Keep steady"), AppColorRoles.stateWarningHex)
        case "high":
            return (AppLocalization.string("Worth attention"), AppColorRoles.stateErrorHex)
        case "optimal":
            return (AppLocalization.string("Excellence"), AppColorRoles.stateSuccessHex)
        case "elevated":
            return (AppLocalization.string("Room to improve"), AppColorRoles.stateWarningHex)
        default:
            return (AppLocalization.string(raw), AppColorRoles.stateInfoHex)
        }
    }

    @MainActor
    private func refreshHealthInsight() async {
        guard let input = healthInsightInput else { return }
        await MetricInsightService.shared.invalidateHealth()
        isLoadingInsight = true
        healthInsightText = await MetricInsightService.shared.generateHealthInsight(for: input)
        isLoadingInsight = false
    }

    @MainActor
    private func loadHealthInsightIfNeeded() async {
        guard let input = healthInsightInput else {
            healthInsightText = nil
            isLoadingInsight = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(650))
        } catch {
            isLoadingInsight = false
            return
        }
        guard !Task.isCancelled else {
            isLoadingInsight = false
            return
        }

        isLoadingInsight = true
        healthInsightText = await MetricInsightService.shared.generateHealthInsight(for: input)
        isLoadingInsight = false
    }

    private var noMetricsEnabledView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(HealthIndicatorPalette.accent)

                Text(AppLocalization.string("No indicators selected"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }

            Text(AppLocalization.string("Enable health indicators in Settings to see results here."))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)

            NavigationLink {
                SettingsView()
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text(AppLocalization.string("Go to Settings"))
                }
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(Color.white.opacity(0.98))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(healthAccentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HealthIndicatorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(HealthIndicatorPalette.accent.opacity(0.34), lineWidth: 1)
        )
    }
}

private struct HealthIndicatorMissingDataView: View {
    @EnvironmentObject private var router: AppRouter
    let indicatorTitle: String
    let missingItems: [String]

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 320, tint: HealthIndicatorPalette.accent.opacity(0.24))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(indicatorTitle)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("To calculate this indicator, add:"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)
                        ForEach(missingItems, id: \.self) { item in
                            Text("• \(item)")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColorRoles.surfaceInteractive)
                    )

                    Button {
                        Haptics.light()
                        router.presentedSheet = .composer(mode: .newPost)
                    } label: {
                        Text(AppLocalization.string("Add measurement"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color.white.opacity(0.98))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(healthAccentGradient, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(indicatorTitle)
        .healthIndicatorDetailNavigationStyle()
    }
}

private struct GenderRequiredIndicatorView: View {
    let indicatorTitle: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 320, tint: HealthIndicatorPalette.accent.opacity(0.22))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(indicatorTitle)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string("Set your gender in Profile to unlock this indicator and its ranges."))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Text(AppLocalization.string("Open profile settings"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color.white.opacity(0.98))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(healthAccentGradient, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .navigationTitle(indicatorTitle)
        .healthIndicatorDetailNavigationStyle()
    }
}

private struct CentralFatRiskDetailView: View {
    let result: HealthMetricsCalculator.CentralFatRiskResult

    var body: some View {
        simpleDetail(
            title: AppLocalization.string("Central Fat Risk"),
            value: String(format: "%.2f", result.score),
            category: AppLocalization.string(result.category.rawValue),
            categoryColor: result.category.color,
            formula: "CFR = WHtR / 0.50",
            notes: AppLocalization.string("A simple scale based on WHtR where 1.00 is the core threshold."),
            ranges: [
                (AppLocalization.string("Low risk"), "< 1.00", AppColorRoles.stateSuccessHex),
                (AppLocalization.string("Moderate risk"), "1.00 - 1.20", AppColorRoles.stateWarningHex),
                (AppLocalization.string("High risk"), "> 1.20", AppColorRoles.stateErrorHex)
            ]
        )
    }

    private func simpleDetail(
        title: String,
        value: String,
        category: String,
        categoryColor: String,
        formula: String,
        notes: String,
        ranges: [(String, String, String)]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(value)
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(category)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.bestAccessibleTextColor(onHex: categoryColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: categoryColor), in: RoundedRectangle(cornerRadius: 8))

                Text(formula)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(notes)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)

                ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                    HStack {
                        Circle().fill(Color(hex: range.2)).frame(width: 9, height: 9)
                        Text(range.0)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Spacer()
                        Text(range.1)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                }
            }
            .padding(16)
        }
        .background(AppColorRoles.surfaceCanvas.ignoresSafeArea())
        .navigationTitle(title)
        .healthIndicatorDetailNavigationStyle()
    }
}

private struct BodyShapeRiskScoreDetailView: View {
    let result: HealthMetricsCalculator.BodyShapeRiskResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "%.2f", result.score))
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string(result.category.rawValue))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.bestAccessibleTextColor(onHex: result.category.color))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: result.category.color), in: RoundedRectangle(cornerRadius: 8))

                Text("z-score: \(String(format: "%.2f", result.zScore))")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Text(AppLocalization.string("Body Shape Risk in this app is standardized ABSI (z-score), not an arbitrary composite."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string("Reference interpretation"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    rangeRow(color: AppColorRoles.stateSuccessHex, title: AppLocalization.string("Low risk"), value: "z < -0.272")
                    rangeRow(color: AppColorRoles.stateWarningHex, title: AppLocalization.string("Moderate risk"), value: "-0.272 ... 0.229")
                    rangeRow(color: AppColorRoles.stateErrorHex, title: AppLocalization.string("High risk"), value: "z > 0.229")
                }
                .padding(12)
                .background(AppColorRoles.surfaceInteractive, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .background(AppColorRoles.surfaceCanvas.ignoresSafeArea())
        .navigationTitle(AppLocalization.string("Body Shape Risk"))
        .healthIndicatorDetailNavigationStyle()
    }

    private func rangeRow(color: String, title: String, value: String) -> some View {
        HStack {
            Circle().fill(Color(hex: color)).frame(width: 9, height: 9)
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
            Spacer()
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
        }
    }
}

private struct WaistRiskDetailView: View {
    let result: HealthMetricsCalculator.WaistRiskResult
    let unitsSystem: String

    var body: some View {
        let display = MetricKind.waist.valueForDisplay(fromMetric: result.waistCm, unitsSystem: unitsSystem)
        let unit = MetricKind.waist.unitSymbol(unitsSystem: unitsSystem)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "%.1f %@", display, unit))
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string(result.category.rawValue))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.bestAccessibleTextColor(onHex: result.category.color))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: result.category.color), in: RoundedRectangle(cornerRadius: 8))

                Text(AppLocalization.string("Waist circumference is a direct marker of central fat distribution."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    if result.gender == .male {
                        row(title: AppLocalization.string("Low risk"), value: "<= 94 cm", color: AppColorRoles.stateSuccessHex)
                        row(title: AppLocalization.string("Moderate risk"), value: "> 94 - 102 cm", color: AppColorRoles.stateWarningHex)
                        row(title: AppLocalization.string("High risk"), value: "> 102 cm", color: AppColorRoles.stateErrorHex)
                    } else {
                        row(title: AppLocalization.string("Low risk"), value: "<= 80 cm", color: AppColorRoles.stateSuccessHex)
                        row(title: AppLocalization.string("Moderate risk"), value: "> 80 - 88 cm", color: AppColorRoles.stateWarningHex)
                        row(title: AppLocalization.string("High risk"), value: "> 88 cm", color: AppColorRoles.stateErrorHex)
                    }
                }
                .padding(12)
                .background(AppColorRoles.surfaceInteractive, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .background(AppColorRoles.surfaceCanvas.ignoresSafeArea())
        .navigationTitle(AppLocalization.string("Waist circumference"))
        .healthIndicatorDetailNavigationStyle()
    }

    private func row(title: String, value: String, color: String) -> some View {
        HStack {
            Circle().fill(Color(hex: color)).frame(width: 9, height: 9)
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
            Spacer()
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
        }
    }
}

private extension View {
    func healthIndicatorDetailNavigationStyle() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
