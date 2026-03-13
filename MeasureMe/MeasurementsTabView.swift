import SwiftUI
import Charts
import SwiftData
import Foundation
import Accessibility

struct MeasurementsTabView: View {
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
    @State private var scrollOffset: CGFloat = 0
    @State private var refreshToken = UUID()
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]
    @State private var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @State private var cachedLatestByKind: [MetricKind: MetricSample] = [:]

    @State private var selectedTab: MeasurementsTab = .metrics

    private let healthAccent = HealthIndicatorPalette.accent

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
            return measurementsTheme.softTint
        case .health:
            return healthTheme.softTint
        case .physique:
            return AppColorRoles.accentPhysique.opacity(0.18)
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
            latestHips: latestHips
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
                    scrollOffset: scrollOffset,
                    tint: sectionTint
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

                        if selectedTab == .metrics {
                            AISectionSummaryCard(
                                input: metricsSummaryInput,
                                missingDataMessage: AppLocalization.string("AI summary needs metric data. Add measurements to generate insights."),
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
                                    contentPadding: AppSpacing.sm
                                ) {
                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        HStack(spacing: AppSpacing.xs) {
                                            Image(systemName: "sparkles")
                                                .font(.body)
                                                .foregroundStyle(measurementsTheme.accent)

                                            Text(AppLocalization.string("measurements.discovery.hint", metricsStore.activeKinds.count, metricsStore.allKindsInOrder.count))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColorRoles.textSecondary)
                                        }

                                        Button {
                                            Haptics.selection()
                                            settingsOpenTrackedMeasurements = true
                                            router.selectedTab = .settings
                                        } label: {
                                            HStack(spacing: 6) {
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

                            trackedMetricsFooter
                                .padding(.horizontal, AppSpacing.md)
                        } else if selectedTab == .health {
                            if premiumStore.isPremium {
                                AISectionSummaryCard(
                                    input: healthSummaryInput,
                                    missingDataMessage: AppLocalization.string("AI summary needs health indicator data. Add required measurements first."),
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
                                    missingDataMessage: AppLocalization.string("AI summary needs physique indicator data. Add required measurements first."),
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
            .toolbarBackground(.hidden, for: .navigationBar)
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

private struct MeasurementsCategoryTabs: View {
    @Namespace private var selectedPillNamespace
    @Binding var selectedTab: MeasurementsTabView.MeasurementsTab
    let tabs: [MeasurementsTabView.MeasurementsTab]
    let activeTint: Color
    let animateSelection: Bool

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
                                .fill(activeTint)
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
                            .foregroundStyle(selectedTab == tab ? AppColorRoles.textOnAccent : AppColorRoles.textPrimary)
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
                .fill(.ultraThinMaterial)
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
        .animation(animateSelection ? AppMotion.standard : nil, value: selectedTab)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("measurements.tab.segmented")
    }
}


struct MetricChartTile: View {
    private let measurementsTheme = FeatureTheme.measurements
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: MetricKind
    let unitsSystem: String
    @AppSetting(\.profile.userName) private var userName: String = ""

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
            // MARK: - Pelny kafelek z wykresem
            VStack(alignment: .leading, spacing: 10) {

                // Header
                HStack {
                    HStack(spacing: 8) {
                        kind.iconView(size: 20, tint: measurementsTheme.accent)

                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                    }

                    Spacer()

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

                // Wartosc + trend + informacje o celu
                if let latest {
                    Text(valueString(metricValue: latest.value))
                        .font(AppTypography.dataCompact)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)

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
                            ? AppColorRoles.chartPositive
                            : (trendInfo.outcome == .negative ? AppColorRoles.chartNegative : AppColorRoles.textTertiary)
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
                        .foregroundStyle(isAchieved ? AppColorRoles.stateSuccess : measurementsTheme.accent)
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
                                .foregroundStyle(AppColorRoles.textSecondary)
                            NavigationLink {
                                FAQView()
                            } label: {
                                Text(AppLocalization.string("Learn more in FAQ"))
                                    .font(AppTypography.microEmphasis)
                                    .foregroundStyle(measurementsTheme.accent)
                            }
                        }
                    }
                } else {
                    Text(AppLocalization.string("—"))
                        .font(AppTypography.dataHero)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }

                // Chart - z podwójnym maskowaniem
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        // Tło wykresu
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0))

                        Chart {

                        // 🔹 AREA – gradient zanikający od linii w dół
                        ForEach(recentSamples) { s in
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

                        }

                        // 🔸 LINIA
                        ForEach(recentSamples) { s in
                            LineMark(
                                x: .value("Date", s.date),
                                y: .value("Value", displayValue(s.value))
                            )
                            .interpolationMethod(.monotone)
                            .lineStyle(.init(lineWidth: 2.5))
                            .foregroundStyle(measurementsTheme.accent)
                        }

                        // 🔸 PUNKTY
                        ForEach(recentSamples) { s in
                            PointMark(
                                x: .value("Date", s.date),
                                y: .value("Value", displayValue(s.value))
                            )
                            .symbolSize(24)
                            .foregroundStyle(measurementsTheme.accent.opacity(0.6))
                        }

                        // Linia celu (z annotation)
                        if let goal = currentGoal {
                            let goalValue = displayValue(goal.targetValue)
                            RuleMark(y: .value("Goal", goalValue))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                                .foregroundStyle(AppColorRoles.textSecondary.opacity(0.7))
                                .annotation(position: goalLabelPosition(for: goalValue), alignment: .leading) {
                                    Text(AppLocalization.string("Goal"))
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColorRoles.textPrimary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(AppColorRoles.surfaceCanvas.opacity(0.82))
                                        )
                                        .offset(x: 6)
                                }
                        }

                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
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
