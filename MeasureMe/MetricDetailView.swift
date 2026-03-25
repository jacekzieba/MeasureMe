import SwiftUI
import Charts
import SwiftData
import Accessibility
import Foundation

/// **MetricDetailView**
/// Widok szczegółów pojedynczej metryki. Wyświetla:
/// - Wykres z danymi historycznymi (z możliwością zmiany zakresu czasowego)
/// - Linię celu (jeśli jest ustawiona)
/// - Przycisk do ustawiania/edycji celu
/// - Historię wszystkich pomiarów z możliwością edycji/usuwania
///
/// **Architektura:**
/// - Używa SwiftData do przechowywania próbek (`MetricSample`) i celów (`MetricGoal`)
/// - Automatycznie konwertuje jednostki między metric/imperial
/// - Dynamicznie dostosowuje zakres osi Y do danych i celu
///
/// **Optymalizacje:**
/// - Query filtruje dane już na poziomie bazy danych
/// - Obliczenia wartości do wyświetlenia są cache'owane przez computed properties
/// - Używa `persistentModelID` jako stabilnego identyfikatora w pętlach
struct MetricDetailView: View {
    private let measurementsTheme = FeatureTheme.measurements
    let kind: MetricKind
    @EnvironmentObject private var premiumStore: PremiumStore

    // MARK: - SwiftData Queries
    @Environment(\.modelContext) var context
    @EnvironmentObject var router: AppRouter
    
    /// Próbki tej metryki, posortowane rosnąco po dacie (dla wykresu)
    @Query var samples: [MetricSample]
    
    /// Cel dla tej metryki (maksymalnie jeden cel na metrykę)
    @Query var goals: [MetricGoal]
    
    @Query var photos: [PhotoEntry]

    @Query(sort: [SortDescriptor(\MetricSample.date, order: .forward)])
    private var allMetricSamples: [MetricSample]

    // MARK: - State Properties
    @State var showAddSheet = false
    @State var editingSample: MetricSample?
    @State var showGoalSheet = false
    @State var showCompareSheet = false
    @State var showTrendline = true
    @State var showAllHistory = false
    @State var insightState: InsightState = .loading
    @State var isLoadingInsight = false
    @State private var showInsightConversation = false
    @State var comparisonKind: MetricKind?
    @State private var scrubbedDate: Date?
    @State private var chartScrubState: ChartScrubState = .idle
    @State private var chartWidth: CGFloat = 0
    @State private var isPredictionExpanded = false
    @State private var isEditingCommitment = false
    @State private var commitmentInput: String = ""
    
    @AppSetting(\.experience.photosFilterTag) var photosFilterTag: String = ""

    /// System jednostek: "metric" (kg, cm) lub "imperial" (lb, in)
    @AppSetting(\.profile.unitsSystem) internal var unitsSystem: String = "metric"
    @AppSetting(\.profile.userName) internal var userName: String = ""
    
    // MARK: - Timeframe Enum
    
    /// Zakresy czasowe dla wykresu
    enum Timeframe: String, CaseIterable, Identifiable {
        case week = "7D"
        case month = "30D"
        case threeMonths = "90D"
        case year = "1Y"
        case all = "All"
        var id: String { rawValue }

        /// Oblicza datę początkową dla danego zakresu
        /// - Parameter now: Data odniesienia (domyślnie teraz)
        /// - Returns: Data początkowa lub nil dla "All"
        func startDate(from now: Date = AppClock.now) -> Date? {
            let cal = Calendar.current
            switch self {
            case .week: return cal.date(byAdding: .day, value: -7, to: now)
            case .month: return cal.date(byAdding: .day, value: -30, to: now)
            case .threeMonths: return cal.date(byAdding: .day, value: -90, to: now)
            case .year: return cal.date(byAdding: .year, value: -1, to: now)
            case .all: return nil
            }
        }
    }

    @State var timeframe: Timeframe = .month

    private enum ChartScrubState {
        case idle
        case armed
        case scrubbing
    }

    enum InsightState {
        case loading
        case ready(String)
        case fallback(String)
    }

    // MARK: - Initialization
    
