import SwiftUI
import Charts
import SwiftData
import Foundation
import Accessibility

struct MeasurementsTabView: View {
    private static let queryWindowDays = 1825
    private static let bottomTabBarClearance: CGFloat = 96
    private let measurementsTheme = FeatureTheme.measurements
    private let healthTheme = FeatureTheme.health
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.profile.userGender) private var userGenderRaw: String = "notSpecified"
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    @AppSetting(\.home.settingsOpenTrackedMeasurements) private var settingsOpenTrackedMeasurements: Bool = false
    @AppSetting(\.experience.quickAddHintDismissed) private var quickAddHintDismissed: Bool = false
    @AppSetting(\.experience.hasCustomizedMetrics) private var hasCustomizedMetrics: Bool = false
    @State private var refreshToken = UUID()
    @Query private var samples: [MetricSample]
    @State private var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @State private var cachedLatestByKind: [MetricKind: MetricSample] = [:]

    @Query(sort: \CustomMetricDefinition.sortOrder) private var customDefinitions: [CustomMetricDefinition]
    @State private var cachedCustomSamples: [String: [MetricSample]] = [:]
    @State private var cachedCustomLatest: [String: MetricSample] = [:]

    @State private var selectedTab: MeasurementsTab = .metrics
    @State private var requestedMetricDetailKind: MetricKind?

    private let healthAccent = HealthIndicatorPalette.accent

    init() {
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.queryWindowDays,
            to: AppClock.now
        ) ?? .distantPast
        _samples = Query(
            filter: #Predicate<MetricSample> { $0.date >= startDate },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    enum MeasurementsTab: String, CaseIterable, Identifiable {
        case metrics = "Metrics"
        case health = "Health indicators"
        case physique = "Physique indicators"
        var id: String { rawValue }

        var title: String {
            AppLocalization.string(rawValue)
        }

        var accessibilityID: String {
            switch self {
            case .metrics:
                return "measurements.tab.metrics"
            case .health:
                return "measurements.tab.health"
            case .physique:
                return "measurements.tab.physique"
            }
        }
    }

    private var activeCustomDefinitions: [CustomMetricDefinition] {
        let activeIds = metricsStore.activeCustomIdentifiers(from: customDefinitions)
        let lookup = Dictionary(uniqueKeysWithValues: customDefinitions.map { ($0.identifier, $0) })
        return activeIds.compactMap { lookup[$0] }
    }

    private var samplesByKind: [MetricKind: [MetricSample]] { cachedSamplesByKind }

    private var latestByKind: [MetricKind: MetricSample] { cachedLatestByKind }

    private var userGender: Gender {
        Gender(rawValue: userGenderRaw) ?? .notSpecified
    }

    private var latestWaist: Double? {
        latestByKind[.waist]?.value
    }

    private var latestHeight: Double? {
        if manualHeight > 0 {
            return manualHeight
        }
        return latestByKind[.height]?.value
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

    private var latestShoulders: Double? {
        latestByKind[.shoulders]?.value
    }

    private var latestChest: Double? {
        latestByKind[.chest]?.value
    }

    private var latestBust: Double? {
        latestByKind[.bust]?.value
    }

    private var latestHips: Double? {
        latestByKind[.hips]?.value
    }

    private var sectionTint: Color {
        switch selectedTab {
        case .metrics:
            return measurementsTheme.strongTint
        case .health:
            return healthTheme.strongTint
        case .physique:
            return AppColorRoles.accentPhysique.opacity(0.24)
        }
    }

    private var metricsSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.metricsInput(
            userName: userName,
            activeKinds: metricsStore.activeKinds,
            latestByKind: latestByKind,
            samplesByKind: samplesByKind,
            unitsSystem: unitsSystem
        )
    }

    private var healthSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.healthInput(
            userName: userName,
            userGender: userGender,
            latestWaist: latestWaist,
            latestHeight: latestHeight,
            latestWeight: latestWeight,
            latestHips: latestHips,
            latestBodyFat: latestBodyFat,
            latestLeanMass: latestLeanMass,
            samplesByKind: samplesByKind,
            unitsSystem: unitsSystem
        )
    }

    private var physiqueSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.physiqueInput(
            userName: userName,
            userGender: userGender,
            latestWaist: latestWaist,
            latestHeight: latestHeight,
            latestBodyFat: latestBodyFat,
            latestShoulders: latestShoulders,
            latestChest: latestChest,
            latestBust: latestBust,
            latestHips: latestHips,
            samplesByKind: samplesByKind,
            unitsSystem: unitsSystem
        )
    }

    private func tabAccent(for tab: MeasurementsTab) -> Color {
        switch tab {
        case .metrics:
            return measurementsTheme.accent
        case .health:
            return healthTheme.accent
        case .physique:
            return AppColorRoles.accentPhysique
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(
                    topHeight: 380,
                    tint: sectionTint
                )

                ScrollView {
                    LazyVStack(spacing: 16) {
                        headerSection

                        if selectedTab == .metrics {
                            AISectionSummaryCard(
                                input: metricsSummaryInput,
                                    missingDataMessage: AppLocalization.aiString("AI summary needs metric data. Add measurements to generate insights."),
                                tint: measurementsTheme.softTint,
                                accessibilityIdentifier: "measurements.metrics.ai.summary"
                            )
                            .padding(.horizontal, AppSpacing.md)

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
                                    tint: measurementsTheme.softTint,
                                    contentPadding: AppSpacing.sm
                                ) {
                                    HStack(spacing: AppSpacing.xs) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(measurementsTheme.accent)

                                        Text(AppLocalization.string("measurements.quickadd.hint"))
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColorRoles.textSecondary)

                                        Spacer(minLength: 4)

                                        Button {
                                            withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                                                quickAddHintDismissed = true
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppColorRoles.textTertiary)
                                                .frame(width: 28, height: 28)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            // MARK: - Metrics discovery banner
                            if !hasCustomizedMetrics {
                                AppGlassCard(
                                    depth: .base,
                                    cornerRadius: AppRadius.md,
                                    tint: measurementsTheme.softTint,
                                    contentPadding: AppSpacing.xs
                                ) {
                                    HStack(alignment: .center, spacing: AppSpacing.xs) {
                                        HStack(spacing: AppSpacing.xs) {
                                            Image(systemName: "sparkles")
                                                .font(.body)
                                                .foregroundStyle(measurementsTheme.accent)

                                            Text(AppLocalization.string("measurements.discovery.hint", metricsStore.activeKinds.count, metricsStore.allKindsInOrder.count))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColorRoles.textSecondary)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Spacer(minLength: AppSpacing.xxs)
                                        Button {
                                            Haptics.selection()
                                            settingsOpenTrackedMeasurements = true
                                            router.selectedTab = .settings
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(AppLocalization.string("measurements.discovery.cta"))
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.semibold))
                                            }
                                            .font(AppTypography.captionEmphasis)
                                            .foregroundStyle(measurementsTheme.accent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                .accessibilityIdentifier("measurements.discovery.banner")
                            }

                            ForEach(metricsStore.activeKinds, id: \.self) { kind in
                                MetricChartTile(
                                    kind: kind,
                                    unitsSystem: unitsSystem
                                )
                                .padding(.horizontal, AppSpacing.md)
                            }

                            ForEach(activeCustomDefinitions) { def in
                                CustomMetricChartTile(
                                    definition: def,
                                    theme: measurementsTheme
                                )
                                .padding(.horizontal, AppSpacing.md)
                            }

                            trackedMetricsFooter
                                .padding(.horizontal, AppSpacing.md)
                        } else if selectedTab == .health {
                            if premiumStore.isPremium {
                                AISectionSummaryCard(
                                    input: healthSummaryInput,
                                    missingDataMessage: AppLocalization.aiString("AI summary needs health indicator data. Add required measurements first."),
                                    tint: healthTheme.softTint,
                                    accessibilityIdentifier: "measurements.health.ai.summary"
                                )
                                .padding(.horizontal, AppSpacing.md)

                                HealthMetricsSection(
                                    latestWaist: latestWaist,
                                    latestHeight: latestHeight,
                                    latestWeight: latestWeight,
                                    latestHips: latestHips,
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
                        } else {
                            if premiumStore.isPremium {
                                AISectionSummaryCard(
                                    input: physiqueSummaryInput,
                                    missingDataMessage: AppLocalization.aiString("AI summary needs physique indicator data. Add required measurements first."),
                                    tint: AppColorRoles.accentPhysique.opacity(0.18),
                                    accessibilityIdentifier: "measurements.physique.ai.summary"
                                )
                                .padding(.horizontal, AppSpacing.md)

                                PhysiqueIndicatorsSection(
                                    latestWaist: latestWaist,
                                    latestHeight: latestHeight,
                                    latestWeight: latestWeight,
                                    latestBodyFat: latestBodyFat,
                                    latestShoulders: latestShoulders,
                                    latestChest: latestChest,
                                    latestBust: latestBust,
                                    latestHips: latestHips
                                )
                                .padding(.horizontal, AppSpacing.md)
                                .accessibilityIdentifier("measurements.physique.container")
                            } else {
                                PremiumLockedCard(
                                    title: AppLocalization.string("Physique indicators"),
                                    message: AppLocalization.string("Upgrade to Premium Edition to unlock Physique indicators.")
                                ) {
                                    premiumStore.presentPaywall(reason: .feature("Physique indicators"))
                                }
                                .padding(.horizontal, AppSpacing.md)
                            }
                        }
                    }
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.lg)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: Self.bottomTabBarClearance)
                        .accessibilityHidden(true)
                }
                .id(refreshToken)
                .accessibilityIdentifier("measurements.scroll")
                .refreshable {
                    rebuildSamplesCache()
                    refreshToken = UUID()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background {
                NavigationLink(
                    isActive: metricDetailPresentationBinding
                ) {
                    requestedMetricDetailDestination
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
        .onAppear {
            rebuildSamplesCache()
            if let requestID = router.metricDetailRequestID,
               let kind = router.requestedMetricDetailKind {
                presentMetricDetail(kind, requestID: requestID)
            }
            if let requestID = router.measurementsSectionRequestID,
               let section = router.requestedMeasurementsSection {
                switch section {
                case "health":
                    selectedTab = .health
                case "physique":
                    selectedTab = .physique
                default:
                    selectedTab = .metrics
                }
                router.consumeMeasurementsSectionRequest(requestID)
            }
        }
        .onChange(of: samplesSignature) { _, _ in
            rebuildSamplesCache()
        }
        .onChange(of: router.metricDetailRequestID) { _, requestID in
            guard let requestID, let kind = router.requestedMetricDetailKind else { return }
            presentMetricDetail(kind, requestID: requestID)
        }
        .onChange(of: router.measurementsSectionRequestID) { _, requestID in
            guard let requestID, let section = router.requestedMeasurementsSection else { return }
            switch section {
            case "health":
                selectedTab = .health
            case "physique":
                selectedTab = .physique
            default:
                selectedTab = .metrics
            }
            router.consumeMeasurementsSectionRequest(requestID)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 0) {
            ScreenTitleHeader(
                title: AppLocalization.string("Measurements"),
                topPadding: 6,
                bottomPadding: 0,
                horizontalPadding: 8
            )

            MeasurementsCategoryTabs(
                selectedTab: $selectedTab,
                tabs: MeasurementsTab.allCases,
                activeTint: tabAccent(for: selectedTab),
                animateSelection: shouldAnimate
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel(AppLocalization.string("accessibility.measurements.section"))
            .accessibilityHint(AppLocalization.string("accessibility.measurements.switch"))
            .padding(.horizontal, AppSpacing.md)
            .onChange(of: selectedTab) { _, newValue in
                guard newValue == .health || newValue == .physique else { return }
                if !premiumStore.isPremium {
                    let feature = newValue == .health ? "Health indicators" : "Physique indicators"
                    premiumStore.presentPaywall(reason: .feature(feature))
                    Task { @MainActor in
                        selectedTab = .metrics
                    }
                }
            }
            .animation(shouldAnimate ? .easeInOut(duration: 0.24) : nil, value: selectedTab)
            .padding(.bottom, AppSpacing.sm)
        }
    }

    private var trackedMetricsFooter: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: 16,
            tint: measurementsTheme.softTint,
            contentPadding: 14
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("measurements.footer.dynamic", metricsStore.activeKinds.count, metricsStore.allKindsInOrder.count))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
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
                .foregroundStyle(measurementsTheme.accent)
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
        var customGrouped: [String: [MetricSample]] = [:]
        var customLatest: [String: MetricSample] = [:]
        for sample in samples {
            if sample.isCustomMetric {
                customGrouped[sample.kindRaw, default: []].append(sample)
                if customLatest[sample.kindRaw] == nil {
                    customLatest[sample.kindRaw] = sample
                }
                continue
            }
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
        cachedCustomSamples = customGrouped
        cachedCustomLatest = customLatest
    }

    private func presentMetricDetail(_ kind: MetricKind, requestID: UUID) {
        Task { @MainActor in
            requestedMetricDetailKind = nil
            await Task.yield()
            requestedMetricDetailKind = kind
            router.consumeMetricDetailRequest(requestID)
        }
    }

    private var metricDetailPresentationBinding: Binding<Bool> {
        Binding(
            get: { requestedMetricDetailKind != nil },
            set: { isPresented in
                if !isPresented {
                    requestedMetricDetailKind = nil
                }
            }
        )
    }

    @ViewBuilder
    private var requestedMetricDetailDestination: some View {
        if let kind = requestedMetricDetailKind {
            MetricDetailView(kind: kind)
        } else {
            EmptyView()
        }
    }
}

struct MetricGoalProgressSnapshot {
    let progress: Double
    let percentage: Int
    let isAchieved: Bool

    init(goal: MetricGoal, currentValue: Double, baselineValue: Double) {
        let rawProgress: Double
        switch goal.direction {
        case .increase:
            let denominator = goal.targetValue - baselineValue
            rawProgress = denominator > 0 ? (currentValue - baselineValue) / denominator : 0
        case .decrease:
            let denominator = baselineValue - goal.targetValue
            rawProgress = denominator > 0 ? (baselineValue - currentValue) / denominator : 0
        }

        let clamped = min(max(rawProgress, 0), 1)
        self.progress = clamped
        self.percentage = Int((clamped * 100).rounded())
        self.isAchieved = goal.isAchieved(currentValue: currentValue) || clamped >= 1
    }
}

struct CompactGoalProgressPill: View {
    let progress: Double
    let percentage: Int
    let isAchieved: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColorRoles.surfaceInteractive)
                    Capsule()
                        .fill(isAchieved ? AppColorRoles.stateSuccess : accent)
                        .frame(width: proxy.size.width * max(0, min(progress, 1)))
                }
            }
            .frame(width: 28, height: 4)

            Text("\(percentage)%")
                .font(AppTypography.microBold)
                .monospacedDigit()
                .foregroundStyle(isAchieved ? AppColorRoles.stateSuccess : accent)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(AppColorRoles.surfaceInteractive, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("Progress"))
        .accessibilityValue("\(percentage)%")
    }
}

