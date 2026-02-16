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
    let kind: MetricKind
    @EnvironmentObject private var premiumStore: PremiumStore

    // MARK: - SwiftData Queries
    @Environment(\.modelContext) var context
    @EnvironmentObject var router: AppRouter
    
    /// Próbki tej metryki, posortowane rosnąco po dacie (dla wykresu)
    @Query var samples: [MetricSample]
    
    /// Cel dla tej metryki (maksymalnie jeden cel na metrykę)
    @Query var goals: [MetricGoal]
    
    @Query(sort: \PhotoEntry.date, order: .reverse)
    var photos: [PhotoEntry]

    // MARK: - State Properties
    @State var showAddSheet = false
    @State var editingSample: MetricSample?
    @State var showGoalSheet = false
    @State var showTrendline = true
    @State var showAllHistory = false
    @State var detailedInsight: String?
    @State var isLoadingInsight = false
    @State private var scrubbedSample: MetricSample?
    
    @AppStorage("photos_filter_tag") var photosFilterTag: String = ""

    /// System jednostek: "metric" (kg, cm) lub "imperial" (lb, in)
    @AppStorage("unitsSystem") internal var unitsSystem: String = "metric"
    @AppStorage("userName") internal var userName: String = ""
    
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
        func startDate(from now: Date = .now) -> Date? {
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
    }
    
    // MARK: - Computed Properties
    
    /// Aktualny cel dla tej metryki (może być nil)
    var currentGoal: MetricGoal? {
        goals.first
    }
    
    /// Próbki przefiltrowane według wybranego zakresu czasowego
    var chartSamples: [MetricSample] {
        if let start = timeframe.startDate() {
            return samples.filter { $0.date >= start }
        } else {
            return samples  // "All" - pokazuj wszystkie
        }
    }

    var isChartScrubbingEnabled: Bool {
        !chartSamples.isEmpty
    }
    
    var relatedTag: PhotoTag? {
        PhotoTag(metricKind: kind)
    }
    
    var relatedPhotos: [PhotoEntry] {
        guard let tag = relatedTag else { return [] }
        return photos.filter { $0.tags.contains(tag) }
    }

    var visiblePhotos: [PhotoEntry] {
        Array(relatedPhotos.prefix(3))
    }
    
    var historyLimit: Int { 5 }
    
    var visibleHistorySamples: [MetricSample] {
        let all = samples.reversed()
        if showAllHistory {
            return Array(all)
        }
        return Array(all.prefix(historyLimit))
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
            AppScreenBackground(topHeight: 260)
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
            SetGoalView(kind: kind, currentGoal: currentGoal, onSet: { targetValue, direction in
                setGoal(targetValue: targetValue, direction: direction)
            }, onDelete: {
                deleteGoal()
            })
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
            insightSection
            chartSection
            goalTrendSection
            progressSection
            if relatedTag != nil {
                photosSection
            }
            historySection
            howToMeasureSection
        }
    }

    private var emptyStateSection: some View {
        ContentUnavailableView(
            AppLocalization.string("No data"),
            systemImage: kind.systemImage,
            description: Text(AppLocalization.string("Add your first entry to see history and charts."))
        )
    }

    @ViewBuilder
    private var insightSection: some View {
        if supportsAppleIntelligence, (isLoadingInsight || detailedInsight != nil) {
            Section {
                if let detailedInsight {
                    MetricInsightCard(
                        text: detailedInsight,
                        compact: false,
                        isLoading: isLoadingInsight
                    )
                } else if isLoadingInsight {
                    MetricInsightCard(
                        text: AppLocalization.string("Generating insight..."),
                        compact: false,
                        isLoading: true
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
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        FAQView()
                    } label: {
                        Text(AppLocalization.string("Learn more in FAQ"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color.appAccent)
                    }
                }
            } header: {
                Text(AppLocalization.string("Insight"))
            }
        }
    }

    private var chartSection: some View {
        Section {
            chartSectionContent
        } header: {
            Text(AppLocalization.string("Chart"))
        }
    }

    private var goalTrendSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    showGoalSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "target")
                                .foregroundStyle(Color(hex: "#FCA311"))
                            Text(AppLocalization.string("Goal"))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppTypography.micro)
                                .foregroundStyle(.secondary)
                        }

                        if let goal = currentGoal {
                            Text(AppLocalization.string("metric.goal.update.value", valueString(goal.targetValue)))
                                .font(AppTypography.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text(AppLocalization.string("Set a target"))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentGoal == nil ? AppLocalization.string("accessibility.goal.set") : AppLocalization.string("accessibility.goal.update"))
                .accessibilityHint(AppLocalization.string("accessibility.goal.define"))

                Button {
                    showTrendline.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(Color(hex: "#FCA311"))
                            Text(AppLocalization.string("Trend"))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(.primary)
                            Spacer()
                        }

                        Text(showTrendline ? AppLocalization.string("Visible") : AppLocalization.string("Hidden"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("accessibility.trendline"))
                .accessibilityValue(showTrendline ? AppLocalization.string("accessibility.visible") : AppLocalization.string("accessibility.hidden"))
                .accessibilityHint(AppLocalization.string("accessibility.trendline.toggle"))
            }
            .swipeActions {
                if currentGoal != nil {
                    Button(role: .destructive) {
                        deleteGoal()
                    } label: {
                        Label(AppLocalization.string("Delete Goal"), systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(AppLocalization.string("Goal & Trend"))
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let goal = currentGoal, let latest = samples.last {
            Section {
                GoalProgressView(
                    goal: goal,
                    latest: latest,
                    baselineValue: baselineValue(for: goal)
                ) { value in
                    valueString(value)
                }
            } header: {
                Text(AppLocalization.string("Progress"))
            }
        }
    }

    private var photosSection: some View {
        Section {
            if relatedPhotos.isEmpty {
                Text(AppLocalization.string("No related photos yet."))
                    .foregroundStyle(.secondary)
            } else {
                MetricPhotosRow(photos: visiblePhotos)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            HStack {
                Text(AppLocalization.string("Photos"))
                Spacer()
                if relatedPhotos.count > 3, let tag = relatedTag {
                    Button(AppLocalization.string("View More")) {
                        photosFilterTag = tag.rawValue
                        router.selectedTab = .photos
                    }
                    .font(AppTypography.sectionAction)
                    .accessibilityLabel(AppLocalization.string("View more photos"))
                    .accessibilityHint(AppLocalization.string("accessibility.photos.filtered"))
                }
            }
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [2, 4]))
                            .frame(width: 22, height: 2)
                        Text(AppLocalization.string("Trend"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if currentGoal != nil {
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(Color(hex: "#E5E5E5"))
                            .frame(width: 22, height: 2)
                        Text(AppLocalization.string("Goal"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color(hex: "#1C1C1E"))
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
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
                }
            }

            ForEach(chartSamples, id: \.persistentModelID) { s in
                AreaMark(
                    x: .value("Date", s.date),
                    y: .value("Value", displayValue(s.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FCA311").opacity(0.1),
                            Color(hex: "#FCA311").opacity(0.0)
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
                .foregroundStyle(Color(hex: "#FCA311"))

                PointMark(
                    x: .value("Date", s.date),
                    y: .value("Value", displayValue(s.value))
                )
                .symbol(Circle())
                .symbolSize(20)
                .foregroundStyle(Color(hex: "#FCA311"))
            }

            if let goal = currentGoal {
                let goalValue = displayValue(goal.targetValue)
                RuleMark(y: .value("Goal", goalValue))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color(hex: "#E5E5E5"))
            }

            if let scrubbedSample {
                let scrubbedValue = displayValue(scrubbedSample.value)
                RuleMark(x: .value("Selected Date", scrubbedSample.date))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Selected Date", scrubbedSample.date),
                    y: .value("Selected Value", scrubbedValue)
                )
                .symbol(Circle())
                .symbolSize(58)
                .foregroundStyle(Color.white)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisTick().foregroundStyle(.white.opacity(0.2))
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.12))
                AxisTick().foregroundStyle(.white.opacity(0.2))
                AxisValueLabel()
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 168)
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .allowsHitTesting(isChartScrubbingEnabled)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    if let drag {
                                        updateScrubbedSample(at: drag.location, proxy: proxy, geometry: geometry)
                                    }
                                default:
                                    break
                                }
                            }
                            .onEnded { _ in
                                scrubbedSample = nil
                            }
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            if let scrubbedSample {
                HStack(spacing: 8) {
                    Text(scrubbedSample.date.formatted(date: .abbreviated, time: .omitted))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(valueString(scrubbedSample.value))
                        .font(AppTypography.microEmphasis.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                )
                .padding(.top, 6)
                .padding(.leading, 6)
            }
        }
        .clipped()
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
        guard chartSamples.count >= 2 else { return nil }
        
        let sorted = chartSamples.sorted { $0.date < $1.date }
        let times = sorted.map { $0.date.timeIntervalSinceReferenceDate }
        let values = sorted.map { displayValue($0.value) }
        
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
              let firstSample = sorted.first, let lastSample = sorted.last else { return nil }
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
        var values = chartSamples.map { displayValue($0.value) }
        
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
        guard !chartSamples.isEmpty else {
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

        scrubbedSample = chartSamples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}
// Extension methods are defined in MetricDetailComponents.swift

