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

    // MARK: - State Properties
    @State var showAddSheet = false
    @State var editingSample: MetricSample?
    @State var showGoalSheet = false
    @State var showTrendline = true
    @State var showAllHistory = false
    @State var insightState: InsightState = .loading
    @State var isLoadingInsight = false
    @State private var scrubbedSample: MetricSample?
    @State private var chartScrubState: ChartScrubState = .idle
    @State private var chartWidth: CGFloat = 0
    
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
        return "\(sign)\(abs(delta).formatted(.number.precision(.fractionLength(1)))) \(kind.unitSymbol(unitsSystem: unitsSystem))"
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
        .task(id: insightInput) {
            await loadInsightIfNeeded()
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if samples.isEmpty {
            emptyStateSection
            howToMeasureSection
        } else {
            heroSection
            insightSection
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

            HStack(spacing: 12) {
                if showTrendline {
                    HStack(spacing: 6) {
                        Capsule()
                            .stroke(AppColorRoles.textTertiary, style: StrokeStyle(lineWidth: 2, dash: [2, 4]))
                            .frame(width: 22, height: 2)
                        Text(AppLocalization.string("Trend"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                }

                if currentGoal != nil {
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(AppColorRoles.textSecondary)
                            .frame(width: 22, height: 2)
                        Text(AppLocalization.string("Goal"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Button {
                    showGoalSheet = true
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("Goal"),
                        value: currentGoal.map { AppLocalization.string("metric.goal.update.value", valueString($0.targetValue)) } ?? AppLocalization.string("Set Goal"),
                        icon: "target",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.goal")
                .accessibilityLabel(currentGoal == nil ? AppLocalization.string("accessibility.goal.set") : AppLocalization.string("accessibility.goal.update"))
                .accessibilityHint(AppLocalization.string("accessibility.goal.define"))

                Button {
                    showTrendline.toggle()
                } label: {
                    secondaryActionCard(
                        title: AppLocalization.string("Trend"),
                        value: showTrendline ? AppLocalization.string("Visible") : AppLocalization.string("Hidden"),
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric.detail.trend")
                .accessibilityLabel(AppLocalization.string("accessibility.trendline"))
                .accessibilityValue(showTrendline ? AppLocalization.string("accessibility.visible") : AppLocalization.string("accessibility.hidden"))
                .accessibilityHint(AppLocalization.string("accessibility.trendline.toggle"))
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

    private func secondaryActionCard(title: String, value: String, icon: String, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(measurementsTheme.accent)
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
            }

            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
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
                    .foregroundStyle(AppColorRoles.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
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

            if let scrubbedSample {
                let scrubbedValue = displayValue(scrubbedSample.value)
                RuleMark(x: .value("Selected Date", scrubbedSample.date))
                    .foregroundStyle(AppColorRoles.textSecondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Selected Date", scrubbedSample.date),
                    y: .value("Selected Value", scrubbedValue)
                )
                .symbol(Circle())
                .symbolSize(58)
                .foregroundStyle(AppColorRoles.textPrimary)
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
            if let scrubbedSample {
                HStack(spacing: 8) {
                    Text(scrubbedSample.date.formatted(date: .abbreviated, time: .omitted))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    Text(valueString(scrubbedSample.value))
                        .font(AppTypography.microEmphasis.monospacedDigit())
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColorRoles.surfaceCanvas.opacity(0.52))
                )
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
        let shown = displayValue(metricValue)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)

        switch kind.unitCategory {
        case .weight, .length:
            return String(format: "%.1f %@", shown, unit)
        case .percent:
            return String(format: "%.1f%@", shown, unit)
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
        
        // Dodaj wartość celu, aby była widoczna na wykresie
        if let goal = currentGoal {
            values.append(displayValue(goal.targetValue))
        }
        
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, minimalSpan(for: kind))
        let padding = max(span * 0.10, minimalPadding(for: kind))  // 10% paddingu
        let lower = minV - padding
        let upper = maxV + padding
        return lower...upper
    }

    private func updateScrubbedSample(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !chartInteractionSamples.isEmpty else {
            scrubbedSample = nil
            return
        }

        guard let plotFrame = proxy.plotFrame else {
            scrubbedSample = nil
            return
        }

        let plotOrigin = geometry[plotFrame].origin
        let xPosition = location.x - plotOrigin.x

        guard xPosition >= 0, xPosition <= proxy.plotSize.width else {
            scrubbedSample = nil
            return
        }

        guard let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
            scrubbedSample = nil
            return
        }

        scrubbedSample = chartInteractionSamples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled else { return }
        guard isLocationNearChartSeries(location, proxy: proxy, geometry: geometry) else {
            endChartScrubbing()
            return
        }

        chartScrubState = .armed
        updateScrubbedSample(at: location, proxy: proxy, geometry: geometry)
    }

    private func handleChartDragChanged(_ value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled else { return }

        switch chartScrubState {
        case .armed, .scrubbing:
            chartScrubState = .scrubbing
            updateScrubbedSample(at: value.location, proxy: proxy, geometry: geometry)

        case .idle:
            guard isLocationNearChartSeries(value.startLocation, proxy: proxy, geometry: geometry) else { return }
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            guard horizontal >= 8, horizontal > vertical else { return }

            chartScrubState = .scrubbing
            updateScrubbedSample(at: value.location, proxy: proxy, geometry: geometry)
        }
    }

    private func endChartScrubbing() {
        chartScrubState = .idle
        scrubbedSample = nil
    }

    private func isLocationNearChartSeries(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Bool {
        let hitTolerance: CGFloat = 24
        let segmentTolerance: CGFloat = 20

        let positions = chartSampleScreenPositions(proxy: proxy, geometry: geometry)
        guard !positions.isEmpty else { return false }

        let nearPoint = positions.contains { location.distance(to: $0.point) <= hitTolerance }
        if nearPoint {
            return true
        }

        guard positions.count > 1 else { return false }
        for index in 0..<(positions.count - 1) {
            let start = positions[index].point
            let end = positions[index + 1].point
            if location.distance(toSegmentStart: start, end: end) <= segmentTolerance {
                return true
            }
        }
        return false
    }

    private func chartSampleScreenPositions(proxy: ChartProxy, geometry: GeometryProxy) -> [(sample: MetricSample, point: CGPoint)] {
        guard let plotFrame = proxy.plotFrame else { return [] }
        let plotOrigin = geometry[plotFrame].origin

        return chartInteractionSamples.compactMap { sample in
            guard let xPosition = proxy.position(forX: sample.date),
                  let yPosition = proxy.position(forY: displayValue(sample.value)) else {
                return nil
            }

            return (
                sample: sample,
                point: CGPoint(x: plotOrigin.x + xPosition, y: plotOrigin.y + yPosition)
            )
        }
    }

    private func updateChartWidthIfNeeded(_ newWidth: CGFloat) {
        let normalized = max(newWidth, 0)
        guard abs(chartWidth - normalized) >= 1 else { return }
        chartWidth = normalized
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