struct MetricValueText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let parts = splitValue(text)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.value)
                .font(AppTypography.dataCompact)
                .monospacedDigit()
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func splitValue(_ text: String) -> (value: String, unit: String) {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (text, "") }
        return (parts[0], parts[1])
    }
}

struct MetricTileSparklineChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let samples: [MetricSample]
    let goal: MetricGoal?
    let accent: Color
    let yDomain: ClosedRange<Double>
    let xDomain: ClosedRange<Date>
    let displayValue: (Double) -> Double
    let yAxisLabel: (Double) -> String

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Date", sample.date),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", displayValue(sample.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            accent.opacity(colorScheme == .dark ? 0.32 : 0.22),
                            accent.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(samples) { sample in
                LineMark(
                    x: .value("Date", sample.date),
                    y: .value("Value", displayValue(sample.value))
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(accent)
            }

            if let latest = samples.last {
                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("Value", displayValue(latest.value))
                )
                .symbolSize(58)
                .foregroundStyle(accent)
            }

            if let goal {
                RuleMark(y: .value("Goal", displayValue(goal.targetValue)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(AppColorRoles.textTertiary.opacity(0.55))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7))
                    .foregroundStyle(AppColorRoles.borderSubtle.opacity(colorScheme == .dark ? 0.28 : 0.42))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(.clear)
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text(yAxisLabel(numericValue))
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColorRoles.textTertiary.opacity(colorScheme == .dark ? 0.78 : 0.88))
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MeasurementsCategoryTabs: View {
    @Namespace private var selectedPillNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: MeasurementsTabView.MeasurementsTab
    let tabs: [MeasurementsTabView.MeasurementsTab]
    let activeTint: Color
    let animateSelection: Bool

    private func selectedGradient(for tab: MeasurementsTabView.MeasurementsTab) -> LinearGradient {
        switch tab {
        case .metrics:
            return ClaudeLightStyle.directionalGradient(
                colors: [
                    Color.dynamic(light: Color(hex: "#5B7CFF"), dark: Color(hex: "#7DB5FF")),
                    Color.dynamic(light: Color(hex: "#2F56D9"), dark: Color(hex: "#3B82F6"))
                ],
                colorScheme: colorScheme,
                lightColor: AppColorRoles.surfaceInteractive
            )
        case .health:
            return ClaudeLightStyle.directionalGradient(
                colors: [
                    Color.dynamic(light: Color(hex: "#1FAF9F"), dark: Color(hex: "#7BF0DA")),
                    Color.dynamic(light: Color(hex: "#0F766E"), dark: Color(hex: "#27B7A7"))
                ],
                colorScheme: colorScheme,
                lightColor: AppColorRoles.surfaceInteractive
            )
        case .physique:
            return ClaudeLightStyle.directionalGradient(
                colors: [
                    Color.dynamic(light: Color(hex: "#7667FF"), dark: Color(hex: "#C1B6FF")),
                    Color.dynamic(light: Color(hex: "#4F46E5"), dark: Color(hex: "#7C6DFF"))
                ],
                colorScheme: colorScheme,
                lightColor: AppColorRoles.surfaceInteractive
            )
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button {
                    if animateSelection {
                        withAnimation(AppMotion.standard) {
                            selectedTab = tab
                        }
                    } else {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedGradient(for: tab))
                                .matchedGeometryEffect(id: "measurements-selected-pill", in: selectedPillNamespace)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.clear)
                        }

                        Text(tab.title)
                            .font(AppTypography.captionEmphasis)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)
                            .foregroundStyle(selectedTab == tab ? (colorScheme == .dark ? Color.white.opacity(0.96) : AppColorRoles.textPrimary) : AppColorRoles.textPrimary)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selectedTab == tab ? AppColorRoles.borderStrong : AppColorRoles.borderSubtle, lineWidth: selectedTab == tab ? 0.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityID)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColorRoles.surfaceChrome)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: [
                                    activeTint.opacity(colorScheme == .dark ? 0.10 : 0.08),
                                    .clear
                                ],
                                colorScheme: colorScheme,
                                lightColor: activeTint.opacity(0.04)
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColorRoles.borderStrong, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .inset(by: 0.5)
                        .stroke(AppColorRoles.surfaceCanvas.opacity(0.32), lineWidth: 0.6)
                )
        )
        .frame(minHeight: 64)
        .fixedSize(horizontal: false, vertical: true)
        .animation(animateSelection ? AppMotion.standard : nil, value: selectedTab)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("measurements.tab.segmented")
    }
}


