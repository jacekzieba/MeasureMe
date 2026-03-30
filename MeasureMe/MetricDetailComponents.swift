import SwiftUI
import Charts
import Accessibility
import SwiftData
import Foundation

@available(iOS 16.0, *)
extension MetricDetailView {
    var chartDescriptor: AXChartDescriptor {
        let unit = kind.unitSymbol(unitsSystem: self.unitsSystem)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let points: [(String, Double)] = chartRenderSamples.map { sample in
            let label = dateFormatter.string(from: sample.date)
            return (label, displayValue(sample.value))
        }

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: AppLocalization.string("Date"),
            categoryOrder: points.map(\.0)
        )

        let values = points.map(\.1)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1

        let yAxis = AXNumericDataAxisDescriptor(
            title: "\(kind.title) (\(unit))",
            range: minValue...maxValue,
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                kind.formattedDisplayValue(value, unitsSystem: unitsSystem)
            }
        )

        let series = AXDataSeriesDescriptor(
            name: kind.title,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.0, y: $0.1) }
        )

        let minText = kind.formattedDisplayValue(minValue, unitsSystem: unitsSystem)
        let maxText = kind.formattedDisplayValue(maxValue, unitsSystem: unitsSystem)
        let trendText = trendlineSegment?.endValue == trendlineSegment?.startValue
            ? AppLocalization.string("trend.steady")
            : ((trendlineSegment?.endValue ?? 0) > (trendlineSegment?.startValue ?? 0)
               ? AppLocalization.string("trend.up")
               : AppLocalization.string("trend.down"))
        let summary = AppLocalization.string(
            "chart.summary.metric",
            kind.title,
            timeframeLabel.lowercased(),
            minText,
            maxText,
            trendText
        )
        return AXChartDescriptor(
            title: AppLocalization.string("chart.title.metric", kind.title),
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    /// Określa dynamiczną pozycję etykiety celu na wykresie
    func goalLabelPosition(for goalValue: Double) -> AnnotationPosition {
        let minV = yDomain.lowerBound
        let maxV = yDomain.upperBound
        let span = max(maxV - minV, 0.0001)
        let rel = (goalValue - minV) / span
        if rel > 0.85 { return .bottom }
        if rel < 0.15 { return .top }
        return .top
    }

    /// Minimalny span dla osi Y - zapewnia czytelność gdy dane są bardzo zbliżone
    func minimalSpan(for kind: MetricKind) -> Double {
        Self.minimalSpan(for: kind)
    }

    static func minimalSpan(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent: return 1.0
        case .weight, .length: return 1.0
        }
    }

    /// Minimalny padding dla osi Y - zapewnia margines wokół danych
    func minimalPadding(for kind: MetricKind) -> Double {
        Self.minimalPadding(for: kind)
    }

    static func minimalPadding(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent: return 1.0
        case .weight, .length: return 0.5
        }
    }

    var insightInput: MetricInsightInput? {
        guard supportsAppleIntelligence, let latest = sortedSamplesAscending.last else { return nil }
        let recent14 = sortedSamplesAscending.filterInLast(days: 14)
        let recent30 = sortedSamplesAscending.filterInLast(days: 30)
        let recent90 = sortedSamplesAscending.filterInLast(days: 90)
        return MetricInsightInput(
            userName: userName.isEmpty ? nil : userName,
            metricTitle: kind.englishTitle,
            measurementContext: kind.insightMeasurementContext,
            latestValueText: valueString(latest.value),
            timeframeLabel: "Last 90 days",
            sampleCount: recent90.count,
            delta7DaysText: nil,
            delta14DaysText: recent14.deltaText(days: 14, kind: kind, unitsSystem: unitsSystem),
            delta30DaysText: recent30.deltaText(days: 30, kind: kind, unitsSystem: unitsSystem),
            delta90DaysText: recent90.deltaText(days: 90, kind: kind, unitsSystem: unitsSystem),
            goalStatusText: goalStatusText,
            goalDirectionText: currentGoal?.direction.rawValue,
            defaultFavorableDirectionText: kind.defaultFavorableDirectionWhenNoGoal.rawValue
        )
    }

    var goalStatusText: String? {
        guard let goal = currentGoal, let latest = samples.last else { return nil }
        if goal.isAchieved(currentValue: latest.value) {
            return "Goal reached"
        }
        let remaining = displayValue(abs(goal.remainingToGoal(currentValue: latest.value)))
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return "\(remaining) \(unit) away from goal"
    }

    var goalPredictionResult: GoalPredictionResult? {
        guard let goal = currentGoal else { return nil }
        return GoalPredictionEngine.predict(samples: samples, goal: goal)
    }

    var goalForecastText: String? {
        guard let result = goalPredictionResult else { return nil }
        switch result {
        case .achieved:
            return AppLocalization.string("Goal already achieved.")
        case .onTrack(let date):
            let formatted = date.formatted(date: .abbreviated, time: .omitted)
            return AppLocalization.string("metric.goal.projected.date", formatted)
        case .trendOpposite:
            return AppLocalization.string("metric.goal.trend.opposite")
        case .flatTrend:
            return AppLocalization.string("metric.goal.trend.flat")
        case .tooFarOut:
            return AppLocalization.string("metric.goal.trend.too_far")
        case .insufficientData:
            return nil
        }
    }

    // MARK: - Weight Prediction Rates

    var weightPredictionRates: GoalPredictionEngine.WeightPredictionRates? {
        guard kind == .weight, let goal = currentGoal else { return nil }
        return GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)
    }

    func formattedWeeklyRate(_ metricRatePerWeek: Double) -> String {
        let displayRate = displayValue(metricRatePerWeek)
        let formatted = kind.formattedDisplayValue(displayRate, unitsSystem: unitsSystem)
        return formatted
    }

    func updateCommitmentRate(_ displayRate: Double) {
        guard let goal = currentGoal else { return }
        let metricRate = kind.valueToMetric(fromDisplay: displayRate, unitsSystem: unitsSystem)
        goal.commitmentWeeklyRate = abs(metricRate)
    }

    var insightTrendlineSegment: (startDate: Date, startValue: Double, endDate: Date, endValue: Double)? {
        let recent90 = sortedSamplesAscending.filterInLast(days: 90)
        guard recent90.count >= 2 else { return nil }

        let times = recent90.map { $0.date.timeIntervalSinceReferenceDate }
        let values = recent90.map { displayValue($0.value) }
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
              let firstSample = recent90.first, let lastSample = recent90.last else { return nil }
        return (
            startDate: firstSample.date,
            startValue: slope * startTime + intercept,
            endDate: lastSample.date,
            endValue: slope * endTime + intercept
        )
    }

    func baselineValue(for goal: MetricGoal) -> Double {
        // Priorytet: użytkownik podał jawny punkt startowy
        if let sv = goal.startValue { return sv }

        // Stare zachowanie: ostatnia próbka ≤ daty utworzenia celu
        let sorted = sortedSamplesAscending
        guard !sorted.isEmpty else { return latestSampleValue ?? goal.targetValue }
        if let baseline = sorted.last(where: { $0.date <= goal.createdDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? (latestSampleValue ?? goal.targetValue)
    }

    var latestSampleValue: Double? {
        samples.last?.value
    }

    var timeframeLabel: String {
        switch timeframe {
        case .week: return AppLocalization.string("Last 7 days")
        case .month: return AppLocalization.string("Last 30 days")
        case .threeMonths: return AppLocalization.string("Last 90 days")
        case .year: return AppLocalization.string("Last year")
        case .all: return AppLocalization.string("All time")
        }
    }

    @MainActor
    func refreshInsight() async {
        guard let input = insightInput else { return }
        await MetricInsightService.shared.invalidate(for: input.metricTitle)
        await loadInsightIfNeeded()
    }

    @MainActor
    func loadInsightIfNeeded() async {
        guard supportsAppleIntelligence else {
            isLoadingInsight = false
            return
        }

        guard let input = insightInput else {
            insightState = .fallback(AppLocalization.string("Not enough data to generate insights yet."))
            isLoadingInsight = false
            return
        }

        if case .ready = insightState {
            // stale-while-revalidate: keep previous insight visible while refreshing
        } else {
            insightState = .loading
        }
        isLoadingInsight = true
        let generated = await MetricInsightService.shared.generateInsight(for: input)
        let baseText = generated?.detailedText ?? ""
        let trimmed = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            insightState = .fallback(AppLocalization.string("Couldn't generate an insight right now. Please try again in a moment."))
        } else {
            insightState = .ready(trimmed)
        }
        isLoadingInsight = false
    }

    // MARK: - Data Management
    
    /// Dodaje nową próbkę do bazy danych
    func add(date: Date, value: Double) {
        let previousMetricCount = AnalyticsFirstEventTracker.metricCount(in: context)
        let sample = MetricSample(kind: kind, value: value, date: date)
        context.insert(sample)
        AnalyticsFirstEventTracker.trackFirstMetricIfNeeded(previousMetricCount: previousMetricCount)
        NotificationManager.shared.recordMeasurement(kinds: [kind], date: date)
        NotificationManager.shared.scheduleAINotificationsIfNeeded(
            context: context,
            trigger: .manualLog(kinds: [kind])
        )
        if let goal = currentGoal, goal.isAchieved(currentValue: value) {
            NotificationManager.shared.sendGoalAchievedNotification(
                kind: kind,
                goalCreatedDate: goal.createdDate,
                goalValue: goal.targetValue
            )
        }
        ReviewRequestManager.recordMetricEntryAdded(count: 1)
        // SwiftData automatycznie zapisuje zmiany
    }

    /// Otwiera sheet edycji próbki
    func edit(sample: MetricSample) {
        editingSample = sample
    }

    /// Usuwa próbkę z bazy danych
    func delete(sample: MetricSample) {
        context.delete(sample)
        WidgetDataWriter.writeAndReload(kinds: [kind], context: context, unitsSystem: unitsSystem)
    }
    
    /// Ustawia lub aktualizuje cel dla metryki.
    /// - Parameters:
    ///   - targetValue: Wartość docelowa w jednostkach bazowych
    ///   - direction: Kierunek celu (increase/decrease)
    ///   - startValue: Opcjonalna wartość startowa w jednostkach bazowych — punkt zerowy postępu.
    ///                 Gdy nil, baseline obliczany jest dynamicznie z historii próbek (stare zachowanie).
    ///   - startDate:  Opcjonalna data startowa — zapisywana razem z startValue jako MetricSample.
    func setGoal(targetValue: Double, direction: MetricGoal.Direction,
                 startValue: Double? = nil, startDate: Date? = nil) {
        MetricGoalStore.upsertGoal(
            kind: kind,
            targetValue: targetValue,
            direction: direction,
            startValue: startValue,
            startDate: startDate,
            in: context,
            existingGoal: currentGoal,
            existingSamples: samples
        )
        try? context.save()
        WidgetDataWriter.writeAndReload(kinds: [kind], context: context, unitsSystem: unitsSystem)
    }
    
    /// Usuwa cel z bazy danych
    func deleteGoal() {
        if let goal = currentGoal {
            context.delete(goal)
            try? context.save()
            WidgetDataWriter.writeAndReload(kinds: [kind], context: context, unitsSystem: unitsSystem)
        }
    }
}