    init(kind: MetricKind) {
        self.kind = kind
        // Hoist rawValue do lokalnej stałej - #Predicate wymaga wartości, nie key path
        let kindValue = kind.rawValue
        
        // Query dla próbek tej metryki, posortowane rosnąco po dacie
        _samples = Query(
            filter: #Predicate<MetricSample> { $0.kindRaw == kindValue },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
        
        // Query dla celu tej metryki
        _goals = Query(
            filter: #Predicate<MetricGoal> { $0.kindRaw == kindValue }
        )

        if let tag = PhotoTag(metricKind: kind) {
            _photos = Query(
                filter: #Predicate<PhotoEntry> { $0.tags.contains(tag) },
                sort: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            _photos = Query(
                filter: #Predicate<PhotoEntry> { _ in false },
                sort: [SortDescriptor(\.date, order: .reverse)]
            )
        }
    }
    
    // MARK: - Computed Properties
    
    /// Aktualny cel dla tej metryki (może być nil)
    var currentGoal: MetricGoal? {
        goals.first
    }

    var availableComparisonOptions: [MetricComparisonOption] {
        let grouped = Dictionary(grouping: allMetricSamples) { $0.kindRaw }

        return MetricKind.allCases.compactMap { candidate in
            guard candidate != kind,
                  let candidateSamples = grouped[candidate.rawValue],
                  !candidateSamples.isEmpty else {
                return nil
            }

            let sorted = candidateSamples.sorted { $0.date < $1.date }
            return MetricComparisonOption(
                kind: candidate,
                latestSample: sorted.last,
                sampleCount: sorted.count,
                usesSecondaryAxis: candidate.unitCategory != kind.unitCategory,
                isRecommended: candidate.unitCategory == kind.unitCategory
            )
        }
        .sorted { lhs, rhs in
            if lhs.isRecommended != rhs.isRecommended {
                return lhs.isRecommended && !rhs.isRecommended
            }
            if lhs.sampleCount != rhs.sampleCount {
                return lhs.sampleCount > rhs.sampleCount
            }
            switch (lhs.latestSample?.date, rhs.latestSample?.date) {
            case let (left?, right?) where left != right:
                return left > right
            default:
                return lhs.kind.title.localizedCaseInsensitiveCompare(rhs.kind.title) == .orderedAscending
            }
        }
    }

    var hasComparisonOptions: Bool {
        !availableComparisonOptions.isEmpty
    }

    var activeComparisonOption: MetricComparisonOption? {
        guard let comparisonKind else { return nil }
        return availableComparisonOptions.first { $0.kind == comparisonKind }
    }

    var comparisonSamples: [MetricSample] {
        guard let comparisonKind else { return [] }
        return allMetricSamples.filter { $0.kindRaw == comparisonKind.rawValue }
    }
    
    /// Próbki przefiltrowane według wybranego zakresu czasowego
    var chartSamples: [MetricSample] {
        if let start = timeframe.startDate(from: AppClock.now) {
            return sortedSamplesAscending.filter { $0.date >= start }
        } else {
            return sortedSamplesAscending  // "All" - pokazuj wszystkie
        }
    }

    var chartRenderPointLimit: Int {
        Self.chartRenderPointLimit(for: timeframe, availableWidth: chartWidth)
    }

    var chartRenderSamples: [MetricSample] {
        Self.sampledChartSamples(from: chartSamples, maxPoints: chartRenderPointLimit)
    }

    var comparisonChartSamples: [MetricSample] {
        guard !comparisonSamples.isEmpty else { return [] }
        if let start = timeframe.startDate(from: AppClock.now) {
            return comparisonSamples.filter { $0.date >= start }
        }
        return comparisonSamples
    }

    var comparisonRenderSamples: [MetricSample] {
        Self.sampledChartSamples(from: comparisonChartSamples, maxPoints: chartRenderPointLimit)
    }

    var chartTrendSamples: [MetricSample] {
        Self.sampledChartSamples(
            from: chartSamples,
            maxPoints: Self.chartTrendPointLimit(for: timeframe, availableWidth: chartWidth)
        )
    }

    var chartInteractionSamples: [MetricSample] {
        Self.sampledChartSamples(
            from: chartRenderSamples,
            maxPoints: Self.chartInteractionPointLimit(for: timeframe, availableWidth: chartWidth)
        )
    }

    var shouldRenderAllChartPoints: Bool {
        chartRenderSamples.count <= 220
    }

    var latestRenderedSampleID: PersistentIdentifier? {
        chartRenderSamples.last?.persistentModelID
    }
    
    var isChartScrubbingEnabled: Bool {
        !chartInteractionSamples.isEmpty
    }
    
    var relatedTag: PhotoTag? {
        PhotoTag(metricKind: kind)
    }
    
    var relatedPhotos: [PhotoEntry] {
        photos
    }

    var visiblePhotos: [PhotoEntry] {
        Array(relatedPhotos.prefix(3))
    }

    var latestSample: MetricSample? {
        sortedSamplesAscending.last
    }

    var previousSample: MetricSample? {
        guard sortedSamplesAscending.count > 1 else { return nil }
        return sortedSamplesAscending[sortedSamplesAscending.count - 2]
    }

    var heroDeltaValueText: String? {
        guard let latestSample, let previousSample else { return nil }
        let delta = displayValue(latestSample.value - previousSample.value)
        guard abs(delta) >= 0.05 else { return nil }
        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(kind.formattedDisplayValue(abs(delta), unitsSystem: unitsSystem))"
    }

    var heroDeltaCaption: String {
        guard let latestSample, let previousSample else {
            return AppLocalization.string("Current value")
        }
        let days = max(Calendar.current.dateComponents([.day], from: previousSample.date, to: latestSample.date).day ?? 0, 0)
        if days == 0 {
            return AppLocalization.string("Current value")
        }
        return AppLocalization.plural("compare.days.apart", days)
    }

    var isComparisonActive: Bool {
        comparisonKind != nil && !comparisonRenderSamples.isEmpty
    }

    var comparisonHasLargeScaleDisparity: Bool {
        guard comparisonKind != nil else { return false }

        let primaryValues = chartRenderSamples.map { displayValue($0.value) }
        let comparisonValues = comparisonRenderSamples.map { comparisonDisplayValue($0.value) }

        guard let primaryRange = valueRange(for: primaryValues),
              let comparisonRange = valueRange(for: comparisonValues) else {
            return false
        }

        let primarySpan = max(primaryRange.upperBound - primaryRange.lowerBound, Self.minimalSpan(for: kind))
        let comparisonSpan = max(comparisonRange.upperBound - comparisonRange.lowerBound, Self.minimalSpan(for: kind))
        let combinedLower = min(primaryRange.lowerBound, comparisonRange.lowerBound)
        let combinedUpper = max(primaryRange.upperBound, comparisonRange.upperBound)
        let combinedSpan = max(combinedUpper - combinedLower, max(primarySpan, comparisonSpan))
        let primaryMidpoint = (primaryRange.lowerBound + primaryRange.upperBound) / 2
        let comparisonMidpoint = (comparisonRange.lowerBound + comparisonRange.upperBound) / 2
        let midpointGap = abs(primaryMidpoint - comparisonMidpoint)

        return combinedSpan > max(primarySpan, comparisonSpan) * 2.2 &&
            midpointGap > max(primarySpan, comparisonSpan) * 0.9
    }

    var comparisonRequiresSecondaryAxis: Bool {
        guard let comparisonKind else { return false }
        return comparisonKind.unitCategory != kind.unitCategory || comparisonHasLargeScaleDisparity
    }

    var scrubbedPrimarySample: MetricSample? {
        nearestSample(to: scrubbedDate, in: chartInteractionSamples)
    }
    
    var historyLimit: Int { 5 }
    
    var visibleHistorySamples: [MetricSample] {
        let all = sortedSamplesAscending.reversed()
        if showAllHistory {
            return Array(all)
        }
        return Array(all.prefix(historyLimit))
    }

    var sortedSamplesAscending: [MetricSample] {
        samples
    }

    var appleIntelligenceAvailable: Bool {
        AppleIntelligenceSupport.isAvailable()
    }

    var supportsAppleIntelligence: Bool {
        premiumStore.isPremium && appleIntelligenceAvailable
    }

    var measurementInstructions: String {
        switch kind {
        case .weight:
            return AppLocalization.string("measure.instructions.weight")
        case .waist:
            return AppLocalization.string("measure.instructions.waist")
        case .bodyFat:
            return AppLocalization.string("measure.instructions.bodyFat")
        case .leanBodyMass:
            return AppLocalization.string("measure.instructions.leanBodyMass")
        case .height:
            return AppLocalization.string("measure.instructions.height")
        case .neck, .shoulders, .bust, .chest, .hips, .leftBicep, .rightBicep, .leftForearm, .rightForearm, .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return AppLocalization.string("measure.instructions.circumference")
        }
    }

    // MARK: - Body

    var body: some View {
        detailList
    }

    var detailList: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 260, tint: measurementsTheme.softTint)
            List {
                listContent
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(kind.title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    showAddSheet = true
                } label: {
                    Label(AppLocalization.string("Update"), systemImage: "plus")
                }
                .accessibilityLabel(AppLocalization.string("accessibility.update.metric", kind.title))
                .accessibilityHint(AppLocalization.string("accessibility.add.measurement"))
            }
        }
        // MARK: Sheets
        .sheet(isPresented: $showAddSheet) {
            AddMetricSampleView(
                kind: kind,
                defaultMetricValue: samples.last?.value
            ) { date, metricValue in
                add(date: date, value: metricValue)
            }
        }
        .sheet(item: $editingSample) { sample in
            EditMetricSampleView(kind: kind, sample: sample)
        }
        .sheet(isPresented: $showGoalSheet) {
            SetGoalView(
                kind: kind,
                currentGoal: currentGoal,
                latestMetricValue: latestSampleValue,
                onSet: { targetValue, direction, startValue, startDate in
                    setGoal(targetValue: targetValue, direction: direction,
                            startValue: startValue, startDate: startDate)
                },
                onDelete: {
                    deleteGoal()
                }
            )
        }
        .sheet(isPresented: $showCompareSheet) {
            MetricCompareSheet(
                currentKind: kind,
                selectedKind: comparisonKind,
                options: availableComparisonOptions,
                timeframe: $timeframe,
                unitsSystem: unitsSystem,
                primarySamples: chartRenderSamples,
                comparisonSamples: comparisonRenderSamples,
                primaryColor: measurementsTheme.accent,
                comparisonColor: AppColorRoles.compareAfter,
                usesSecondaryAxis: comparisonRequiresSecondaryAxis,
                primaryAxisDomain: comparisonPrimaryAxisDomain,
                secondaryAxisValues: secondaryAxisGuideValues.reversed(),
                primaryDisplayValue: { displayValue($0) },
                comparisonDisplayValue: { plottedComparisonValue(for: $0) },
                onSelect: { selectedKind in
                    Haptics.selection()
                    comparisonKind = selectedKind
                    scrubbedDate = nil
                },
                onClear: isComparisonActive ? {
                    Haptics.light()
                    comparisonKind = nil
                    scrubbedDate = nil
                } : nil
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showInsightConversation) {
            if let input = insightInput, case .ready(let text) = insightState {
                InsightConversationView(
                    metricTitle: kind.title,
                    originalInsight: text,
                    input: input
                )
            }
        }
        .task(id: insightInput) {
            await loadInsightIfNeeded()
        }
        .onChange(of: comparisonKind) { _, _ in
            endChartScrubbing()
        }
        .onChange(of: allMetricSamples.count) { _, _ in
            guard let comparisonKind else { return }
            let stillExists = allMetricSamples.contains { $0.kindRaw == comparisonKind.rawValue }
            if !stillExists {
                self.comparisonKind = nil
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if samples.isEmpty {
            emptyStateSection
            howToMeasureSection
        } else {
            heroSection
            goalPredictionSection
            insightSection
            trendsSection
            historySection
            howToMeasureSection
        }
    }

    private var currentValueTrendSummary: (text: String, color: Color, icon: String)? {
        guard let start = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) else { return nil }
        let window = sortedSamplesAscending.filter { $0.date >= start }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID,
              let deltaText = window.deltaText(days: 30, kind: kind, unitsSystem: unitsSystem) else {
            return nil
        }

        let delta = newest.value - oldest.value
        let outcome = kind.trendOutcome(from: oldest.value, to: newest.value, goal: currentGoal)
        let relativeLabel = AppLocalization.string("trend.relative.30d")
        let trendText = "\(deltaText) vs \(relativeLabel)"
        let icon: String
        if delta > 0 {
            icon = "arrow.up.right"
        } else if delta < 0 {
            icon = "arrow.down.right"
        } else {
            icon = "arrow.left.and.right"
        }
        switch outcome {
        case .positive:
            return (trendText,
                    AppColorRoles.chartPositive,
                    icon)
        case .negative:
            return (trendText,
                    AppColorRoles.chartNegative,
                    icon)
        case .neutral:
            return (trendText,
                    AppColorRoles.textSecondary,
                    icon)
        }
    }

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            kind.iconView(size: 56, tint: measurementsTheme.accent)
                .opacity(0.7)
            VStack(spacing: 6) {
                Text(AppLocalization.string("No data"))
                    .font(AppTypography.displaySection)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(AppLocalization.string("Add your first entry to see history and charts."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var insightSection: some View {
        if supportsAppleIntelligence {
            Section {
                switch insightState {
                case .ready(let text):
                    MetricInsightCard(
                        text: text,
                        compact: false,
                        isLoading: isLoadingInsight,
                        onRefresh: { Task { await refreshInsight() } }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { showInsightConversation = true }
                case .loading:
                    MetricInsightCard(
                        text: AppLocalization.string("Generating insight..."),
                        compact: false,
                        isLoading: true
                    )
                case .fallback(let message):
                    MetricInsightCard(
                        text: message,
                        compact: false,
                        isLoading: isLoadingInsight,
                        onRefresh: { Task { await refreshInsight() } }
                    )
                }
            } header: {
                Text(AppLocalization.string("Insight"))
            }
        }
        if premiumStore.isPremium && !appleIntelligenceAvailable {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("AI Insights aren’t available right now."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    NavigationLink {
                        FAQView()
                    } label: {
                        Text(AppLocalization.string("Learn more in FAQ"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(measurementsTheme.accent)
                    }
                }
            } header: {
                Text(AppLocalization.string("Insight"))
            }
        }
    }

    @ViewBuilder
    private var goalPredictionSection: some View {
        if currentGoal != nil {
            Section {
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
            } header: {
                Text(AppLocalization.string("metric.goal.prediction.title"))
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

    // MARK: - Weight Prediction Expanded Content

    @ViewBuilder
    private func weightPredictionExpandedContent(rates: GoalPredictionEngine.WeightPredictionRates) -> some View {
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

            // Rzędy dat
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
    private func predictionRateBox(
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
    private func predictionDateRow(
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
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.06))
        )
    }

    private func predictionIcon(for result: GoalPredictionResult) -> String {
        switch result {
        case .achieved: return "checkmark.circle.fill"
        case .onTrack: return "chart.line.uptrend.xyaxis"
        case .trendOpposite: return "exclamationmark.triangle.fill"
        case .flatTrend: return "equal.circle.fill"
        case .tooFarOut: return "clock.badge.exclamationmark"
        case .insufficientData: return "questionmark.circle"
        }
    }

    private func predictionColor(for result: GoalPredictionResult) -> Color {
        switch result {
        case .achieved, .onTrack: return AppColorRoles.stateSuccess
        case .trendOpposite: return AppColorRoles.stateError
        case .flatTrend, .tooFarOut, .insufficientData: return AppColorRoles.textSecondary
        }
    }

    // MARK: - Trends Card

    private struct TrendPeriod: Identifiable {
        let days: Int?
        let labelKey: String
        var id: String { labelKey }
    }

    private var trendPeriods: [TrendPeriod] {
        [
            TrendPeriod(days: 7, labelKey: "trends.period.7d"),
            TrendPeriod(days: 30, labelKey: "trends.period.30d"),
            TrendPeriod(days: 90, labelKey: "trends.period.90d"),
            TrendPeriod(days: nil, labelKey: "trends.period.alltime"),
        ]
    }

    private static let trendPositive = Color(hex: "#16A34A")
    private static let trendNegative = Color(hex: "#EF4444")

    private var trendsSection: some View {
        Section {
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
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text(AppLocalization.string("trends.title", kind.title))
        }
    }

    @ViewBuilder
    private func trendTile(period: TrendPeriod) -> some View {
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    private func trendLabel(delta: Double?, periodLabel: String) -> String {
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

    private var heroSection: some View {
        Section {
            AppGlassCard(
                depth: .floating,
                cornerRadius: 24,
                tint: measurementsTheme.strongTint,
                contentPadding: 18
            ) {
                VStack(spacing: 18) {
                    metricHeroSummary

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    chartSectionContent
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var historySection: some View {
        Section {
            ForEach(visibleHistorySamples, id: \.persistentModelID) { s in
                HStack {
                    Text(s.date, style: .date)
                    Spacer()
                    Text(valueString(s.value))
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { edit(sample: s) }
                .accessibilityLabel({
                    let dateText = s.date.formatted(date: .abbreviated, time: .omitted)
                    return AppLocalization.string("accessibility.entry.detail", dateText, valueString(s.value))
                }())
                .accessibilityHint(AppLocalization.string("accessibility.entry.edit"))
                .swipeActions {
                    Button(role: .destructive) {
                        delete(sample: s)
                    } label: {
                        Label(AppLocalization.string("Delete"), systemImage: "trash")
                    }
                    .tint(.red)
                    Button {
                        edit(sample: s)
                    } label: {
                        Label(AppLocalization.string("Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        } header: {
            HStack {
                Text(AppLocalization.string("History"))
                Spacer()
                if samples.count > historyLimit {
                    Button(showAllHistory ? AppLocalization.string("Show Less") : AppLocalization.string("View All")) {
                        showAllHistory.toggle()
                    }
                    .font(AppTypography.sectionAction)
                }
            }
        }
    }

    private var howToMeasureSection: some View {
        Section {
            Text(measurementInstructions)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
        } header: {
            Text(AppLocalization.string("How to measure"))
        }
    }

    var chartSectionContent: some View {
        VStack(spacing: 12) {
            Picker(AppLocalization.string("Range"), selection: $timeframe) {
                ForEach(Timeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(.segmented)

            chartView
                .padding(.bottom, 6)

            chartLegendRow

            HStack(spacing: 12) {
                Button {
                    showGoalSheet = true
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("Goal"),
                        icon: "target",
                        color: measurementsTheme.accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.goal")
                .accessibilityLabel(currentGoal == nil ? AppLocalization.string("accessibility.goal.set") : AppLocalization.string("accessibility.goal.update"))
                .accessibilityHint(AppLocalization.string("accessibility.goal.define"))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showTrendline.toggle()
                    }
                    Haptics.selection()
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("Trend"),
                        icon: "chart.line.uptrend.xyaxis",
                        color: AppColorRoles.stateSuccess,
                        isActive: showTrendline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.trend")
                .accessibilityLabel(AppLocalization.string("accessibility.trendline"))
                .accessibilityValue(showTrendline ? AppLocalization.string("accessibility.visible") : AppLocalization.string("accessibility.hidden"))
                .accessibilityHint(AppLocalization.string("accessibility.trendline.toggle"))

                Button {
                    showCompareSheet = true
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("metric.compare.title"),
                        icon: "square.stack.3d.up",
                        color: AppColorRoles.compareAfter,
                        isActive: isComparisonActive
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.compare")
                .accessibilityLabel(AppLocalization.string("metric.compare.button"))
                .accessibilityValue(compareActionValueText)
                .accessibilityHint(AppLocalization.string("metric.compare.button.hint"))
            }
        }
    }

    private var metricHeroSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        kind.iconView(size: 18, tint: measurementsTheme.accent)
                        Text(AppLocalization.string("Current value"))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Text(valueString(latestSampleValue ?? 0))
                        .font(AppTypography.dataCompact)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.22)
                        .allowsTightening(true)

                    if let latestSample {
                        Text(latestSample.date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                if let currentValueTrendSummary {
                    Label(currentValueTrendSummary.text, systemImage: currentValueTrendSummary.icon)
                        .font(AppTypography.badge)
                        .foregroundStyle(currentValueTrendSummary.color)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(currentValueTrendSummary.color.opacity(0.14))
                        )
                }
            }
            if relatedTag != nil {
                metricHeroPhotoProof
            }
        }
    }

    @ViewBuilder
    private var metricHeroPhotoProof: some View {
        if relatedPhotos.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.headline)
                    .foregroundStyle(measurementsTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Photo Progress"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string("No related photos yet."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
            )
        } else {
            Button {
                if let tag = relatedTag {
                    photosFilterTag = tag.rawValue
                    router.selectedTab = .photos
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("Photo Progress"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(heroDeltaCaption)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        ForEach(visiblePhotos, id: \.persistentModelID) { photo in
                            DownsampledImageView(
                                imageData: photo.thumbnailOrImageData,
                                targetSize: CGSize(width: 42, height: 42),
                                contentMode: .fill,
                                cornerRadius: 12,
                                showsProgress: false,
                                cacheID: String(describing: photo.id)
                            )
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("View more photos"))
            .accessibilityHint(AppLocalization.string("accessibility.photos.filtered"))
        }
    }

    private func secondaryActionCard(
        title: String,
        icon: String,
        color: Color,
        isActive: Bool = true,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(AppTypography.iconMedium)
                .foregroundStyle(isActive ? color : AppColorRoles.textTertiary)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .layoutPriority(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isActive ? AppColorRoles.surfaceInteractive : AppColorRoles.surfaceInteractive.opacity(0.74))
        )
    }

    private var chartLegendRow: some View {
        HStack {
            legendItem(
                title: kind.title,
                color: measurementsTheme.accent,
                subtitle: nil
            )
            Spacer(minLength: 0)
        }
    }

    private func legendItem(title: String, color: Color, subtitle: String?, dashed: Bool = false) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 4] : []))
                .background {
                    if !dashed {
                        Capsule().fill(color)
                    }
                }
                .frame(width: 18, height: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    private var compareActionValueText: String {
        guard let comparisonKind else {
            return hasComparisonOptions
                ? AppLocalization.string("metric.compare.cta.idle")
                : AppLocalization.string("metric.compare.cta.empty")
        }
        return comparisonKind.title
    }

    var chartView: some View {
        Chart {
            if showTrendline, let trend = trendlineSegment {
                ForEach(trendlinePoints(trend), id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Trend", "Trend")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(AppColorRoles.stateSuccess.opacity(0.96))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
            }

            ForEach(chartRenderSamples, id: \.persistentModelID) { s in
                AreaMark(
                    x: .value("Date", s.date),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", displayValue(s.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            measurementsTheme.accent.opacity(0.28),
                            measurementsTheme.accent.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", s.date),
                    y: .value("Value", displayValue(s.value))
                )
                .interpolationMethod(.monotone)
                .lineStyle(.init(lineWidth: 2.5))
                .foregroundStyle(measurementsTheme.accent)

                if shouldRenderAllChartPoints {
                    PointMark(
                        x: .value("Date", s.date),
                        y: .value("Value", displayValue(s.value))
                    )
                    .symbol(Circle())
                    .symbolSize(20)
                    .foregroundStyle(measurementsTheme.accent)
                }

                if s.persistentModelID == latestRenderedSampleID {
                    PointMark(
                        x: .value("Latest Date", s.date),
                        y: .value("Latest Value", displayValue(s.value))
                    )
                    .symbol(Circle())
                    .symbolSize(82)
                    .foregroundStyle(measurementsTheme.accent.opacity(0.26))

                    if !shouldRenderAllChartPoints {
                        PointMark(
                            x: .value("Latest Date Marker", s.date),
                            y: .value("Latest Value Marker", displayValue(s.value))
                        )
                        .symbol(Circle())
                        .symbolSize(24)
                        .foregroundStyle(measurementsTheme.accent)
                    }
                }
            }

            if let goal = currentGoal {
                let goalValue = displayValue(goal.targetValue)
                RuleMark(y: .value("Goal", goalValue))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            if let scrubbedDate {
                RuleMark(x: .value("Selected Date", scrubbedDate))
                    .foregroundStyle(AppColorRoles.textSecondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let scrubbedPrimarySample {
                    PointMark(
                        x: .value("Selected Date", scrubbedPrimarySample.date),
                        y: .value("Selected Value", displayValue(scrubbedPrimarySample.value))
                    )
                    .symbol(Circle())
                    .symbolSize(58)
                    .foregroundStyle(AppColorRoles.textPrimary)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppColorRoles.borderSubtle)
                AxisTick().foregroundStyle(AppColorRoles.borderStrong)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppColorRoles.borderSubtle)
                AxisTick().foregroundStyle(AppColorRoles.borderStrong)
                AxisValueLabel()
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
            }
        }
        .frame(height: 168)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateChartWidthIfNeeded(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, newValue in
                        updateChartWidthIfNeeded(newValue)
                    }
            }
        }
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleChartTap(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                handleChartDragChanged(value, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                if chartScrubState != .idle {
                                    endChartScrubbing()
                                }
                            }
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            if let scrubbedDate {
                scrubbedOverlay(for: scrubbedDate)
                    .padding(.top, 6)
                    .padding(.leading, 6)
            }
        }
        .clipped()
        .accessibilityIdentifier("metric.detail.chart")
        .accessibilityChartDescriptor(MetricChartAXDescriptor(descriptor: chartDescriptor))
        .accessibilityLabel(AppLocalization.string("accessibility.chart", kind.title))
        .accessibilityHint(AppLocalization.string("accessibility.chart.hint"))
    }

    // MARK: - Helper Methods
    
    /// Konwertuje wartość z jednostek bazowych (metrycznych) na jednostki wyświetlania
    func displayValue(_ metricValue: Double) -> Double {
        kind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    /// Formatuje wartość jako string z jednostką
    func valueString(_ metricValue: Double) -> String {
        kind.formattedMetricValue(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    func comparisonDisplayValue(_ metricValue: Double) -> Double {
        guard let comparisonKind else { return metricValue }
        return comparisonKind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    var comparisonPrimaryAxisDomain: ClosedRange<Double> {
        var values = chartRenderSamples.map { displayValue($0.value) }
        if !comparisonRequiresSecondaryAxis {
            values.append(contentsOf: comparisonRenderSamples.map { comparisonDisplayValue($0.value) })
        }
        return Self.chartDomain(for: values, kind: kind)
    }

    var comparisonAxisDomain: ClosedRange<Double>? {
        guard comparisonRequiresSecondaryAxis, let comparisonKind else { return nil }
        let values = comparisonRenderSamples.map { comparisonKind.valueForDisplay(fromMetric: $0.value, unitsSystem: unitsSystem) }
        guard !values.isEmpty else { return nil }
        return Self.chartDomain(for: values, kind: comparisonKind)
    }

    var secondaryAxisGuideValues: [Double] {
        guard let domain = comparisonAxisDomain else { return [] }
        return [domain.lowerBound, (domain.lowerBound + domain.upperBound) / 2, domain.upperBound]
    }

    func plottedComparisonValue(for metricValue: Double) -> Double {
        let compareDisplay = comparisonDisplayValue(metricValue)
        guard comparisonRequiresSecondaryAxis, let comparisonAxisDomain else {
            return compareDisplay
        }
        return remapComparisonValue(compareDisplay, from: comparisonAxisDomain)
    }

    func remapComparisonValue(_ value: Double, from comparisonDomain: ClosedRange<Double>) -> Double {
        Self.remap(value, from: comparisonDomain, to: comparisonPrimaryAxisDomain)
    }

    @ViewBuilder
    func scrubbedOverlay(for scrubbedDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scrubbedDate.formatted(date: .abbreviated, time: .omitted))
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textSecondary)

            if let scrubbedPrimarySample {
                scrubbedValueChip(
                    title: kind.title,
                    value: valueString(scrubbedPrimarySample.value),
                    color: measurementsTheme.accent
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColorRoles.surfaceCanvas.opacity(0.68))
        )
    }

    func scrubbedValueChip(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
                Text(value)
                    .font(AppTypography.microEmphasis.monospacedDigit())
                    .foregroundStyle(AppColorRoles.textPrimary)
            }
        }
    }

    var trendlineSegment: (startDate: Date, startValue: Double, endDate: Date, endValue: Double)? {
        guard chartTrendSamples.count >= 2 else { return nil }

        let times = chartTrendSamples.map { $0.date.timeIntervalSinceReferenceDate }
        let values = chartTrendSamples.map { displayValue($0.value) }
        
        let count = Double(values.count)
        let sumX = times.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(times, values).reduce(0) { $0 + ($1.0 * $1.1) }
        let sumXX = times.reduce(0) { $0 + ($1 * $1) }
        
        let denominator = (count * sumXX - sumX * sumX)
        guard denominator != 0 else { return nil }
        
        let slope = (count * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / count
        
        guard let startTime = times.first, let endTime = times.last,
              let firstSample = chartTrendSamples.first, let lastSample = chartTrendSamples.last else { return nil }
        let startValue = slope * startTime + intercept
        let endValue = slope * endTime + intercept

        return (
            startDate: firstSample.date,
            startValue: startValue,
            endDate: lastSample.date,
            endValue: endValue
        )
    }
    
    func trendlinePoints(
        _ trend: (startDate: Date, startValue: Double, endDate: Date, endValue: Double)
    ) -> [(date: Date, value: Double)] {
        [
            (date: trend.startDate, value: trend.startValue),
            (date: trend.endDate, value: trend.endValue)
        ]
    }

    /// Dynamicznie oblicza zakres osi Y na podstawie danych i celu
    /// Uwzględnia minimalny span i padding dla czytelności
    var yDomain: ClosedRange<Double> {
        var values = chartRenderSamples.map { displayValue($0.value) }
        if let goal = currentGoal {
            values.append(displayValue(goal.targetValue))
        }
        return Self.chartDomain(for: values, kind: kind)
    }

    private func updateScrubbedDate(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled else {
            scrubbedDate = nil
            return
        }

        guard let plotFrame = proxy.plotFrame else {
            scrubbedDate = nil
            return
        }

        let plotOrigin = geometry[plotFrame].origin
        let xPosition = location.x - plotOrigin.x

        guard xPosition >= 0, xPosition <= proxy.plotSize.width else {
            scrubbedDate = nil
            return
        }

        guard let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
            scrubbedDate = nil
            return
        }

        scrubbedDate = date
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled else { return }
        guard isLocationNearChartSeries(location, proxy: proxy, geometry: geometry) else {
            endChartScrubbing()
            return
        }

        chartScrubState = .armed
        updateScrubbedDate(at: location, proxy: proxy, geometry: geometry)
    }

    private func handleChartDragChanged(_ value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled else { return }

        switch chartScrubState {
        case .armed, .scrubbing:
            chartScrubState = .scrubbing
            updateScrubbedDate(at: value.location, proxy: proxy, geometry: geometry)

        case .idle:
            guard isLocationNearChartSeries(value.startLocation, proxy: proxy, geometry: geometry) else { return }
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            guard horizontal >= 8, horizontal > vertical else { return }

            chartScrubState = .scrubbing
            updateScrubbedDate(at: value.location, proxy: proxy, geometry: geometry)
        }
    }

    private func endChartScrubbing() {
        chartScrubState = .idle
        scrubbedDate = nil
    }

    private func isLocationNearChartSeries(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Bool {
        let hitTolerance: CGFloat = 24
        let segmentTolerance: CGFloat = 20

        let positions = chartSampleScreenPositions(proxy: proxy, geometry: geometry)
        guard !positions.isEmpty else { return false }

        let nearPoint = positions.contains { location.distance(to: $0) <= hitTolerance }
        if nearPoint {
            return true
        }

        guard positions.count > 1 else { return false }
        for index in 0..<(positions.count - 1) {
            let start = positions[index]
            let end = positions[index + 1]
            if location.distance(toSegmentStart: start, end: end) <= segmentTolerance {
                return true
            }
        }
        return false
    }

    private func chartSampleScreenPositions(proxy: ChartProxy, geometry: GeometryProxy) -> [CGPoint] {
        guard let plotFrame = proxy.plotFrame else { return [] }
        let plotOrigin = geometry[plotFrame].origin

        return chartInteractionSamples.compactMap { sample -> CGPoint? in
            guard let xPosition = proxy.position(forX: sample.date),
                  let yPosition = proxy.position(forY: displayValue(sample.value)) else {
                return nil
            }

            return CGPoint(x: plotOrigin.x + xPosition, y: plotOrigin.y + yPosition)
        }
    }

    private func updateChartWidthIfNeeded(_ newWidth: CGFloat) {
        let normalized = max(newWidth, 0)
        guard abs(chartWidth - normalized) >= 1 else { return }
        chartWidth = normalized
    }

    private func nearestSample(to date: Date?, in samples: [MetricSample]) -> MetricSample? {
        guard let date, !samples.isEmpty else { return nil }
        return samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    static func chartDomain(for values: [Double], kind: MetricKind) -> ClosedRange<Double> {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, minimalSpan(for: kind))
        let padding = max(span * 0.10, minimalPadding(for: kind))
        return (minV - padding)...(maxV + padding)
    }

    static func remap(_ value: Double, from sourceDomain: ClosedRange<Double>, to targetDomain: ClosedRange<Double>) -> Double {
        let sourceSpan = max(sourceDomain.upperBound - sourceDomain.lowerBound, 0.0001)
        let targetSpan = targetDomain.upperBound - targetDomain.lowerBound
        let progress = (value - sourceDomain.lowerBound) / sourceSpan
        return targetDomain.lowerBound + progress * targetSpan
    }

    func valueRange(for values: [Double]) -> ClosedRange<Double>? {
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return minValue...maxValue
    }
    static func chartRenderPointLimit(for timeframe: Timeframe, availableWidth: CGFloat) -> Int {
        let width = max(availableWidth, 240)
        let densityBudget = Int((width / 1.6).rounded())
        return min(timeframe.maximumRenderPointLimit, max(timeframe.minimumRenderPointLimit, densityBudget))
    }

    static func chartTrendPointLimit(for timeframe: Timeframe, availableWidth: CGFloat) -> Int {
        let width = max(availableWidth, 240)
        let densityBudget = Int((width / 3.2).rounded())
        let cappedByRender = min(chartRenderPointLimit(for: timeframe, availableWidth: width), 120)
        return min(cappedByRender, max(40, densityBudget))
    }

    static func chartInteractionPointLimit(for timeframe: Timeframe, availableWidth: CGFloat) -> Int {
        let width = max(availableWidth, 240)
        let densityBudget = Int((width / 3.6).rounded())
        let cappedByRender = min(chartRenderPointLimit(for: timeframe, availableWidth: width), 96)
        return min(cappedByRender, max(36, densityBudget))
    }

    static func sampledChartSamples(from samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
        guard maxPoints > 0, samples.count > maxPoints else { return samples }
        guard let first = samples.first, let last = samples.last else { return samples }
        if maxPoints == 1 { return [last] }
        if maxPoints == 2 { return [first, last] }

        let interior = Array(samples.dropFirst().dropLast())
        guard !interior.isEmpty else { return [first, last] }

        let remainingSlots = maxPoints - 2
        let bucketCount = max(1, remainingSlots / 3)
        let bucketSize = Double(interior.count) / Double(bucketCount)

        var selected: [MetricSample] = [first]
        var selectedIDs: Set<PersistentIdentifier> = [first.persistentModelID, last.persistentModelID]

        for bucket in 0..<bucketCount {
            let start = Int(floor(Double(bucket) * bucketSize))
            let end = Int(floor(Double(bucket + 1) * bucketSize))
            let lower = max(0, min(start, interior.count - 1))
            let upper = max(lower + 1, min(end, interior.count))
            guard lower < upper else { continue }

            let slice = Array(interior[lower..<upper])
            guard let representative = slice[safe: slice.count / 2],
                  let localMin = slice.min(by: { $0.value < $1.value }),
                  let localMax = slice.max(by: { $0.value < $1.value }) else {
                continue
            }

            for sample in [representative, localMin, localMax] where !selectedIDs.contains(sample.persistentModelID) {
                selected.append(sample)
                selectedIDs.insert(sample.persistentModelID)
            }
        }

        selected.append(last)
        selected.sort { lhs, rhs in
            if lhs.date == rhs.date {
                let left = samples.firstIndex(where: { $0.persistentModelID == lhs.persistentModelID }) ?? 0
                let right = samples.firstIndex(where: { $0.persistentModelID == rhs.persistentModelID }) ?? 0
                return left < right
            }
            return lhs.date < rhs.date
        }

        if selected.count <= maxPoints { return selected }

        var trimmed: [MetricSample] = [first]
        let interiorTrimmed = Array(selected.dropFirst().dropLast())
        let allowedInterior = max(0, maxPoints - 2)
        if allowedInterior > 0, !interiorTrimmed.isEmpty {
            let step = Double(interiorTrimmed.count) / Double(allowedInterior)
            var index = 0.0
            for _ in 0..<allowedInterior {
                let candidate = interiorTrimmed[min(Int(index), interiorTrimmed.count - 1)]
                if trimmed.last?.persistentModelID != candidate.persistentModelID {
                    trimmed.append(candidate)
                }
                index += step
            }
        }
        if trimmed.last?.persistentModelID != last.persistentModelID {
            trimmed.append(last)
        }
        return trimmed
    }
}
// Metody rozszerzenia sa zdefiniowane w MetricDetailComponents.swift

private extension MetricDetailView.Timeframe {
    var minimumRenderPointLimit: Int {
        switch self {
        case .week: return 56
        case .month: return 72
        case .threeMonths: return 84
        case .year: return 96
        case .all: return 112
        }
    }

    var maximumRenderPointLimit: Int {
        switch self {
        case .week: return 220
        case .month: return 240
        case .threeMonths: return 260
        case .year: return 280
        case .all: return 320
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(x - point.x, y - point.y)
    }

    func distance(toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: start) }

        let projection = ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared
        let clamped = max(0, min(1, projection))
        let projected = CGPoint(x: start.x + clamped * dx, y: start.y + clamped * dy)
        return distance(to: projected)
    }
}