struct MetricChartTile: View {
    private let measurementsTheme = FeatureTheme.measurements
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: MetricKind
    let unitsSystem: String
    @AppSetting(\.profile.userName) private var userName: String = ""

    @Query private var samples: [MetricSample]
    @Query private var goals: [MetricGoal]

    @State private var shortInsight: String?
    @State private var isLoadingInsight = false
    // Chart scrubbing removed from tile - available only in MetricDetailView

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
    
    // Current goal for this metric
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
            // MARK: - Compact empty tile (no data)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            kind.iconView(size: 20, tint: measurementsTheme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .layoutPriority(1)

                                Text(AppLocalization.string("measurements.metric.nodata"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textTertiary)
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
                                    .foregroundStyle(AppColorRoles.textTertiary)
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
                                kind.iconView(size: 20, tint: measurementsTheme.accent)

                                Text(kind.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .layoutPriority(1)
                            }

                            Text(AppLocalization.string("measurements.metric.nodata"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textTertiary)
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
                                .foregroundStyle(AppColorRoles.textTertiary)
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
                    tint: measurementsTheme.softTint
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.string("accessibility.metric.summary.nodata", kind.title))
            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
        } else {
            // MARK: - Full tile with chart
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        kind.iconView(size: 24, tint: metricAccent)

                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .layoutPriority(1)

                        Spacer(minLength: 8)

                        if let goalProgress {
                            CompactGoalProgressPill(
                                progress: goalProgress.progress,
                                percentage: goalProgress.percentage,
                                isAchieved: goalProgress.isAchieved,
                                accent: metricAccent
                            )
                        }

                        NavigationLink {
                            MetricDetailView(kind: kind)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(AppTypography.iconMedium)
                                .foregroundStyle(AppColorRoles.textTertiary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metric.tile.open.\(kind.rawValue)")
                    }

                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let latest {
                                MetricValueText(valueString(metricValue: latest.value))

                                if let trendInfo {
                                    HStack(spacing: 5) {
                                        Image(systemName: trendInfo.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            .font(AppTypography.microEmphasis)
                                        Text(kind.formattedDisplayValue(abs(trendInfo.delta), unitsSystem: unitsSystem))
                                            .monospacedDigit()
                                        Text(AppLocalization.string("trend.vs.relative", trendInfo.relativeText))
                                            .foregroundStyle(AppColorRoles.textTertiary)
                                    }
                                    .font(AppTypography.captionEmphasis)
                                    .foregroundStyle(trendColor(for: trendInfo.outcome))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                }
                            } else {
                                Text(AppLocalization.string("—"))
                                    .font(AppTypography.dataCompact)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                        }
                        .frame(width: 126, alignment: .leading)

                        MetricTileSparklineChart(
                            samples: recentSamples,
                            goal: currentGoal,
                            accent: metricAccent,
                            yDomain: yDomain,
                            xDomain: xDomain,
                            displayValue: displayValue,
                            yAxisLabel: { kind.formattedDisplayValue($0, unitsSystem: unitsSystem, includeUnit: false) }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                        .accessibilityChartDescriptor(MetricChartAXDescriptor(descriptor: chartDescriptor))
                    }
                }
                .padding(16)

                if let footerInsightText {
                    Divider()
                        .overlay(AppColorRoles.borderSubtle.opacity(0.7))

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(metricAccent)
                            .padding(.top, 2)

                        Text(footerInsightText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        if premiumStore.isPremium && !appleIntelligenceAvailable {
                            Spacer(minLength: 4)
                            NavigationLink {
                                FAQView()
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(AppTypography.micro)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(
                AppGlassBackground(
                    depth: .elevated,
                    cornerRadius: 22,
                    tint: measurementsTheme.softTint
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
        kind.formattedMetricValue(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    private var metricAccent: Color {
        switch kind {
        case .weight, .leanBodyMass:
            return AppColorRoles.accentPrimary
        case .bodyFat:
            return Color.appRose
        case .waist, .hips:
            return Color.appTeal
        case .height:
            return Color.appCyan
        case .neck, .shoulders, .bust, .chest:
            return Color.appIndigo
        case .leftBicep, .rightBicep, .leftForearm, .rightForearm:
            return Color.appEmerald
        case .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return Color.appAmber
        }
    }

    private var goalProgress: MetricGoalProgressSnapshot? {
        guard let goal = currentGoal, let latest else { return nil }
        let baseline = baselineValue(for: goal)
        return MetricGoalProgressSnapshot(goal: goal, currentValue: latest.value, baselineValue: baseline)
    }

    private var footerInsightText: String? {
        if canUseAppleIntelligence {
            if isLoadingInsight { return AppLocalization.aiString("Generating insight...") }
            if let shortInsight { return shortInsight }
        }
        if premiumStore.isPremium && !appleIntelligenceAvailable {
            return AppLocalization.aiString("AI Insights aren't available right now.")
        }
        return localInsightText
    }

    private var localInsightText: String? {
        if let trendInfo {
            let deltaText = kind.formattedDisplayValue(abs(trendInfo.delta), unitsSystem: unitsSystem)
            let direction = trendInfo.delta >= 0
                ? AppLocalization.aiString("up")
                : AppLocalization.aiString("down")
            if let progress = goalProgress {
                if progress.isAchieved {
                    return AppLocalization.aiString("Goal reached. Last 30 days are %@ %@, so keep checking consistency before changing the target.", direction, deltaText)
                }
                return AppLocalization.aiString("%d%% toward goal. Last 30 days are %@ %@, which helps judge whether the current pace is realistic.", progress.percentage, direction, deltaText)
            }
            switch trendInfo.outcome {
            case .positive:
                return AppLocalization.aiString("Last 30 days moved %@ %@ in a favorable direction. Keep the same measurement rhythm to confirm the trend.", direction, deltaText)
            case .negative:
                return AppLocalization.aiString("Last 30 days moved %@ %@ against the preferred direction. Check whether training, recovery, or intake changed recently.", direction, deltaText)
            case .neutral:
                return AppLocalization.aiString("This metric is broadly steady over 30 days. More consistent check-ins will make subtle changes easier to trust.")
            }
        }
        return AppLocalization.aiString("Add more check-ins to build a reliable 30-day trend for this metric.")
    }

    private var yDomain: ClosedRange<Double> {
        var values = recentSamples.map { displayValue($0.value) }
        
        // Add goal value to the range if a goal exists
        if let goal = currentGoal {
            values.append(displayValue(goal.targetValue))
        }
        
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 1)
        let padding = span * 0.15
        return (minV - padding)...(maxV + padding)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = recentSamples.first?.date,
              let last = recentSamples.last?.date else {
            let start = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
            return start...AppClock.now
        }
        if first == last {
            let start = Calendar.current.date(byAdding: .hour, value: -12, to: first) ?? first
            let end = Calendar.current.date(byAdding: .hour, value: 12, to: first) ?? first
            return start...end
        }
        return first...last
    }

    private func baselineValue(for goal: MetricGoal) -> Double {
        if let startValue = goal.startValue { return startValue }
        let sorted = recentSamples.sorted { $0.date < $1.date }
        let anchorDate = goal.startDate ?? goal.createdDate
        if let baseline = sorted.last(where: { $0.date <= anchorDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? latest?.value ?? goal.targetValue
    }

    private func trendColor(for outcome: MetricKind.TrendOutcome) -> Color {
        switch outcome {
        case .positive:
            return AppColorRoles.chartPositive
        case .negative:
            return AppColorRoles.chartNegative
        case .neutral:
            return AppColorRoles.textTertiary
        }
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
            measurementContext: kind.insightMeasurementContext,
            latestValueText: valueString(metricValue: latest.value),
            timeframeLabel: "Last 30 days",
            sampleCount: recentSamples.count,
            delta7DaysText: recentSamples.deltaText(days: 7, kind: kind, unitsSystem: unitsSystem),
            delta14DaysText: nil,
            delta30DaysText: recentSamples.deltaText(days: 30, kind: kind, unitsSystem: unitsSystem),
            delta90DaysText: nil,
            goalStatusText: goalStatusText,
            goalDirectionText: currentGoal?.direction.rawValue,
            defaultFavorableDirectionText: kind.defaultFavorableDirectionWhenNoGoal.rawValue
        )
    }

    private var goalStatusText: String? {
        guard let goal = currentGoal, let latest else { return nil }
        if goal.isAchieved(currentValue: latest.value) {
            return "Goal reached"
        }
        let remaining = displayValue(abs(goal.remainingToGoal(currentValue: latest.value)))
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return "\(remaining) \(unit) away from goal"
    }

    private var accessibilitySummary: String {
        if let latest {
            let value = valueString(metricValue: latest.value)
            if let trendInfo {
                let deltaText = kind.formattedDisplayValue(abs(trendInfo.delta), unitsSystem: unitsSystem)
                return AppLocalization.string("accessibility.metric.summary.trend", kind.title, value, deltaText, trendInfo.relativeText)
            }
            return AppLocalization.string("accessibility.metric.summary.value", kind.title, value)
        }
        return AppLocalization.string("accessibility.metric.summary.nodata", kind.title)
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
                kind.formattedDisplayValue(value, unitsSystem: unitsSystem)
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
                kind.formattedDisplayValue(first, unitsSystem: unitsSystem, includeUnit: false),
                kind.formattedDisplayValue(last, unitsSystem: unitsSystem, includeUnit: false),
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
