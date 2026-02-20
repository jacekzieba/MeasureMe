import SwiftUI
import Charts
import SwiftData
import Foundation
import Accessibility

struct MeasurementsTabView: View {
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("settings_open_tracked_measurements") private var settingsOpenTrackedMeasurements: Bool = false
    @AppStorage("quickAddHintDismissed") private var quickAddHintDismissed: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var refreshToken = UUID()
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]
    @State private var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @State private var cachedLatestByKind: [MetricKind: MetricSample] = [:]

    @State private var selectedTab: MeasurementsTab = .metrics

    enum MeasurementsTab: String, CaseIterable, Identifiable {
        case metrics = "Metrics"
        case health = "Health indicators"
        var id: String { rawValue }

        var title: String {
            AppLocalization.string(rawValue)
        }
    }

    private var samplesByKind: [MetricKind: [MetricSample]] { cachedSamplesByKind }

    private var latestByKind: [MetricKind: MetricSample] { cachedLatestByKind }

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
                            .accessibilityIdentifier("measurements.tab.segmented")
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.md)
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
                                // MARK: - Hero empty state
                                EmptyStateCard(
                                    title: AppLocalization.string("measurements.empty.title"),
                                    message: AppLocalization.string("measurements.empty.body"),
                                    systemImage: "chart.line.uptrend.xyaxis",
                                    actionTitle: AppLocalization.string("Add measurement"),
                                    action: {
                                        Haptics.light()
                                        router.presentedSheet = .composer(mode: .newPost)
                                    },
                                    accessibilityIdentifier: "measurements.empty.state"
                                )
                                .padding(.horizontal, AppSpacing.md)
                            }

                            // MARK: - Quick Add hint strip
                            if !quickAddHintDismissed {
                                AppGlassCard(
                                    depth: .base,
                                    cornerRadius: AppRadius.md,
                                    tint: Color.cyan.opacity(0.12),
                                    contentPadding: AppSpacing.sm
                                ) {
                                    HStack(spacing: AppSpacing.xs) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(Color.appAccent)

                                        Text(AppLocalization.string("measurements.quickadd.hint"))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(.white.opacity(0.72))

                                        Spacer(minLength: 4)

                                        Button {
                                            withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                                                quickAddHintDismissed = true
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 28, height: 28)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            ForEach(metricsStore.activeKinds, id: \.self) { kind in
                                MetricChartTile(
                                    kind: kind,
                                    unitsSystem: unitsSystem
                                )
                                .padding(.horizontal, AppSpacing.md)
                            }

                            trackedMetricsFooter
                                .padding(.horizontal, AppSpacing.md)
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
                                .padding(.horizontal, AppSpacing.md)
                                .accessibilityIdentifier("measurements.ai.container")
                            } else {
                                PremiumLockedCard(
                                    title: AppLocalization.string("Health indicators"),
                                    message: AppLocalization.string("Upgrade to Premium Edition to unlock Health Indicators.")
                                ) {
                                    premiumStore.presentPaywall(reason: .feature("Health indicators"))
                                }
                                .padding(.horizontal, AppSpacing.md)
                            }
                        }
                    }
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                }
                .id(refreshToken)
                .coordinateSpace(name: "measurementsScroll")
                .onPreferenceChange(MeasurementsScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
                .accessibilityIdentifier("measurements.scroll")
                .refreshable {
                    rebuildSamplesCache()
                    refreshToken = UUID()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(scrollOffset < -16 ? .visible : .hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuildSamplesCache()
        }
        .onChange(of: samplesSignature) { _, _ in
            rebuildSamplesCache()
        }
    }

    private var trackedMetricsFooter: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: AppRadius.lg,
            tint: Color.appAccent.opacity(0.10),
            contentPadding: AppSpacing.sm
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("Tracked metric visibility can be changed in Settings."))
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    settingsOpenTrackedMeasurements = true
                    router.selectedTab = .settings
                } label: {
                    HStack(spacing: 6) {
                        Text(AppLocalization.string("Open tracked metrics settings"))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var samplesSignature: Int {
        var hasher = Hasher()
        for sample in samples {
            hasher.combine(sample.persistentModelID)
            hasher.combine(sample.value.bitPattern)
            hasher.combine(sample.date.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private func rebuildSamplesCache() {
        var grouped: [MetricKind: [MetricSample]] = [:]
        var latest: [MetricKind: MetricSample] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else {
                AppLog.debug("⚠️ Ignoring MetricSample with invalid kindRaw: \(sample.kindRaw)")
                continue
            }
            grouped[kind, default: []].append(sample)
            if latest[kind] == nil {
                latest[kind] = sample
            }
        }
        cachedSamplesByKind = grouped
        cachedLatestByKind = latest
    }
}


struct MetricChartTile: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: MetricKind
    let unitsSystem: String
    @AppStorage("userName") private var userName: String = ""

    @Query private var samples: [MetricSample]
    @Query private var goals: [MetricGoal]

    @State private var shortInsight: String?
    @State private var isLoadingInsight = false
    // Scrubbing wykresu usuniety z kafelka - dostepny tylko w MetricDetailView

    init(kind: MetricKind, unitsSystem: String) {
        self.kind = kind
        self.unitsSystem = unitsSystem

        let kindValue = kind.rawValue
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? .distantPast
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
        Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? .distantPast
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
        if recentSamples.isEmpty {
            // MARK: - Kompaktowy pusty kafelek (brak danych)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(.secondary)
                                .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .layoutPriority(1)

                                Text(AppLocalization.string("measurements.metric.nodata"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                Haptics.light()
                                router.presentedSheet = .addSample(kind: kind)
                            } label: {
                                Text(AppLocalization.string("Add"))
                            }
                            .buttonStyle(LiquidCapsuleButtonStyle())
                            .frame(minHeight: 44)

                            Spacer(minLength: 0)

                            NavigationLink {
                                MetricDetailView(kind: kind)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: kind.systemImage)
                                    .foregroundStyle(.secondary)
                                    .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)

                                Text(kind.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .layoutPriority(1)
                            }

                            Text(AppLocalization.string("measurements.metric.nodata"))
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer(minLength: 8)

                        Button {
                            Haptics.light()
                            router.presentedSheet = .addSample(kind: kind)
                        } label: {
                            Text(AppLocalization.string("Add"))
                        }
                        .buttonStyle(LiquidCapsuleButtonStyle())

                        NavigationLink {
                            MetricDetailView(kind: kind)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                    }
                }
            }
            .padding(14)
            .background(
                AppGlassBackground(
                    depth: .elevated,
                    cornerRadius: 16,
                    tint: Color.appAccent.opacity(0.14)
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.string("accessibility.metric.summary.nodata", kind.title))
            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
        } else {
            // MARK: - Pelny kafelek z wykresem
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
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                }

                // Wartosc + trend + informacje o celu
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
                        MetricInsightCard(
                            text: shortInsight,
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
                            Text(AppLocalization.string("AI Insights aren't available right now."))
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
                VStack(alignment: .leading, spacing: 8) {
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
                                        .font(AppTypography.micro)
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
                        .accessibilityChartDescriptor(MetricChartAXDescriptor(descriptor: chartDescriptor))

                    }
                    .frame(height: 120)
                    .mask(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )

                }
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
            goalStatusText: goalStatusText,
            goalDirectionText: currentGoal?.direction.rawValue,
            defaultFavorableDirectionText: kind.defaultFavorableDirectionWhenNoGoal.rawValue
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
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: AppClock.now) else { return nil }
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

    private var chartDescriptor: AXChartDescriptor {
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let points: [(String, Double)] = recentSamples.map { sample in
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
                String(format: "%.1f %@", value, unit)
            }
        )

        let series = AXDataSeriesDescriptor(
            name: kind.title,
            isContinuous: true,
            dataPoints: points.map { AXDataPoint(x: $0.0, y: $0.1) }
        )

        let summary: String
        if let first = values.first, let last = values.last {
            let trend = last == first
                ? AppLocalization.string("trend.steady")
                : (last > first ? AppLocalization.string("trend.up") : AppLocalization.string("trend.down"))
            summary = AppLocalization.string(
                "chart.summary.metric",
                kind.title,
                AppLocalization.string("Last 30 days").lowercased(),
                String(format: "%.1f", first),
                String(format: "%.1f", last),
                trend
            )
        } else {
            summary = AppLocalization.string("chart.summary.empty", kind.title)
        }

        return AXChartDescriptor(
            title: AppLocalization.string("chart.title.metric", kind.title),
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

private struct MeasurementsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
