import SwiftUI
import Charts
import SwiftData

struct CustomMetricDetailView: View {
    private let measurementsTheme = FeatureTheme.measurements
    let definition: CustomMetricDefinition

    @Environment(\.modelContext) private var context
    @Query private var samples: [MetricSample]
    @Query private var goals: [MetricGoal]

    @State private var timeframe: Timeframe = .month
    @State private var showGoalSheet = false
    @State private var showAllHistory = false
    @State private var editingSample: MetricSample?

    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    enum Timeframe: String, CaseIterable, Identifiable {
        case week = "7D"
        case month = "30D"
        case threeMonths = "90D"
        case year = "1Y"
        case all = "All"
        var id: String { rawValue }

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

    init(definition: CustomMetricDefinition) {
        self.definition = definition
        let identifier = definition.identifier
        _samples = Query(
            filter: #Predicate<MetricSample> { $0.kindRaw == identifier },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
        _goals = Query(
            filter: #Predicate<MetricGoal> { $0.kindRaw == identifier }
        )
    }

    private var currentGoal: MetricGoal? { goals.first }

    private var chartSamples: [MetricSample] {
        if let start = timeframe.startDate() {
            return samples.filter { $0.date >= start }
        }
        return samples
    }

    private var latest: MetricSample? { samples.last }

    private var trendDelta: Double? {
        guard chartSamples.count >= 2,
              let first = chartSamples.first,
              let last = chartSamples.last,
              first.persistentModelID != last.persistentModelID else { return nil }
        return last.value - first.value
    }

    private var trendOutcome: MetricKind.TrendOutcome {
        guard let delta = trendDelta else { return .neutral }
        if delta == 0 { return .neutral }
        if let goal = currentGoal {
            guard let first = chartSamples.first, let last = chartSamples.last else { return .neutral }
            let startDist = abs(goal.targetValue - first.value)
            let endDist = abs(goal.targetValue - last.value)
            if endDist < startDist { return .positive }
            if endDist > startDist { return .negative }
            return .neutral
        }
        if definition.favorsDecrease {
            return delta < 0 ? .positive : .negative
        }
        return delta > 0 ? .positive : .negative
    }

    private var yDomain: ClosedRange<Double> {
        var values = chartSamples.map(\.value)
        if let goal = currentGoal { values.append(goal.targetValue) }
        guard let minVal = values.min(), let maxVal = values.max() else { return 0...1 }
        let padding = max((maxVal - minVal) * 0.15, 0.5)
        return (minVal - padding)...(maxVal + padding)
    }

    private var historyItems: [MetricSample] {
        let reversed = Array(samples.reversed())
        return showAllHistory ? reversed : Array(reversed.prefix(20))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: measurementsTheme.strongTint)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    headerSection
                    timeframeSelector
                    chartSection
                    goalSection
                    historySection
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(definition.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showGoalSheet) {
            CustomGoalSheet(
                definition: definition,
                existingGoal: currentGoal,
                samples: samples
            )
        }
        .sheet(item: $editingSample) { sample in
            CustomSampleEditSheet(
                sample: sample,
                definition: definition
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.md, tint: measurementsTheme.softTint, contentPadding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: definition.sfSymbolName)
                        .font(.title2)
                        .foregroundStyle(measurementsTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.name)
                            .font(AppTypography.bodyEmphasis)

                        if let latest {
                            Text(String(format: "%.1f %@", latest.value, definition.unitLabel))
                                .font(AppTypography.dataHero)
                                .monospacedDigit()
                        } else {
                            Text(AppLocalization.string("measurements.metric.nodata"))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let delta = trendDelta {
                    HStack(spacing: 6) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%.1f %@", abs(delta), definition.unitLabel))
                            .monospacedDigit()
                        Text(timeframe.rawValue)
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        trendOutcome == .positive ? AppColorRoles.chartPositive
                        : (trendOutcome == .negative ? AppColorRoles.chartNegative : AppColorRoles.textTertiary)
                    )
                }

                if let goal = currentGoal {
                    let isAchieved = latest.map { goal.isAchieved(currentValue: $0.value) } ?? false
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                        Text(isAchieved
                             ? AppLocalization.string("Goal reached")
                             : String(format: "%@ %.1f %@", AppLocalization.string("Goal:"), goal.targetValue, definition.unitLabel))
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(isAchieved ? AppColorRoles.stateSuccess : measurementsTheme.accent)
                }
            }
        }
    }

    // MARK: - Timeframe Selector