private extension Array where Element == MetricSample {
    func filterInLast(days: Int, now: Date = AppClock.now) -> [MetricSample] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return self }
        return filter { $0.date >= start }
    }
}

@available(iOS 16.0, *)
struct MetricChartAXDescriptor: AXChartDescriptorRepresentable {
    let descriptor: AXChartDescriptor

    func makeChartDescriptor() -> AXChartDescriptor {
        descriptor
    }
}

struct MetricComparisonOption: Identifiable, Equatable {
    let kind: MetricKind
    let latestSample: MetricSample?
    let sampleCount: Int
    let usesSecondaryAxis: Bool
    let isRecommended: Bool

    var id: String { kind.rawValue }
}

struct MetricCompareSheet: View {
    let currentKind: MetricKind
    let selectedKind: MetricKind?
    let options: [MetricComparisonOption]
    @Binding var timeframe: MetricDetailView.Timeframe
    let unitsSystem: String
    let primarySamples: [MetricSample]
    let comparisonSamples: [MetricSample]
    let primaryColor: Color
    let comparisonColor: Color
    let usesSecondaryAxis: Bool
    let primaryAxisDomain: ClosedRange<Double>
    let secondaryAxisValues: [Double]
    let primaryDisplayValue: (Double) -> Double
    let comparisonDisplayValue: (Double) -> Double
    let onSelect: (MetricKind) -> Void
    let onClear: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isPickerExpanded: Bool
    @State private var scrubbedDate: Date?

