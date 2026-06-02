import SwiftUI
import Charts
import SwiftData
import Accessibility
import Foundation

/// **MetricDetailView**
/// Detail view for a single metric. Displays:
/// - Chart with historical data (with adjustable time range)
/// - Goal line (if set)
/// - Button to set/edit goal
/// - History of all measurements with edit/delete capability
///
/// **Architecture:**
/// - Uses SwiftData to store samples (`MetricSample`) and goals (`MetricGoal`)
/// - Automatically converts units between metric/imperial
/// - Dynamically adjusts Y-axis range to data and goal
///
/// **Optimizations:**
/// - Query filters data at the database level
/// - Display value calculations are cached via computed properties
/// - Uses `persistentModelID` as a stable identifier in loops
struct MetricDetailView: View {
    let measurementsTheme = FeatureTheme.measurements
    let kind: MetricKind
    @EnvironmentObject var premiumStore: PremiumStore
    @Environment(\.colorScheme) var colorScheme

    // MARK: - SwiftData Queries
    @Environment(\.modelContext) var context
    @EnvironmentObject var router: AppRouter
    
    /// Samples for this metric, sorted ascending by date (for the chart)
    @Query var samples: [MetricSample]
    
    /// Goal for this metric (at most one goal per metric)
    @Query var goals: [MetricGoal]
    
    @Query var photos: [PhotoEntry]

    // MARK: - State Properties
    @State var showAddSheet = false
    @State var editingSample: MetricSample?
    @State var showGoalSheet = false
    @State var showCompareSheet = false
    @State var showTrendline = true
    @State var showAllHistory = false
    @State var insightState: InsightState = .loading
    @State var isLoadingInsight = false
    @State var showInsightConversation = false
    @State var comparisonKind: MetricKind?
    @State var scrubbedDate: Date?
    @State var chartScrubState: ChartScrubState = .idle
    @State var chartWidth: CGFloat = 0
    @State var isPredictionExpanded = false
    @State var isEditingCommitment = false
    @State var commitmentInput: String = ""
    @State var comparisonCache = ComparisonCache()

    // MARK: - Cached Chart Calculations (held in MetricDetailViewModel)
    @State var detailViewModel = MetricDetailViewModel()

    var cachedYDomain: ClosedRange<Double> { detailViewModel.cachedYDomain }
    var cachedTrendlineSegment: (startDate: Date, startValue: Double, endDate: Date, endValue: Double)? { detailViewModel.cachedTrendlineSegment }

    @AppSetting(\.experience.photosFilterTag) var photosFilterTag: String = ""

    /// System jednostek: "metric" (kg, cm) lub "imperial" (lb, in)
    @AppSetting(\.profile.unitsSystem) internal var unitsSystem: String = "metric"
    @AppSetting(\.profile.userName) internal var userName: String = ""
    
    @State var timeframe: Timeframe = .month

    // MARK: - Initialization
    