    private var timeframeSelector: some View {
        HStack(spacing: 4) {
            ForEach(Timeframe.allCases) { tf in
                Button {
                    withAnimation(AppMotion.standard) {
                        timeframe = tf
                    }
                } label: {
                    Text(tf.rawValue)
                        .font(AppTypography.captionEmphasis)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(timeframe == tf ? measurementsTheme.accent : Color.white.opacity(0.08))
                        )
                        .foregroundStyle(timeframe == tf ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.md, tint: measurementsTheme.softTint, contentPadding: 14) {
            if chartSamples.isEmpty {
                Text(AppLocalization.string("measurements.metric.nodata"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(chartSamples) { s in
                        AreaMark(
                            x: .value("Date", s.date),
                            yStart: .value("Baseline", yDomain.lowerBound),
                            yEnd: .value("Value", s.value)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [measurementsTheme.accent.opacity(0.3), measurementsTheme.accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }

                    ForEach(chartSamples) { s in
                        LineMark(x: .value("Date", s.date), y: .value("Value", s.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(measurementsTheme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    ForEach(chartSamples) { s in
                        PointMark(x: .value("Date", s.date), y: .value("Value", s.value))
                            .foregroundStyle(measurementsTheme.accent)
                            .symbolSize(chartSamples.count <= 30 ? 20 : 0)
                    }

                    if let goal = currentGoal {
                        RuleMark(y: .value("Goal", goal.targetValue))
                            .foregroundStyle(measurementsTheme.accent.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.white.opacity(0.5))
                            .font(AppTypography.micro)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.0f", v))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                    .font(AppTypography.micro)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
    }

    // MARK: - Goal Section

    private var goalSection: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.md, tint: measurementsTheme.softTint, contentPadding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("Goal"))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.secondary)

                    if let goal = currentGoal {
                        Text(String(format: "%.1f %@", goal.targetValue, definition.unitLabel))
                            .font(AppTypography.bodyEmphasis)
                        Text(goal.direction == .increase
                             ? AppLocalization.string("custom.metric.trend.increase")
                             : AppLocalization.string("custom.metric.trend.decrease"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(AppLocalization.string("No goal set"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    showGoalSheet = true
                } label: {
                    Text(currentGoal != nil ? AppLocalization.string("Edit") : AppLocalization.string("Set"))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(measurementsTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.md, tint: measurementsTheme.softTint, contentPadding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("History"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.secondary)

                if historyItems.isEmpty {
                    Text(AppLocalization.string("measurements.metric.nodata"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(historyItems) { sample in
                        Button {
                            editingSample = sample
                        } label: {
                            HStack {
                                Text(sample.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f %@", sample.value, definition.unitLabel))
                                    .font(AppTypography.bodyEmphasis)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)

                        if sample.persistentModelID != historyItems.last?.persistentModelID {
                            Divider().opacity(0.3)
                        }
                    }

                    if samples.count > 20 && !showAllHistory {
                        Button {
                            withAnimation { showAllHistory = true }
                        } label: {
                            Text(AppLocalization.string("Show all"))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(measurementsTheme.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Custom Goal Sheet

private struct CustomGoalSheet: View {
    let definition: CustomMetricDefinition
    let existingGoal: MetricGoal?
    let samples: [MetricSample]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var targetText: String = ""
    @State private var direction: MetricGoal.Direction = .decrease

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.string("custom.metric.goal.target"), text: $targetText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text(String(format: "%@ (%@)", AppLocalization.string("Target value"), definition.unitLabel))
                }

                Section {
                    Picker(AppLocalization.string("Direction"), selection: $direction) {
                        Text(AppLocalization.string("custom.metric.trend.increase")).tag(MetricGoal.Direction.increase)
                        Text(AppLocalization.string("custom.metric.trend.decrease")).tag(MetricGoal.Direction.decrease)
                    }
                    .pickerStyle(.segmented)
                }

                if existingGoal != nil {
                    Section {
                        Button(role: .destructive) {
                            if let goal = existingGoal {
                                context.delete(goal)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text(AppLocalization.string("Remove goal"))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) { save() }
                        .disabled(Double(targetText) == nil)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let goal = existingGoal {
                    targetText = String(format: "%.1f", goal.targetValue)
                    direction = goal.direction
                }
            }
        }
    }

    private func save() {
        guard let target = Double(targetText) else { return }
        MetricGoalStore.upsertCustomGoal(
            kindRaw: definition.identifier,
            targetValue: target,
            direction: direction,
            in: context,
            existingGoal: existingGoal,
            existingSamples: samples
        )
        Haptics.light()
        dismiss()
    }
}

// MARK: - Custom Sample Edit Sheet

private struct CustomSampleEditSheet: View {
    let sample: MetricSample
    let definition: CustomMetricDefinition

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var valueText: String = ""
    @State private var date: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(definition.unitLabel, text: $valueText)
                            .keyboardType(.decimalPad)
                        Text(definition.unitLabel)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(AppLocalization.string("Value"))
                }

                Section {
                    DatePicker(
                        AppLocalization.string("Date"),
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    Button(role: .destructive) {
                        context.delete(sample)
                        Haptics.medium()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(AppLocalization.string("Delete measurement"))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Edit measurement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
                        if let value = Double(valueText) {
                            sample.value = value
                            sample.date = date
                            Haptics.light()
                        }
                        dismiss()
                    }
                    .disabled(Double(valueText) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                valueText = String(format: "%.1f", sample.value)
                date = sample.date
            }
        }
    }
}

