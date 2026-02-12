import SwiftUI
import Charts
import SwiftData
import Foundation

struct MeasurementsTabView: View {
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(AppRouter.self) private var router
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @State private var scrollOffset: CGFloat = 0
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]

    @State private var selectedTab: MeasurementsTab = .metrics

    enum MeasurementsTab: String, CaseIterable, Identifiable {
        case metrics = "Metrics"
        case health = "Health indicators"
        var id: String { rawValue }

        var title: String {
            AppLocalization.string(rawValue)
        }
    }

    private var samplesByKind: [MetricKind: [MetricSample]] {
        var grouped: [MetricKind: [MetricSample]] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            grouped[kind, default: []].append(sample)
        }
        return grouped
    }

    private var latestByKind: [MetricKind: MetricSample] {
        var latest: [MetricKind: MetricSample] = [:]
        for (kind, list) in samplesByKind {
            if let first = list.first {
                latest[kind] = first
            }
        }
        return latest
    }

    private var latestWaist: Double? {
        latestByKind[.waist]?.value
    }

    private var latestHeight: Double? {
        latestByKind[.height]?.value
    }

    private var latestWeight: Double? {
        latestByKind[.weight]?.value
    }

    private var latestBodyFat: Double? {
        latestByKind[.bodyFat]?.value
    }

    private var latestLeanMass: Double? {
        latestByKind[.leanBodyMass]?.value
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(
                    topHeight: 380,
                    scrollOffset: scrollOffset,
                    tint: Color.cyan.opacity(0.22)
                )

                ScrollView {
                    LazyVStack(spacing: 16) {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: MeasurementsScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("measurementsScroll")).minY
                                )
                        }
                        .frame(height: 0)

                        ScreenTitleHeader(title: AppLocalization.string("Measurements"), topPadding: 6, bottomPadding: 4)

                        HStack {
                            Spacer()
                            Picker(AppLocalization.string("Section"), selection: $selectedTab) {
                                ForEach(MeasurementsTab.allCases) { tab in
                                    Text(tab.title).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .glassSegmentedControl(tint: Color(hex: "#FCA311"))
                            .tint(Color(hex: "#FCA311"))
                            .frame(maxWidth: 320)
                            .accessibilityLabel(AppLocalization.string("accessibility.measurements.section"))
                            .accessibilityHint(AppLocalization.string("accessibility.measurements.switch"))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .onChange(of: selectedTab) { _, newValue in
                            guard newValue == .health else { return }
                            if !premiumStore.isPremium {
                                premiumStore.presentPaywall(reason: .feature("Health indicators"))
                                DispatchQueue.main.async {
                                    selectedTab = .metrics
                                }
                            }
                        }

                        if selectedTab == .metrics {
                            if samples.isEmpty {
                                AppGlassCard(
                                    depth: .elevated,
                                    cornerRadius: 24,
                                    tint: Color.appAccent.opacity(0.18),
                                    contentPadding: 16
                                ) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(AppLocalization.string("No measurements yet"))
                                            .font(AppTypography.bodyEmphasis)
                                            .foregroundStyle(.white)

                                        Text(AppLocalization.string("Add your first measurement to unlock charts and progress."))
                                            .font(AppTypography.body)
                                            .foregroundStyle(.white.opacity(0.7))

                                        Button {
                                            router.presentedSheet = .composer(mode: .newPost)
                                        } label: {
                                            Text(AppLocalization.string("Add measurement"))
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color.appAccent)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            ForEach(metricsStore.activeKinds, id: \.self) { kind in
                                MetricChartTile(
                                    kind: kind,
                                    unitsSystem: unitsSystem
                                )
                                .padding(.horizontal, 16)
                            }
                        } else {
                            if premiumStore.isPremium {
                                HealthMetricsSection(
                                    latestWaist: latestWaist,
                                    latestHeight: latestHeight,
                                    latestWeight: latestWeight,
                                    latestBodyFat: latestBodyFat,
                                    latestLeanMass: latestLeanMass,
                                    displayMode: .indicatorsOnly,
                                    title: ""
                                )
                                .padding(.horizontal, 16)
                            } else {
                                PremiumLockedCard(
                                    title: AppLocalization.string("Health indicators"),
                                    message: AppLocalization.string("Upgrade to Premium Edition to unlock Health Indicators.")
                                ) {
                                    premiumStore.presentPaywall(reason: .feature("Health indicators"))
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .coordinateSpace(name: "measurementsScroll")
                .onPreferenceChange(MeasurementsScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(scrollOffset < -16 ? .visible : .hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}


struct MetricChartTile: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    let kind: MetricKind
    let unitsSystem: String
    @AppStorage("userName") private var userName: String = ""

    @Query private var samples: [MetricSample]
    @Query private var goals: [MetricGoal]

    @State private var shortInsight: String?
    @State private var isLoadingInsight = false

    init(kind: MetricKind, unitsSystem: String) {
        self.kind = kind
        self.unitsSystem = unitsSystem

        let kindValue = kind.rawValue
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        _samples = Query(
            filter: #Predicate<MetricSample> {
                $0.kindRaw == kindValue && $0.date >= startDate
            },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
        _goals = Query(
            filter: #Predicate<MetricGoal> {
                $0.kindRaw == kindValue
            }
        )
    }
    
    // Aktualny cel dla tej metryki
    private var currentGoal: MetricGoal? {
        goals.first
    }

    // MARK: - Data

    private var startDate30: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
    }

    private var recentSamples: [MetricSample] {
        samples.filter { $0.date >= startDate30 }
    }

    private var latest: MetricSample? {
        recentSamples.last
    }

    private var trendInfo: (delta: Double, relativeText: String, outcome: MetricKind.TrendOutcome)? {
        guard recentSamples.count >= 2,
              let lastSample = recentSamples.last else { return nil }

        let targetDate = Calendar.current.date(byAdding: .day, value: -30, to: lastSample.date) ?? startDate30
        let baselineSample = recentSamples.min {
            abs($0.date.timeIntervalSince(targetDate)) < abs($1.date.timeIntervalSince(targetDate))
        }

        guard let baselineSample,
              baselineSample.persistentModelID != lastSample.persistentModelID else { return nil }

        let last = displayValue(lastSample.value)
        let baseline = displayValue(baselineSample.value)
        let delta = last - baseline
        let outcome = kind.trendOutcome(from: baselineSample.value, to: lastSample.value, goal: currentGoal)
        return (delta, AppLocalization.string("trend.relative.30d"), outcome)
    }

    // MARK: - UI

    private var appleIntelligenceAvailable: Bool {
        AppleIntelligenceSupport.isAvailable()
    }

    private var canUseAppleIntelligence: Bool {
        premiumStore.isPremium && appleIntelligenceAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: kind.systemImage)
                        .foregroundStyle(.secondary)
                        .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)

                    Text(kind.title)
                        .font(AppTypography.bodyEmphasis)
                }

                Spacer()

                NavigationLink {
                    MetricDetailView(kind: kind)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Value + trend + goal info
            if let latest {
                Text(valueString(metricValue: latest.value))
                    .font(AppTypography.metricValue)
                    .monospacedDigit()

                if let trendInfo {
                    HStack(spacing: 6) {
                        Image(systemName: trendInfo.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(
                            String(
                                format: "%.1f %@",
                                abs(trendInfo.delta),
                                kind.unitSymbol(unitsSystem: unitsSystem)
                            )
                        )
                        .monospacedDigit()
                        Text(AppLocalization.string("trend.vs.relative", trendInfo.relativeText))
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        trendInfo.outcome == .positive
                        ? Color(hex: "#22C55E")
                        : (trendInfo.outcome == .negative ? Color(hex: "#EF4444") : Color.white.opacity(0.6))
                    )
                }
                
                // Goal info (ile zostało do celu)
                if let goal = currentGoal {
                    let isAchieved = goal.isAchieved(currentValue: latest.value)
                    let remaining = goal.remainingToGoal(currentValue: latest.value)
                    let remainingDisplay = displayValue(abs(remaining))
                    let unit = kind.unitSymbol(unitsSystem: unitsSystem)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(AppTypography.micro)
                        Text(isAchieved
                             ? AppLocalization.string("Goal reached")
                             : AppLocalization.string("goal.remaining", remainingDisplay, unit))
                        .monospacedDigit()
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(isAchieved ? Color(hex: "#22C55E") : Color(hex: "#FCA311"))
                }

                if canUseAppleIntelligence, let shortInsight {
                    let compactInsight = shortInsight.count > 140
                        ? String(shortInsight.prefix(140))
                        : shortInsight
                    MetricInsightCard(
                        text: compactInsight,
                        compact: true,
                        isLoading: isLoadingInsight
                    )
                } else if canUseAppleIntelligence, isLoadingInsight {
                    MetricInsightCard(
                        text: AppLocalization.string("Generating insight..."),
                        compact: true,
                        isLoading: true
                    )
                } else if premiumStore.isPremium && !appleIntelligenceAvailable {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("Apple Intelligence isn’t available right now."))
                            .font(AppTypography.micro)
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            FAQView()
                        } label: {
                            Text(AppLocalization.string("Learn more in FAQ"))
                                .font(AppTypography.microEmphasis)
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                }
            } else {
                Text(AppLocalization.string("—"))
                    .font(AppTypography.metricValue)
                    .foregroundStyle(.secondary)
            }

            // Chart - z podwójnym maskowaniem
            ZStack {
                // Tło wykresu
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0))
                
                Chart {

                    // 🔹 AREA – JEDEN mark, jeden gradient
                    ForEach(recentSamples) { s in
                        AreaMark(
                            x: .value("Date", s.date),
                            y: .value("Value", displayValue(s.value))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("Area", "fill"))

                    }

                    // 🔸 LINIA
                    ForEach(recentSamples) { s in
                        LineMark(
                            x: .value("Date", s.date),
                            y: .value("Value", displayValue(s.value))
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(.init(lineWidth: 2.5))
                        .foregroundStyle(Color(hex: "#FCA311"))
                    }

                    // 🔸 PUNKTY
                    ForEach(recentSamples) { s in
                        PointMark(
                            x: .value("Date", s.date),
                            y: .value("Value", displayValue(s.value))
                        )
                        .symbolSize(24)
                        .foregroundStyle(Color(hex: "#FCA311").opacity(0.6))
                    }
                    
                    // Linia celu (z annotation)
                    if let goal = currentGoal {
                        let goalValue = displayValue(goal.targetValue)
                        RuleMark(y: .value("Goal", goalValue))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                            .foregroundStyle(Color(hex: "#E5E5E5").opacity(0.7))
                            .annotation(position: goalLabelPosition(for: goalValue), alignment: .leading) {
                                Text(AppLocalization.string("Goal"))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color(hex: "#E5E5E5"))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.black.opacity(0.75))
                                    )
                                    .offset(x: 6)
                            }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .chartForegroundStyleScale([
                    "fill": LinearGradient(
                        colors: [
                            Color(hex: "#FCA311").opacity(0.1),
                            Color(hex: "#FCA311").opacity(0.1),
                            Color(hex: "#FCA311").opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                ])
                .chartLegend(.hidden)
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.12))
                        AxisTick().foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel()
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

            }
            .frame(height: 120)
            .mask(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
        }
        .padding(14)
        .background(
            AppGlassBackground(
                depth: .elevated,
                cornerRadius: 16,
                tint: Color.appAccent.opacity(0.14)
            )
        )
        .task(id: insightInput) {
            await loadInsightIfNeeded()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
    }

    // MARK: - Helpers

    private func displayValue(_ metricValue: Double) -> Double {
        kind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    private func valueString(metricValue: Double) -> String {
        let shown = displayValue(metricValue)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%.1f %@", shown, unit)
    }

    private var yDomain: ClosedRange<Double> {
        var values = recentSamples.map { displayValue($0.value) }
        
        // Dodaj wartość celu do zakresu, jeśli cel istnieje
        if let goal = currentGoal {
            values.append(displayValue(goal.targetValue))
        }
        
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 1)
        let padding = span * 0.15
        return (minV - padding)...(maxV + padding)
    }
    
    private func goalLabelPosition(for goalValue: Double) -> AnnotationPosition {
        let minV = yDomain.lowerBound
        let maxV = yDomain.upperBound
        let span = max(maxV - minV, 0.0001)
        let rel = (goalValue - minV) / span
        if rel > 0.85 { return .bottom }
        if rel < 0.15 { return .top }
        return .top
    }

    private var insightInput: MetricInsightInput? {
        guard canUseAppleIntelligence, let latest else { return nil }
        return MetricInsightInput(
            userName: userName.isEmpty ? nil : userName,
            metricTitle: kind.englishTitle,
            latestValueText: valueString(metricValue: latest.value),
            timeframeLabel: AppLocalization.string("Last 30 days"),
            sampleCount: recentSamples.count,
            delta7DaysText: deltaText(days: 7, in: recentSamples),
            delta30DaysText: deltaText(days: 30, in: recentSamples),
            goalStatusText: goalStatusText
        )
    }

    private var goalStatusText: String? {
        guard let goal = currentGoal, let latest else { return nil }
        if goal.isAchieved(currentValue: latest.value) {
            return AppLocalization.string("Goal reached")
        }
        let remaining = displayValue(abs(goal.remainingToGoal(currentValue: latest.value)))
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return AppLocalization.string("goal.away", remaining, unit)
    }

    private var accessibilitySummary: String {
        if let latest {
            let value = valueString(metricValue: latest.value)
            if let trendInfo {
                let deltaText = String(format: "%.1f %@", abs(trendInfo.delta), kind.unitSymbol(unitsSystem: unitsSystem))
                return AppLocalization.string("accessibility.metric.summary.trend", kind.title, value, deltaText, trendInfo.relativeText)
            }
            return AppLocalization.string("accessibility.metric.summary.value", kind.title, value)
        }
        return AppLocalization.string("accessibility.metric.summary.nodata", kind.title)
    }

    private func deltaText(days: Int, in source: [MetricSample]) -> String? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return nil }
        let window = source.filter { $0.date >= start }
        guard let first = window.first, let last = window.last, first.persistentModelID != last.persistentModelID else {
            return nil
        }
        let delta = displayValue(last.value) - displayValue(first.value)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%+.1f %@", delta, unit)
    }

    @MainActor
    private func loadInsightIfNeeded() async {
        guard let input = insightInput else {
            shortInsight = nil
            isLoadingInsight = false
            return
        }

        isLoadingInsight = true
        let generated = await MetricInsightService.shared.generateInsight(for: input)
        shortInsight = generated?.shortText
        isLoadingInsight = false
    }
}

private struct MeasurementsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