    init(kind: MetricKind) {
        self.kind = kind
        // Hoist rawValue to a local constant - #Predicate requires values, not key paths
        let kindValue = kind.rawValue
        
        // Query for this metric's samples, sorted ascending by date
        _samples = Query(
            filter: #Predicate<MetricSample> { $0.kindRaw == kindValue },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
        
        // Query for this metric's goal
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
    
    /// Current goal for this metric (can be nil)
    var currentGoal: MetricGoal? {
        detailViewModel.goals.first
    }

    var availableComparisonOptions: [MetricComparisonOption] {
        comparisonCache.options
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
        return comparisonCache.samplesByKind[comparisonKind] ?? []
    }
    
    /// Samples filtered by the selected time range
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
        detailViewModel.photos
    }

    var visiblePhotos: [PhotoEntry] {
        Array(relatedPhotos.prefix(3))
    }

    var latestSample: MetricSample? {
        sortedSamplesAscending.last
    }

    var comparisonCacheRefreshSignature: [PersistentIdentifier] {
        detailViewModel.samples.map(\.persistentModelID)
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
        detailViewModel.samples
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
        detailListWithLifecycle
    }

    private var detailListBase: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 260, tint: measurementsTheme.softTint)
            ScrollView {
                detailContent
            }
        }
    }

    private var detailListNavigation: some View {
        detailListBase
        .navigationTitle(kind.title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: presentAddMeasurementSheet) {
                    Label(AppLocalization.string("Update"), systemImage: "plus")
                }
                .accessibilityLabel(AppLocalization.string("accessibility.update.metric", kind.title))
                .accessibilityHint(AppLocalization.string("accessibility.add.measurement"))
            }
        }
    }

    private var detailListWithSheets: some View {
        detailListNavigation
        .sheet(isPresented: $showAddSheet) {
            addMeasurementSheetContent
        }
        .sheet(item: $editingSample) { sample in
            EditMetricSampleView(kind: kind, sample: sample)
        }
        .sheet(isPresented: $showGoalSheet) {
            goalSheetContent
        }
        .sheet(isPresented: $showCompareSheet) {
            metricCompareSheetContent
        }
        .sheet(isPresented: $showInsightConversation) {
            insightConversationSheetContent
        }
    }

    private var detailListWithLifecycle: some View {
        detailListWithSheets
        .task(id: insightInput) {
            await loadInsightIfNeeded()
        }
        .onChange(of: comparisonKind) { _, _ in
            endChartScrubbing()
        }
        .onChange(of: comparisonCacheRefreshSignature) { _, _ in handleAllMetricSamplesCountChange() }
        .onChange(of: chartRenderSamples.map(\.persistentModelID)) { _, _ in refreshChartCache() }
        .onChange(of: timeframe) { _, _ in refreshChartCache() }
        .onChange(of: currentGoal?.targetValue) { _, _ in refreshChartCache() }
        .onAppear {
            detailViewModel.samples = samples
            detailViewModel.goals = goals
            detailViewModel.photos = photos
            handleDetailAppear()
        }
        .onChange(of: samples) { _, newValue in
            detailViewModel.samples = newValue
        }
        .onChange(of: goals) { _, newValue in
            detailViewModel.goals = newValue
        }
        .onChange(of: photos) { _, newValue in
            detailViewModel.photos = newValue
        }
    }

    @ViewBuilder
    private var addMeasurementSheetContent: some View {
        AddMetricSampleView(
            kind: kind,
            defaultMetricValue: detailViewModel.samples.last?.value
        ) { date, metricValue in
            add(date: date, value: metricValue)
        }
    }

    @ViewBuilder
    private var goalSheetContent: some View {
        SetGoalView(
            kind: kind,
            currentGoal: currentGoal,
            latestMetricValue: latestSampleValue,
            onSet: { targetValue, direction, startValue, startDate in
                setGoal(
                    targetValue: targetValue,
                    direction: direction,
                    startValue: startValue,
                    startDate: startDate
                )
            },
            onDelete: deleteGoal
        )
    }

    private var compareSheetOnClearAction: (() -> Void)? {
        if isComparisonActive {
            return { clearComparison() }
        }
        return nil
    }

    private var metricCompareSheetContent: some View {
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
            onSelect: handleComparisonSelection,
            onClear: compareSheetOnClearAction
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    @ViewBuilder
    private var insightConversationSheetContent: some View {
        if let input = insightInput, case .ready(let text) = insightState {
            InsightConversationView(
                metricTitle: kind.title,
                originalInsight: text,
                input: input
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if detailViewModel.samples.isEmpty {
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
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func rebuildComparisonCache() {
        let allSamples = (try? context.fetch(FetchDescriptor<MetricSample>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        ))) ?? []
        let grouped = Dictionary(grouping: allSamples) { $0.kindRaw }
        var samplesByKind: [MetricKind: [MetricSample]] = [:]

        let options = MetricKind.allCases.compactMap { candidate -> MetricComparisonOption? in
            guard candidate != kind,
                  let candidateSamples = grouped[candidate.rawValue],
                  !candidateSamples.isEmpty else {
                return nil
            }

            samplesByKind[candidate] = candidateSamples
            return MetricComparisonOption(
                kind: candidate,
                latestSample: candidateSamples.last,
                sampleCount: candidateSamples.count,
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

        comparisonCache = ComparisonCache(options: options, samplesByKind: samplesByKind)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.eyebrow)
            .foregroundStyle(AppColorRoles.textSecondary)
            .textCase(.uppercase)
            .tracking(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private func presentAddMeasurementSheet() {
        Haptics.light()
        showAddSheet = true
    }

    private func handleComparisonSelection(_ selectedKind: MetricKind) {
        Haptics.selection()
        comparisonKind = selectedKind
        scrubbedDate = nil
    }

    private func clearComparison() {
        Haptics.light()
        comparisonKind = nil
        scrubbedDate = nil
    }

    private func handleAllMetricSamplesCountChange() {
        rebuildComparisonCache()
        guard let comparisonKind else { return }
        let stillExists = comparisonCache.samplesByKind[comparisonKind] != nil &&
            !(comparisonCache.samplesByKind[comparisonKind]?.isEmpty ?? true)
        if !stillExists {
            self.comparisonKind = nil
        }
    }

    private func handleDetailAppear() {
        rebuildComparisonCache()
        refreshChartCache()
    }

    private func refreshChartCache() {
        detailViewModel.refreshChartCache(
            computeYDomain: { computeYDomain() },
            computeTrendlineSegment: { computeTrendlineSegment() }
        )
    }

    private func computeYDomain() -> ClosedRange<Double> {
        var values = chartRenderSamples.map { displayValue($0.value) }
        if let goal = currentGoal {
            values.append(displayValue(goal.targetValue))
        }
        return Self.chartDomain(for: values, kind: kind)
    }

    private func computeTrendlineSegment() -> (startDate: Date, startValue: Double, endDate: Date, endValue: Double)? {
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

    @ViewBuilder
    func sectionHeader<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            sectionHeader(title)
            accessory()
        }
    }

    var currentValueTrendSummary: (text: String, color: Color, icon: String)? {
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

    @ViewBuilder
    private var insightSection: some View {
        if supportsAppleIntelligence {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(AppLocalization.string("Insight"))
                switch insightState {
                case .ready(let text):
                    MetricInsightCard(
                        text: text,
                        compact: false,
                        isLoading: isLoadingInsight,
                        onRefresh: { Task { await refreshInsight() } },
                        onExpandToggle: { expanded in
                            Analytics.shared.track(AnalyticsEvents.aiInsightExpanded(kind: .metric, metric: kind.englishTitle, expanded: expanded))
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { showInsightConversation = true }
                case .loading:
                    MetricInsightCard(
                        text: AppLocalization.aiString("Generating insight..."),
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
            }
        }
        if premiumStore.isPremium && !appleIntelligenceAvailable {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(AppLocalization.string("Insight"))
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.aiString("AI Insights aren’t available right now."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    NavigationLink {
                        FAQView()
                    } label: {
                        Text(AppLocalization.aiString("Learn more in FAQ"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(measurementsTheme.accent)
                        }
                }
            }
        }
    }

    var compareActionValueText: String {
        guard let comparisonKind else {
            return hasComparisonOptions
                ? AppLocalization.string("metric.compare.cta.idle")
                : AppLocalization.string("metric.compare.cta.empty")
        }
        return comparisonKind.title
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
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
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

    func trendlinePoints(
        _ trend: (startDate: Date, startValue: Double, endDate: Date, endValue: Double)
    ) -> [(date: Date, value: Double)] {
        [
            (date: trend.startDate, value: trend.startValue),
            (date: trend.endDate, value: trend.endValue)
        ]
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

    func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled else { return }
        guard isLocationNearChartSeries(location, proxy: proxy, geometry: geometry) else {
            endChartScrubbing()
            return
        }

        chartScrubState = .armed
        updateScrubbedDate(at: location, proxy: proxy, geometry: geometry)
    }

    func handleChartDragChanged(_ value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy) {
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

    func endChartScrubbing() {
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

    func updateChartWidthIfNeeded(_ newWidth: CGFloat) {
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
        let sanitizedValues = values.filter(\.isFinite)
        let minV = sanitizedValues.min() ?? 0
        let maxV = sanitizedValues.max() ?? 1
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
