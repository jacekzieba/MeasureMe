// HealthMetricsSection.swift
//
// **HealthMetricsSection**
// Sekcje wyświetlające wskaźniki zdrowotne na ekranie Home.
//
// **Podział na sekcje:**
// - Core Metrics: WHtR, RFM, BMI
// - Body Composition: Body Fat %, Lean Body Mass (z HealthKit)
// - Risk Indicators: Body Shape Risk (ABSI), Central Fat Risk (Conicity)
//
// **Funkcje:**
// - Obliczanie wskaźników na podstawie aktualnych pomiarów
// - BMI uwzględnia wiek użytkownika
// - Wyświetlanie kategorii z kolorowym tłem
// - Każda sekcja jako jedna kafelka z listą metryk wewnątrz
// - Nawigacja do szczegółowych widoków dla poszczególnych metryk
// - Możliwość pokazania/ukrycia każdej metryki w ustawieniach
//
import SwiftUI
import SwiftData

struct HealthMetricsSection: View {
    enum DisplayMode {
        case summaryOnly
        case indicatorsOnly
        case full
    }

    @AppStorage("userName") private var userName: String = ""
    @EnvironmentObject private var premiumStore: PremiumStore
    @AppStorage("userGender") private var userGenderRaw: String = "notSpecified"
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    @AppStorage("userAge") private var userAgeValue: Int = 0

    // Core Metrics visibility
    @AppStorage("showWHtROnHome") private var showWHtROnHome: Bool = true
    @AppStorage("showRFMOnHome") private var showRFMOnHome: Bool = true
    @AppStorage("showBMIOnHome") private var showBMIOnHome: Bool = true

    // Body Composition visibility
    @AppStorage("showBodyFatOnHome") private var showBodyFatOnHome: Bool = true
    @AppStorage("showLeanMassOnHome") private var showLeanMassOnHome: Bool = true

    // Risk Indicators visibility
    @AppStorage("showABSIOnHome") private var showABSIOnHome: Bool = true
    @AppStorage("showConicityOnHome") private var showConicityOnHome: Bool = true

    #if DEBUG
    private var uiTestForcePremium: Bool { ProcessInfo.processInfo.arguments.contains("-uiTestForcePremium") }
    private var uiTestBypassHealthSummaryGuards: Bool { ProcessInfo.processInfo.arguments.contains("-uiTestBypassHealthSummaryGuards") }
    #endif

    let latestWaist: Double?
    let latestHeight: Double?
    let latestWeight: Double?
    let latestBodyFat: Double?
    let latestLeanMass: Double?
    let displayMode: DisplayMode
    let title: String

    init(
        latestWaist: Double?,
        latestHeight: Double?,
        latestWeight: Double?,
        latestBodyFat: Double?,
        latestLeanMass: Double?,
        displayMode: DisplayMode = .full,
        title: String = "Health"
    ) {
        self.latestWaist = latestWaist
        self.latestHeight = latestHeight
        self.latestWeight = latestWeight
        self.latestBodyFat = latestBodyFat
        self.latestLeanMass = latestLeanMass
        self.displayMode = displayMode
        self.title = title
    }

    @Query(sort: [SortDescriptor(\MetricSample.date, order: .forward)])
    private var samples: [MetricSample]

    @State private var healthInsightText: String?
    @State private var isLoadingInsight = false

    private var userGender: Gender {
        Gender(rawValue: userGenderRaw) ?? .notSpecified
    }

    // Wiek użytkownika
    private var userAge: Int? {
        userAgeValue > 0 ? userAgeValue : nil
    }

    // Użyj manualnego wzrostu jako priorytet (jeśli ustawiony), inaczej tracked
    private var effectiveHeight: Double? {
        if manualHeight > 0 {
            return manualHeight
        }
        return latestHeight
    }

    // MARK: - Core Metrics

    private var whtrResult: HealthMetricsCalculator.WHtRResult? {
        HealthMetricsCalculator.calculateWHtR(waistCm: latestWaist, heightCm: effectiveHeight)
    }

    private var rfmResult: HealthMetricsCalculator.RFMResult? {
        HealthMetricsCalculator.calculateRFM(waistCm: latestWaist, heightCm: effectiveHeight, gender: userGender)
    }