    init(
        currentKind: MetricKind,
        selectedKind: MetricKind?,
        options: [MetricComparisonOption],
        timeframe: Binding<MetricDetailView.Timeframe>,
        unitsSystem: String,
        primarySamples: [MetricSample],
        comparisonSamples: [MetricSample],
        primaryColor: Color,
        comparisonColor: Color,
        usesSecondaryAxis: Bool,
        primaryAxisDomain: ClosedRange<Double>,
        secondaryAxisValues: [Double],
        primaryDisplayValue: @escaping (Double) -> Double,
        comparisonDisplayValue: @escaping (Double) -> Double,
        onSelect: @escaping (MetricKind) -> Void,
        onClear: (() -> Void)?
    ) {
        self.currentKind = currentKind
        self.selectedKind = selectedKind
        self.options = options
        self._timeframe = timeframe
        self.unitsSystem = unitsSystem
        self.primarySamples = primarySamples
        self.comparisonSamples = comparisonSamples
        self.primaryColor = primaryColor
        self.comparisonColor = comparisonColor
        self.usesSecondaryAxis = usesSecondaryAxis
        self.primaryAxisDomain = primaryAxisDomain
        self.secondaryAxisValues = secondaryAxisValues
        self.primaryDisplayValue = primaryDisplayValue
        self.comparisonDisplayValue = comparisonDisplayValue
        self.onSelect = onSelect
        self.onClear = onClear
        _isPickerExpanded = State(initialValue: selectedKind == nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("metric.compare.sheet.title"))
                            .font(AppTypography.displaySection)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(AppLocalization.string("metric.compare.sheet.subtitle", currentKind.title))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            isPickerExpanded.toggle()
                        }
                    } label: {
                        selectionRow
                    }
                    .buttonStyle(.plain)

                    timeframeSelector

                    if isPickerExpanded || selectedKind == nil {
                        if options.isEmpty {
                            EmptyStateCard(
                                title: AppLocalization.string("metric.compare.empty.title"),
                                message: AppLocalization.string("metric.compare.empty.message"),
                                systemImage: "chart.line.uptrend.xyaxis"
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(AppLocalization.string("metric.compare.sheet.section"))
                                    .font(AppTypography.eyebrow)
                                    .foregroundStyle(AppColorRoles.textSecondary)

                                ForEach(options) { option in
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                            onSelect(option.kind)
                                            isPickerExpanded = false
                                        }
                                    } label: {
                                        compareOptionRow(option)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("metric.compare.option.\(option.kind.rawValue)")
                                }
                            }
                        }
                    }

                    if let selectedKind, !comparisonSamples.isEmpty {
                        comparisonChartCard(selectedKind: selectedKind)
                    } else {
                        comparePlaceholderCard
                    }

                    if let selectedKind, let onClear {
                        Button {
                            onClear()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                Text(AppLocalization.string("metric.compare.clear.current", selectedKind.title))
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppColorRoles.surfaceInteractive)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func compareOptionRow(_ option: MetricComparisonOption) -> some View {
        let isSelected = option.kind == selectedKind

        return HStack(spacing: 12) {
            option.kind.iconView(font: AppTypography.iconMedium, size: 20, tint: AppColorRoles.compareAfter)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(AppColorRoles.compareAfter.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(option.kind.title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    if option.isRecommended {
                        compareBadge(AppLocalization.string("metric.compare.badge.recommended"))
                    } else if option.usesSecondaryAxis {
                        compareBadge(AppLocalization.string("metric.compare.badge.second_axis"))
                    }
                }

                if let latestSample = option.latestSample {
                    Text(option.kind.formattedMetricValue(fromMetric: latestSample.value, unitsSystem: unitsSystem))
                        .font(AppTypography.captionEmphasis.monospacedDigit())
                        .foregroundStyle(AppColorRoles.compareAfter)

                    Text(optionRowMeta(option: option, date: latestSample.date))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(AppTypography.iconMedium)
                .foregroundStyle(isSelected ? AppColorRoles.stateSuccess : AppColorRoles.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    private func compareBadge(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.microEmphasis)
            .foregroundStyle(AppColorRoles.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColorRoles.surfaceAccentSoft)
            )
    }

    private var selectionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("metric.compare.sheet.selector"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Text(selectedKind?.title ?? AppLocalization.string("metric.compare.cta.idle"))
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()

            Image(systemName: isPickerExpanded ? "chevron.up" : "chevron.down")
                .font(AppTypography.iconMedium)
                .foregroundStyle(AppColorRoles.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    private var comparePlaceholderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(AppTypography.iconMedium)
                .foregroundStyle(AppColorRoles.compareAfter)
            Text(AppLocalization.string("metric.compare.chart.empty"))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    private var timeframeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MetricDetailView.Timeframe.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            timeframe = option
                            scrubbedDate = nil
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(timeframe == option ? AppColorRoles.textPrimary : AppColorRoles.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(timeframe == option ? AppColorRoles.surfaceAccentSoft.opacity(1.2) : AppColorRoles.surfaceInteractive)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scrubbedPrimarySample: MetricSample? {
        nearestSample(to: scrubbedDate, in: primarySamples)
    }

    private var scrubbedComparisonSample: MetricSample? {
        nearestSample(to: scrubbedDate, in: comparisonSamples)
    }

    private var isChartScrubbingEnabled: Bool {
        !primarySamples.isEmpty || !comparisonSamples.isEmpty
    }

    private func comparisonChartCard(selectedKind: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                chartLegendItem(title: currentKind.title, color: primaryColor)
                chartLegendItem(title: selectedKind.title, color: comparisonColor)
                Spacer(minLength: 0)
            }

            Chart {
                ForEach(primarySamples, id: \.persistentModelID) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Value", primaryDisplayValue(sample.value))
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(.init(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(by: .value("Series", currentKind.title))

                    PointMark(
                        x: .value("Primary Point Date", sample.date),
                        y: .value("Primary Point Value", primaryDisplayValue(sample.value))
                    )
                    .symbol(Circle())
                    .symbolSize(18)
                    .foregroundStyle(primaryColor)
                }

                ForEach(comparisonSamples, id: \.persistentModelID) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Value", comparisonDisplayValue(sample.value))
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(.init(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(by: .value("Series", selectedKind.title))

                    PointMark(
                        x: .value("Comparison Point Date", sample.date),
                        y: .value("Comparison Point Value", comparisonDisplayValue(sample.value))
                    )
                    .symbol(Circle())
                    .symbolSize(18)
                    .foregroundStyle(comparisonColor)
                }

                if let scrubbedDate {
                    RuleMark(x: .value("Selected Date", scrubbedDate))
                        .foregroundStyle(AppColorRoles.textSecondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    if let scrubbedPrimarySample {
                        PointMark(
                            x: .value("Primary Selected Date", scrubbedPrimarySample.date),
                            y: .value("Primary Selected Value", primaryDisplayValue(scrubbedPrimarySample.value))
                        )
                        .symbol(Circle())
                        .symbolSize(48)
                        .foregroundStyle(primaryColor)
                    }

                    if let scrubbedComparisonSample {
                        PointMark(
                            x: .value("Comparison Selected Date", scrubbedComparisonSample.date),
                            y: .value("Comparison Selected Value", comparisonDisplayValue(scrubbedComparisonSample.value))
                        )
                        .symbol(Circle())
                        .symbolSize(48)
                        .foregroundStyle(comparisonColor)
                    }
                }
            }
            .chartForegroundStyleScale([
                currentKind.title: primaryColor,
                selectedKind.title: comparisonColor
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: primaryAxisDomain)
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
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(AppColorRoles.borderSubtle)
                    AxisTick().foregroundStyle(AppColorRoles.borderStrong)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(currentKind.formattedDisplayValue(number, unitsSystem: unitsSystem))
                                .font(AppTypography.micro)
                                .foregroundStyle(AppColorRoles.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 240)
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
                                    updateScrubbedDate(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateScrubbedDate(at: value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    scrubbedDate = nil
                                }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                if let scrubbedDate {
                    scrubbedOverlay(for: scrubbedDate, selectedKind: selectedKind)
                        .padding(.top, 6)
                        .padding(.leading, 6)
                }
            }
            .overlay(alignment: .trailing) {
                if usesSecondaryAxis {
                    secondaryAxisColumn
                        .padding(.trailing, 4)
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }

    @ViewBuilder
    private func scrubbedOverlay(for date: Date, selectedKind: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textSecondary)

            HStack(spacing: 10) {
                if let scrubbedPrimarySample {
                    scrubbedValueChip(
                        title: currentKind.title,
                        value: currentKind.formattedMetricValue(fromMetric: scrubbedPrimarySample.value, unitsSystem: unitsSystem),
                        color: primaryColor
                    )
                }

                if let scrubbedComparisonSample {
                    scrubbedValueChip(
                        title: selectedKind.title,
                        value: selectedKind.formattedMetricValue(fromMetric: scrubbedComparisonSample.value, unitsSystem: unitsSystem),
                        color: comparisonColor
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColorRoles.surfaceCanvas.opacity(0.72))
        )
    }

    private func scrubbedValueChip(title: String, value: String, color: Color) -> some View {
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

    private func chartLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(color)
                .frame(width: 18, height: 4)
            Text(title)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
        }
    }

    private func optionRowMeta(option: MetricComparisonOption, date: Date) -> String {
        let axisKey = option.usesSecondaryAxis
            ? "metric.compare.option.meta.dual"
            : "metric.compare.option.meta.shared"
        return AppLocalization.string(
            axisKey,
            option.sampleCount,
            date.formatted(date: .abbreviated, time: .omitted)
        )
    }

    @ViewBuilder
    private var secondaryAxisColumn: some View {
        if let selectedKind, !secondaryAxisValues.isEmpty {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(secondaryAxisValues.enumerated()), id: \.offset) { index, value in
                    Text(selectedKind.formattedDisplayValue(value, unitsSystem: unitsSystem))
                        .font(AppTypography.micro)
                        .foregroundStyle(comparisonColor)
                    if index < secondaryAxisValues.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
        }
    }

    private func updateScrubbedDate(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard isChartScrubbingEnabled, let plotFrame = proxy.plotFrame else {
            scrubbedDate = nil
            return
        }

        let plotOrigin = geometry[plotFrame].origin
        let xPosition = location.x - plotOrigin.x
        guard xPosition >= 0, xPosition <= proxy.plotSize.width else {
            scrubbedDate = nil
            return
        }

        scrubbedDate = proxy.value(atX: xPosition, as: Date.self)
    }

    private func nearestSample(to date: Date?, in samples: [MetricSample]) -> MetricSample? {
        guard let date, !samples.isEmpty else { return nil }
        return samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }
}

struct MetricPhotosRow: View {
    let photos: [PhotoEntry]
    @State private var availableWidth: CGFloat = 0
    @Environment(\.modelContext) private var modelContext

    private let spacing: CGFloat = 8

    private var side: CGFloat {
        let totalSpacing = spacing * 2
        let width = availableWidth > 0 ? availableWidth : 0
        let raw = (width - totalSpacing) / 3
        return max(floor(raw), 86)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: 3),
            spacing: spacing
        ) {
            ForEach(photos) { photo in
                DownsampledImageView(
                    imageData: photo.preferredGridImageData,
                    targetSize: CGSize(width: side, height: side),
                    contentMode: .fill,
                    cornerRadius: 12,
                    showsProgress: false,
                    cacheID: String(describing: photo.id)
                )
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear {
                    guard photo.thumbnailData == nil else { return }
                    guard !UITestArgument.isPresent(.mode) else { return }
                    Task {
                        await PhotoThumbnailBackfillService.shared.enqueueIfNeeded(
                            photoID: photo.persistentModelID,
                            originalImageData: photo.imageData,
                            existingThumbnailData: photo.thumbnailData,
                            modelContainer: modelContext.container,
                            source: "metric_detail"
                        )
                    }
                }
            }
        }
        .frame(height: {
            let rows = max(1, Int(ceil(Double(photos.count) / 3.0)))
            return CGFloat(rows) * side + CGFloat(max(rows - 1, 0)) * spacing
        }())
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { availableWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }
}

struct GoalProgressView: View {
    let goal: MetricGoal
    let latest: MetricSample
    let baselineValue: Double
    let format: (Double) -> String

    var body: some View {
        let currentVal = latest.value
        let goalVal = goal.targetValue
        let progress: Double
        let isAchieved: Bool
        switch goal.direction {
        case .increase:
            let denominator = goalVal - baselineValue
            if denominator <= 0 {
                // Cel poniżej lub równy baseline — kierunek bez sensu geometrycznego.
                // Progress = 0, cel nieaktywny dopóki baseline nie zostanie skorygowany.
                progress = 0.0
                isAchieved = false
            } else {
                let raw = (currentVal - baselineValue) / denominator
                progress = min(max(raw, 0.0), 1.0)
                isAchieved = progress >= 1.0
            }
        case .decrease:
            let denominator = baselineValue - goalVal
            if denominator <= 0 {
                // Cel powyżej lub równy baseline — analogiczny błąd geometryczny.
                progress = 0.0
                isAchieved = false
            } else {
                let raw = (baselineValue - currentVal) / denominator
                progress = min(max(raw, 0.0), 1.0)
                isAchieved = progress >= 1.0
            }
        }
        return ProgressViewCard(
            isAchieved: isAchieved,
            progress: progress,
            percentage: Int(progress * 100),
            currentValueString: format(currentVal),
            goalValueString: format(goalVal),
            directionUp: goal.direction == .increase
        )
    }
}

struct ProgressViewCard: View {
    private let measurementsTheme = FeatureTheme.measurements
    let isAchieved: Bool
    let progress: Double
    let percentage: Int
    let currentValueString: String
    let goalValueString: String
    let directionUp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string("Progress"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                Spacer()
                Text("\(percentage)%")
                    .font(AppTypography.dataCompact)
                    .monospacedDigit()
                    .foregroundStyle(isAchieved ? AppColorRoles.stateSuccess : measurementsTheme.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColorRoles.surfaceInteractive)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: isAchieved ? [
                                    AppColorRoles.stateSuccess,
                                    AppColorRoles.stateSuccess.opacity(0.8)
                                ] : [
                                    measurementsTheme.accent,
                                    measurementsTheme.accent.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                }
            }
            .frame(height: 8)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Current"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    Text(currentValueString)
                        .font(AppTypography.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                }

                Spacer()

                Image(systemName: directionUp ? "arrow.up" : "arrow.down")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textTertiary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppLocalization.string("Goal"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    Text(goalValueString)
                        .font(AppTypography.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("Progress"))
        .accessibilityValue("\(percentage)%")
        .accessibilityHint(AppLocalization.string("accessibility.progress.hint", currentValueString, goalValueString))
    }
}

// MARK: - Add Metric Sample View

/// **AddMetricSampleView**
/// Sheet do dodawania nowej próbki metryki.
///
/// **Funkcje:**
/// - Wybór daty i czasu pomiaru
/// - Wprowadzanie wartości w odpowiednich jednostkach (metric/imperial)
/// - Walidacja wartości procentowych (0-100)
/// - Automatyczna konwersja jednostek przed zapisem
struct AddMetricSampleView: View {
    let kind: MetricKind
    var onAdd: (Date, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @FocusState private var isValueFocused: Bool

    @State private var date: Date = .now
    @State private var displayValue: Double

    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    init(kind: MetricKind, defaultMetricValue: Double? = nil, onAdd: @escaping (Date, Double) -> Void) {
        self.kind = kind
        self.onAdd = onAdd

        // Konwertuj domyślną wartość na jednostki wyświetlania
        let units = AppSettingsStore.shared.snapshot.profile.unitsSystem
        if let metric = defaultMetricValue {
            _displayValue = State(initialValue: kind.valueForDisplay(fromMetric: metric, unitsSystem: units))
        } else {
            _displayValue = State(initialValue: 0)
        }
    }

    private var valueValidation: MetricInputValidator.ValidationResult {
        MetricInputValidator.validateMetricDisplayValue(
            displayValue,
            kind: kind,
            unitsSystem: unitsSystem
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 220)

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Hero value card
                        AppGlassCard(
                            depth: .floating,
                            tint: Color.cyan.opacity(0.12),
                            contentPadding: 24
                        ) {
                            VStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    TextField("", value: $displayValue, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                        .fixedSize()
                                        .focused($isValueFocused)
                                        .accessibilityLabel(AppLocalization.string("Goal value"))
                                        .accessibilityIdentifier("goal.input.value")
                                        .accessibilityIdentifier("goal.input.value")

                                    Text(kind.unitSymbol(unitsSystem: unitsSystem))
                                        .font(.title.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                if !isValueFocused {
                                    Text(AppLocalization.string("metric.input.tap_to_edit"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 140)
                            .contentShape(Rectangle())
                            .onTapGesture { isValueFocused = true }
                        }

                        // Walidacja pod kartą
                        if !valueValidation.isValid, let message = valueValidation.message {
                            Text(message)
                                .font(AppTypography.micro)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // MARK: - Date card
                        AppGlassCard(depth: .base) {
                            DatePicker(
                                AppLocalization.string("Date"),
                                selection: $date,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(AppLocalization.string("metric.add.title", kind.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Add")) {
                        Haptics.light()
                        // Konwersja z jednostek wyświetlanych na bazowe (metryczne)
                        let metric = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                        onAdd(date, metric)
                        WidgetDataWriter.writeAndReload(kinds: [kind], context: context, unitsSystem: unitsSystem)
                        dismiss()
                    }
                    .disabled(!valueValidation.isValid)
                }
            }
        }
    }
}

// MARK: - Edit Metric Sample View

/// **EditMetricSampleView**
/// Sheet do edycji istniejącej próbki metryki.
///
/// **Funkcje:**
/// - Modyfikacja daty i czasu pomiaru
/// - Zmiana wartości w odpowiednich jednostkach
/// - Walidacja wartości procentowych
/// - Bezpośrednia aktualizacja obiektu SwiftData
struct EditMetricSampleView: View {
    let kind: MetricKind
    let sample: MetricSample

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @FocusState private var isValueFocused: Bool
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    @State private var date: Date
    @State private var displayValue: Double

    init(kind: MetricKind, sample: MetricSample) {
        self.kind = kind
        self.sample = sample

        // Inicjalizacja stanu z istniejących wartości
        _date = State(initialValue: sample.date)
        _displayValue = State(
            initialValue: kind.valueForDisplay(
                fromMetric: sample.value,
                unitsSystem: AppSettingsStore.shared.snapshot.profile.unitsSystem
            )
        )
    }

    private var valueValidation: MetricInputValidator.ValidationResult {
        MetricInputValidator.validateMetricDisplayValue(
            displayValue,
            kind: kind,
            unitsSystem: unitsSystem
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 220, tint: Color.cyan.opacity(0.18))

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Hero value card
                        AppGlassCard(
                            depth: .floating,
                            tint: Color.cyan.opacity(0.12),
                            contentPadding: 24
                        ) {
                            VStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    TextField("", value: $displayValue, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                        .fixedSize()
                                        .focused($isValueFocused)
                                        .accessibilityLabel(AppLocalization.string("Goal value"))
                                        .accessibilityIdentifier("goal.input.value")

                                    Text(kind.unitSymbol(unitsSystem: unitsSystem))
                                        .font(.title.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                if !isValueFocused {
                                    Text(AppLocalization.string("metric.input.tap_to_edit"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 140)
                            .accessibilityIdentifier("goal.input.card")
                            .contentShape(Rectangle())
                            .onTapGesture { isValueFocused = true }
                        }

                        // Walidacja pod kartą
                        if !valueValidation.isValid, let message = valueValidation.message {
                            Text(message)
                                .font(AppTypography.micro)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // MARK: - Date card
                        AppGlassCard(depth: .base) {
                            DatePicker(
                                AppLocalization.string("Date"),
                                selection: $date,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(AppLocalization.string("metric.edit.title", kind.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
                        // Konwersja i bezpośrednia aktualizacja próbki SwiftData
                        let metric = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                        sample.value = metric
                        sample.date = date
                        WidgetDataWriter.writeAndReload(kinds: [kind], context: context, unitsSystem: unitsSystem)
                        dismiss()
                    }
                    .disabled(!valueValidation.isValid)
                }
            }
        }
    }
}

// MARK: - Set Goal View

/// **SetGoalView**
/// Sheet do ustawiania lub aktualizacji celu dla metryki.
///
/// **Funkcje:**
/// - Ustawianie nowego celu
/// - Wybór kierunku celu (increase/decrease)
/// - Aktualizacja istniejącego celu
/// - Walidacja wartości procentowych
/// - Pomocny opis funkcjonalności celów
///
/// **UI:**
/// - Tytuł zmienia się w zależności czy cel istnieje
/// - Przycisk potwierdzenia również się dostosowuje
struct SetGoalView: View {
    let kind: MetricKind
    let currentGoal: MetricGoal?
    /// Ostatnia znana wartość metryki (jednostki bazowe) — używana jako domyślny punkt startowy.
    /// Gdy nil (brak historii), użytkownik musi wpisać wartość startową ręcznie.
    let latestMetricValue: Double?
    var onSet: (Double, MetricGoal.Direction, Double?, Date?) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @FocusState private var isValueFocused: Bool
    @FocusState private var isStartValueFocused: Bool

    @State private var displayValue: Double
    @State private var direction: MetricGoal.Direction
    @State private var showDeleteConfirmation = false
    @State private var startDisplayValue: Double
    @State private var startDate: Date
    @State private var useCustomStart: Bool

    init(kind: MetricKind, currentGoal: MetricGoal?, latestMetricValue: Double?,
         onSet: @escaping (Double, MetricGoal.Direction, Double?, Date?) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.kind = kind
        self.currentGoal = currentGoal
        self.latestMetricValue = latestMetricValue
        self.onSet = onSet
        self.onDelete = onDelete

        // Załaduj istniejący cel lub zacznij od zera
        let units = AppSettingsStore.shared.snapshot.profile.unitsSystem
        if let goal = currentGoal {
            _displayValue = State(initialValue: kind.valueForDisplay(fromMetric: goal.targetValue, unitsSystem: units))
            _direction = State(initialValue: goal.direction)
            // Punkt startowy: istniejący cel może mieć startValue
            if let sv = goal.startValue {
                _startDisplayValue = State(initialValue: kind.valueForDisplay(fromMetric: sv, unitsSystem: units))
                _startDate = State(initialValue: goal.startDate ?? .now)
                _useCustomStart = State(initialValue: true)
            } else if let latest = latestMetricValue {
                _startDisplayValue = State(initialValue: kind.valueForDisplay(fromMetric: latest, unitsSystem: units))
                _startDate = State(initialValue: .now)
                _useCustomStart = State(initialValue: false)
            } else {
                _startDisplayValue = State(initialValue: 0)
                _startDate = State(initialValue: .now)
                _useCustomStart = State(initialValue: false)
            }
        } else {
            _displayValue = State(initialValue: 0)
            // Domyślny kierunek zależny od typu metryki
            _direction = State(initialValue: SetGoalView.defaultDirection(for: kind))
            // Punkt startowy: domyślnie wyłączony (user włącza jeśli chce)
            if let latest = latestMetricValue {
                _startDisplayValue = State(initialValue: kind.valueForDisplay(fromMetric: latest, unitsSystem: units))
                _startDate = State(initialValue: .now)
                _useCustomStart = State(initialValue: false)
            } else {
                _startDisplayValue = State(initialValue: 0)
                _startDate = State(initialValue: .now)
                _useCustomStart = State(initialValue: false)
            }
        }
    }

    private var valueValidation: MetricInputValidator.ValidationResult {
        MetricInputValidator.validateMetricDisplayValue(
            displayValue,
            kind: kind,
            unitsSystem: unitsSystem
        )
    }

    private var startValueValidation: MetricInputValidator.ValidationResult {
        guard useCustomStart else { return .valid }
        return MetricInputValidator.validateMetricDisplayValue(
            startDisplayValue,
            kind: kind,
            unitsSystem: unitsSystem
        )
    }

    private var isFormValid: Bool {
        valueValidation.isValid && startValueValidation.isValid
    }

    /// Czy metryka nie ma żadnej historii pomiarów (i nie ma istniejącego celu ze startValue)
    private var hasNoHistory: Bool {
        latestMetricValue == nil && (currentGoal?.startValue == nil)
    }

    /// Określa domyślny kierunek celu dla danej metryki
    private static func defaultDirection(for kind: MetricKind) -> MetricGoal.Direction {
        switch kind {
        case .weight, .bodyFat, .waist, .neck, .bust, .chest, .hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return .decrease  // Zwykle chcemy zmniejszyć
        case .height, .leanBodyMass, .shoulders, .leftBicep, .rightBicep, .leftForearm, .rightForearm:
            return .increase  // Zwykle chcemy zwiększyć
        }
    }

    private var isUITestMode: Bool {
        UITestArgument.isPresent(.mode)
    }

    private func dismissKeyboard() {
        isValueFocused = false
        isStartValueFocused = false
    }

    private var goalInputTextBinding: Binding<String> {
        Binding(
            get: {
                if displayValue == 0 { return "" }
                return String(displayValue)
            },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                displayValue = Double(normalized) ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 220, tint: Color.cyan.opacity(0.18))

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Direction picker card
                        AppGlassCard(
                            depth: .floating,
                            tint: Color.cyan.opacity(0.12),
                            contentPadding: 20
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(AppLocalization.string("Direction"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)

                                Picker(AppLocalization.string("Goal type"), selection: $direction) {
                                    Label(AppLocalization.string("Decrease"), systemImage: "arrow.down")
                                        .tag(MetricGoal.Direction.decrease)
                                    Label(AppLocalization.string("Increase"), systemImage: "arrow.up")
                                        .tag(MetricGoal.Direction.increase)
                                }
                                .pickerStyle(.segmented)

                                Text(AppLocalization.string("Choose whether you want to increase or decrease this metric."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // MARK: - Hero value card (cel docelowy)
                        AppGlassCard(
                            depth: .floating,
                            tint: Color.cyan.opacity(0.12),
                            contentPadding: 24
                        ) {
                            VStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    TextField("", value: $displayValue, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                        .fixedSize()
                                        .focused($isValueFocused)
                                        .accessibilityLabel(AppLocalization.string("Goal value"))
                                        .accessibilityIdentifier("goal.input.value")

                                    Text(kind.unitSymbol(unitsSystem: unitsSystem))
                                        .font(.title.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }

                                if !isValueFocused {
                                    Text(AppLocalization.string("metric.input.tap_to_edit"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 140)
                            .accessibilityIdentifier("goal.input.card")
                            .contentShape(Rectangle())
                            .onTapGesture { isValueFocused = true }
                        }

                        if isUITestMode {
                            TextField("Goal value", text: goalInputTextBinding)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(AppLocalization.string("Goal value"))
                                .accessibilityIdentifier("goal.input.value")
                        }

                        // Walidacja pod kartą
                        if !valueValidation.isValid, let message = valueValidation.message {
                            Text(message)
                                .font(AppTypography.micro)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // MARK: - Start point card
                        AppGlassCard(
                            depth: .floating,
                            tint: Color.cyan.opacity(0.12),
                            contentPadding: 20
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(AppLocalization.string("goal.start.section.title"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    // Toggle widoczny tylko gdy jest historia (gdy brak historii — sekcja jest wymuszona)
                                    if !hasNoHistory {
                                        Toggle("", isOn: $useCustomStart)
                                            .labelsHidden()
                                            .tint(Color.appAccent)
                                    }
                                }

                                if useCustomStart {
                                    // Wartość startowa (pełna szerokość)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(AppLocalization.string("goal.start.value.label"))
                                            .font(AppTypography.micro)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 4) {
                                            TextField("0", value: $startDisplayValue, format: .number)
                                                .keyboardType(.decimalPad)
                                                .multilineTextAlignment(.trailing)
                                                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                                                .focused($isStartValueFocused)
                                            Text(kind.unitSymbol(unitsSystem: unitsSystem))
                                                .font(.system(.body, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        .appInputContainer(focused: isStartValueFocused)
                                    }

                                    // Data startowa (pełna szerokość)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(AppLocalization.string("goal.start.date.label"))
                                            .font(AppTypography.micro)
                                            .foregroundStyle(.secondary)
                                        DatePicker(
                                            "",
                                            selection: $startDate,
                                            in: ...Date.now,
                                            displayedComponents: .date
                                        )
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    // Komunikat walidacji wartości startowej
                                    if !startValueValidation.isValid, let msg = startValueValidation.message {
                                        Text(msg)
                                            .font(AppTypography.micro)
                                            .foregroundStyle(Color.red.opacity(0.9))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }

                        // MARK: - Help text card
                        AppGlassCard(depth: .base) {
                            Text(AppLocalization.string("metric.goal.set.help", kind.title.lowercased()))
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        // MARK: - Usun cel
                        if currentGoal != nil {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                    Text(AppLocalization.string("Delete Goal"))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AppDestructiveButtonStyle())
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(currentGoal == nil ? AppLocalization.string("Set Goal") : AppLocalization.string("Update Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .accessibilityIdentifier("goal.sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(currentGoal == nil ? AppLocalization.string("Set") : AppLocalization.string("Update")) {
                        Haptics.light()
                        let metricTarget = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
                        let metricStart: Double? = useCustomStart
                            ? kind.valueToMetric(fromDisplay: startDisplayValue, unitsSystem: unitsSystem)
                            : nil
                        let startDateValue: Date? = useCustomStart ? startDate : nil
                        onSet(metricTarget, direction, metricStart, startDateValue)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .accessibilityIdentifier("goal.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppLocalization.string("Done")) {
                        dismissKeyboard()
                    }
                }
            }
            .alert(AppLocalization.string("Delete Goal"), isPresented: $showDeleteConfirmation) {
                Button(AppLocalization.string("Delete"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
            } message: {
                Text(AppLocalization.string("goal.delete.confirmation"))
            }
        }
    }
}