    private var bmiResult: HealthMetricsCalculator.BMIResult? {
        HealthMetricsCalculator.calculateBMI(weightKg: latestWeight, heightCm: effectiveHeight, age: userAge)
    }

    private var hasCoreMetrics: Bool {
        (showWHtROnHome && whtrResult != nil) ||
        (showRFMOnHome && rfmResult != nil) ||
        (showBMIOnHome && bmiResult != nil)
    }

    private var anyCoreMetricEnabled: Bool {
        showWHtROnHome || showRFMOnHome || showBMIOnHome
    }

    // MARK: - Body Composition

    private var hasBodyComposition: Bool {
        (showBodyFatOnHome && latestBodyFat != nil) ||
        (showLeanMassOnHome && latestLeanMass != nil)
    }

    private var anyBodyCompositionEnabled: Bool {
        showBodyFatOnHome || showLeanMassOnHome
    }

    // MARK: - Risk Indicators

    private var absiResult: HealthMetricsCalculator.ABSIResult? {
        HealthMetricsCalculator.calculateABSI(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            weightKg: latestWeight,
            gender: userGender
        )
    }

    private var conicityResult: HealthMetricsCalculator.ConicityResult? {
        HealthMetricsCalculator.calculateConicity(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            weightKg: latestWeight,
            gender: userGender
        )
    }

    private var hasRiskIndicators: Bool {
        (showABSIOnHome && absiResult != nil) ||
        (showConicityOnHome && conicityResult != nil)
    }

    private var anyRiskIndicatorEnabled: Bool {
        showABSIOnHome || showConicityOnHome
    }

    // MARK: - Missing Data

    private var missingMetrics: [String] {
        HealthMetricsCalculator.missingMetrics(
            waist: latestWaist,
            height: effectiveHeight,
            weight: latestWeight
        )
    }

    private var hasAnyMetricEnabled: Bool {
        anyCoreMetricEnabled || anyBodyCompositionEnabled || anyRiskIndicatorEnabled
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
                        .foregroundStyle(.white)

                    Spacer()

                    if !hasAnyMetricEnabled {
                        // Link do ustawień jeśli żadna metryka nie jest włączona
                        NavigationLink {
                            SettingsView()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                    .font(AppTypography.micro)
                                Text(AppLocalization.string("Settings"))
                                    .font(AppTypography.sectionAction)
                            }
                            .foregroundStyle(Color(hex: "#FCA311"))
                        }
                    } else if !missingMetrics.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                                .font(AppTypography.micro)
                            Text(AppLocalization.string("Missing data"))
                                .font(AppTypography.sectionAction)
                        }
                        .foregroundStyle(Color(hex: "#FCA311"))
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
            await loadHealthInsightIfNeeded()
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
                        .foregroundStyle(Color(hex: "#FCA311"))
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

                Text(AppLocalization.string("AI generated"))
                    .font(AppTypography.micro)
                    .foregroundStyle(.secondary)
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

                // Sekcja wskaznikow glownych
                if anyCoreMetricEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Core indicators"),
                        icon: "heart.text.square.fill",
                        content: {
                            VStack(spacing: 8) {
                                if showWHtROnHome {
                                    if let whtr = whtrResult {
                                        let style = softCategoryStyle(whtr.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Waist-Height Ratio"),
                                            value: String(format: "%.2f", whtr.ratio),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: WHtRDetailView(result: whtr)
                                        )
                                    } else {
                                        missingMetricRow(kind: .whtr, title: AppLocalization.string("Waist-Height Ratio"))
                                    }
                                }

                                if showRFMOnHome {
                                    if let rfm = rfmResult {
                                        let style = softCategoryStyle(rfm.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Relative Fat Mass"),
                                            value: String(format: "%.1f%%", rfm.rfm),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: RFMDetailView(result: rfm)
                                        )
                                    } else {
                                        missingMetricRow(kind: .rfm, title: AppLocalization.string("Relative Fat Mass"))
                                    }
                                }

                                if showBMIOnHome {
                                    if let bmi = bmiResult {
                                        let style = softCategoryStyle(bmi.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Body Mass Index"),
                                            value: String(format: "%.1f", bmi.bmi),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: BMIDetailView(result: bmi)
                                        )
                                    } else {
                                        missingMetricRow(kind: .bmi, title: AppLocalization.string("Body Mass Index"))
                                    }
                                }
                            }
                        }
                    )
                }

                // Sekcja skladu ciala
                if anyBodyCompositionEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Body composition"),
                        icon: "figure.stand",
                        content: {
                            VStack(spacing: 8) {
                                if showBodyFatOnHome {
                                    if let bodyFat = latestBodyFat {
                                        let category = bodyFatCategory(bodyFat)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Body Fat Percentage"),
                                            value: String(format: "%.1f%%", bodyFat),
                                            category: category.name,
                                            categoryColor: category.color,
                                            destination: BodyFatDetailView(value: bodyFat, gender: userGender)
                                        )
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

                // Sekcja sygnalow ryzyka
                if anyRiskIndicatorEnabled {
                    HealthMetricsSectionCard(
                        title: AppLocalization.string("Risk signals"),
                        icon: "exclamationmark.shield.fill",
                        content: {
                            VStack(spacing: 8) {
                                if showABSIOnHome {
                                    if let absi = absiResult {
                                        let style = softCategoryStyle(absi.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Body Shape Risk"),
                                            value: String(format: "%.3f", absi.absi),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: ABSIDetailView(result: absi)
                                        )
                                    } else {
                                        missingMetricRow(kind: .absi, title: AppLocalization.string("Body Shape Risk"))
                                    }
                                }

                                if showConicityOnHome {
                                    if let conicity = conicityResult {
                                        let style = softCategoryStyle(conicity.category.rawValue)
                                        HealthMetricRow(
                                            title: AppLocalization.string("Central Fat Risk"),
                                            value: String(format: "%.2f", conicity.conicity),
                                            category: style.name,
                                            categoryColor: style.color,
                                            destination: ConicityDetailView(result: conicity)
                                        )
                                    } else {
                                        missingMetricRow(kind: .conicity, title: AppLocalization.string("Central Fat Risk"))
                                    }
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func formatWeight(_ kg: Double) -> String {
        if unitsSystem == "imperial" {
            let lbs = kg * 2.20462
            return String(format: "%.1f lb", lbs)
        } else {
            return String(format: "%.1f kg", kg)
        }
    }

    /// Oblicza procent beztłuszczowej masy ciała (LBM%)
    private func leanMassPercentage() -> Double? {
        guard let leanMass = latestLeanMass, let weight = latestWeight, weight > 0 else {
            return nil
        }
        return (leanMass / weight) * 100.0
    }

    /// Kategoryzuje LBM% na podstawie wieku
    private func leanMassCategory(_ lbmPercent: Double) -> (name: String, color: String) {
        guard let age = userAge else {
            // Bez wieku używamy zakresów dla młodych dorosłych
            if lbmPercent >= 80 { return (AppLocalization.string("In range"), "#34D399") }
            else { return (AppLocalization.string("Below range"), "#60A5FA") }
        }

        // Zakresy zależą od wieku
        if age >= 19 && age <= 39 {
            // 19-39 lat
            if lbmPercent >= 80 && lbmPercent <= 92 { return (AppLocalization.string("In range"), "#34D399") }
            else if lbmPercent > 92 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Below range"), "#60A5FA") }
        } else if age >= 40 && age <= 59 {
            // 40-59 lat
            if lbmPercent >= 78 && lbmPercent <= 89 { return (AppLocalization.string("In range"), "#34D399") }
            else if lbmPercent > 89 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Below range"), "#60A5FA") }
        } else if age >= 60 && age <= 79 {
            // 60-79 lat
            if lbmPercent >= 75 && lbmPercent <= 87 { return (AppLocalization.string("In range"), "#34D399") }
            else if lbmPercent > 87 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Below range"), "#60A5FA") }
        } else {
            // Poniżej 19 lub powyżej 79 - używamy zakresów 60-79
            if lbmPercent >= 75 && lbmPercent <= 87 { return (AppLocalization.string("In range"), "#34D399") }
            else if lbmPercent > 87 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Below range"), "#60A5FA") }
        }
    }

    private var missingDataBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: "#FCA311"))
                Text(AppLocalization.string("Missing data"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            Text(AppLocalization.string("To calculate all indicators, add:"))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            ForEach(missingMetrics, id: \.self) { metric in
                Text("• \(AppLocalization.string(metric))")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private enum MissingIndicatorKind {
        case whtr
        case rfm
        case bmi
        case bodyFat
        case leanMass
        case absi
        case conicity
    }

    @ViewBuilder
    private func missingMetricRow(kind: MissingIndicatorKind, title: String) -> some View {
        HealthMetricRow(
            title: title,
            value: "—",
            category: AppLocalization.string("Add data"),
            categoryColor: "#FCA311",
            destination: HealthIndicatorMissingDataView(
                indicatorTitle: title,
                missingItems: missingInputs(for: kind)
            )
        )
    }

    private func missingInputs(for kind: MissingIndicatorKind) -> [String] {
        func appendIfMissing(_ value: Double?, key: String, into list: inout [String]) {
            if value == nil {
                list.append(AppLocalization.string(key))
            }
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
        case .absi, .conicity:
            appendIfMissing(latestWaist, key: "Waist", into: &items)
            appendIfMissing(effectiveHeight, key: "Height", into: &items)
            appendIfMissing(latestWeight, key: "Weight", into: &items)
        }

        if items.isEmpty {
            return missingMetrics.map { AppLocalization.string($0) }
        }
        return items
    }

    private func bodyFatCategory(_ percent: Double) -> (name: String, color: String) {
        // Kategorie zależą od płci
        switch userGender {
        case .male:
            if percent < 10 { return (AppLocalization.string("Lean range"), "#60A5FA") }
            else if percent < 20 { return (AppLocalization.string("In range"), "#34D399") }
            else if percent < 25 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Higher range"), "#F97316") }
        case .female:
            if percent < 20 { return (AppLocalization.string("Lean range"), "#60A5FA") }
            else if percent < 30 { return (AppLocalization.string("In range"), "#34D399") }
            else if percent < 35 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Higher range"), "#F97316") }
        case .notSpecified:
            if percent < 15 { return (AppLocalization.string("Lean range"), "#60A5FA") }
            else if percent < 25 { return (AppLocalization.string("In range"), "#34D399") }
            else if percent < 30 { return (AppLocalization.string("Above range"), "#FCA311") }
            else { return (AppLocalization.string("Higher range"), "#F97316") }
        }
    }

    private var healthInsightInput: HealthInsightInput? {
        guard displayMode != .indicatorsOnly else { return nil }
        guard effectivePremium else { return nil }
        guard supportsAppleIntelligence || bypassGuards else { return nil }
        guard hasAnyMetricEnabled || bypassGuards else { return nil }
        guard hasSummaryMeasurementData || bypassGuards else { return nil }

        return HealthInsightInput(
            userName: userName.isEmpty ? nil : userName,
            ageText: userAge.map { "\($0)" },
            genderText: userGender.rawValue,
            latestWeightText: latestWeight.map { formatWeight($0) },
            latestWaistText: latestWaist.map { formatLength($0, kind: .waist) },
            latestBodyFatText: latestBodyFat.map { String(format: "%.1f%%", $0) },
            latestLeanMassText: latestLeanMass.map { formatWeight($0) },
            weightDelta7dText: metricDeltaText(kind: .weight, days: 7),
            waistDelta7dText: metricDeltaText(kind: .waist, days: 7),
            coreWHtRText: whtrResult.map { String(format: "%.2f", $0.ratio) },
            coreBMIText: bmiResult.map { String(format: "%.1f", $0.bmi) },
            coreRFMText: rfmResult.map { String(format: "%.1f%%", $0.rfm) }
        )
    }

    private func formatLength(_ cm: Double, kind: MetricKind) -> String {
        let display = kind.valueForDisplay(fromMetric: cm, unitsSystem: unitsSystem)
        return String(format: "%.1f %@", display, kind.unitSymbol(unitsSystem: unitsSystem))
    }

    private func metricDeltaText(kind: MetricKind, days: Int) -> String? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return nil }
        let kindSamples = samples.filter { $0.kindRaw == kind.rawValue && $0.date >= start }
        guard let first = kindSamples.first, let last = kindSamples.last, first.persistentModelID != last.persistentModelID else {
            return nil
        }
        let firstValue = kind.valueForDisplay(fromMetric: first.value, unitsSystem: unitsSystem)
        let lastValue = kind.valueForDisplay(fromMetric: last.value, unitsSystem: unitsSystem)
        let delta = lastValue - firstValue
        return String(format: "%+.1f %@", delta, kind.unitSymbol(unitsSystem: unitsSystem))
    }

    private func softCategoryStyle(_ raw: String) -> (name: String, color: String) {
        let normalized = raw.lowercased()
        switch normalized {
        case "low risk": return (AppLocalization.string("Excellence"), "#22C55E")
        case "moderate risk": return (AppLocalization.string("Keep steady"), "#FCA311")
        case "high risk": return (AppLocalization.string("Worth attention"), "#F97316")
        case "underweight": return (AppLocalization.string("Building up"), "#60A5FA")
        case "normal weight": return (AppLocalization.string("On track"), "#34D399")
        case "high weight": return (AppLocalization.string("Room to improve"), "#FCA311")
        case "overweight": return (AppLocalization.string("Room to improve"), "#FCA311")
        case "obese": return (AppLocalization.string("Focus area"), "#F97316")
        case "normal fat level": return (AppLocalization.string("On track"), "#34D399")
        case "high fat level": return (AppLocalization.string("Focus area"), "#F97316")
        case "low": return (AppLocalization.string("Building up"), "#60A5FA")
        case "high": return (AppLocalization.string("Focus area"), "#F97316")
        case "optimal": return (AppLocalization.string("Excellence"), "#22C55E")
        case "elevated": return (AppLocalization.string("Room to improve"), "#FCA311")
        default: return (AppLocalization.string(raw), "#FCA311")
        }
    }

    @MainActor
    private func loadHealthInsightIfNeeded() async {
        guard let input = healthInsightInput else {
            healthInsightText = nil
            isLoadingInsight = false
            return
        }

        isLoadingInsight = true
        healthInsightText = await MetricInsightService.shared.generateHealthInsight(for: input)
        isLoadingInsight = false
    }

    // MARK: - Missing Data Views

    private var noMetricsEnabledView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#FCA311"))

                Text(AppLocalization.string("No indicators selected"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }

            Text(AppLocalization.string("Enable health indicators in Settings to see results here."))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.8))

            NavigationLink {
                SettingsView()
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text(AppLocalization.string("Go to Settings"))
                }
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "#FCA311"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#1C1C1E"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var missingDataView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#FCA311"))

                Text(AppLocalization.string("Missing data"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }

            Text(AppLocalization.string("To calculate health metrics, please add:"))
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.8))

            ForEach(missingMetrics, id: \.self) { metric in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color(hex: "#FCA311"))

                    Text(metric)
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color(hex: "#FCA311"))
                Text(AppLocalization.string("health.indicator.missing.subtitle"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#1C1C1E"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct HealthIndicatorMissingDataView: View {
    let indicatorTitle: String
    let missingItems: [String]

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 340, tint: Color.cyan.opacity(0.2))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(indicatorTitle)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("health.indicator.missing.subtitle"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .foregroundStyle(Color(hex: "#FCA311"))
                            Text(AppLocalization.string("health.indicator.missing.requirements.title"))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(.white)
                        }

                        ForEach(missingItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color(hex: "#FCA311"))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(AppTypography.body)
                                    .foregroundStyle(.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("health.indicator.missing.info.title"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("health.indicator.missing.info.body"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLocalization.string("health.indicator.missing.legend.title"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)

                        legendRow(
                            title: AppLocalization.string("In range"),
                            subtitle: AppLocalization.string("health.indicator.missing.legend.inrange"),
                            color: Color(hex: "#22C55E")
                        )
                        legendRow(
                            title: AppLocalization.string("Above range"),
                            subtitle: AppLocalization.string("health.indicator.missing.legend.above"),
                            color: Color(hex: "#FCA311")
                        )
                        legendRow(
                            title: AppLocalization.string("Higher range"),
                            subtitle: AppLocalization.string("health.indicator.missing.legend.high"),
                            color: Color(hex: "#F97316")
                        )
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
        .navigationTitle(indicatorTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legendRow(title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

// MARK: - Health Metrics Section Card
