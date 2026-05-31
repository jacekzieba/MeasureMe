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
    @State private var viewModel = MeasurementsTabViewModel()
    @Query private var samples: [MetricSample]

    @Query(sort: \CustomMetricDefinition.sortOrder) private var customDefinitions: [CustomMetricDefinition]

    // Binding-required state (must stay in View)
    @State private var selectedTab: MeasurementsTab = .metrics
    @State private var requestedMetricDetailKind: MetricKind?
    @State private var metricDetailPath: [MetricKind] = []

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

    private var samplesByKind: [MetricKind: [MetricSample]] { viewModel.cachedSamplesByKind }

    private var latestByKind: [MetricKind: MetricSample] { viewModel.cachedLatestByKind }

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
        NavigationStack(path: $metricDetailPath) {
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
                                    premiumStore.presentPaywall(reason: .premiumMetric)
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
                                    premiumStore.presentPaywall(reason: .premiumMetric)
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
                .id(viewModel.refreshToken)
                .accessibilityIdentifier("measurements.scroll")
                .refreshable {
                    rebuildSamplesCache()
                    viewModel.refreshToken = UUID()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: MetricKind.self) { kind in
                MetricDetailView(kind: kind)
            }
        }
        .onAppear {
            rebuildSamplesCache()
            if let requestID = router.metricDetailRequestID,
               let kind = router.requestedMetricDetailKind {
                scheduleMetricDetailPresentation(kind, requestID: requestID)
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
            scheduleMetricDetailPresentation(kind, requestID: requestID)
        }
        .onChange(of: metricDetailPath) { _, path in
            if path.isEmpty {
                requestedMetricDetailKind = nil
            }
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
                bottomPadding: AppSpacing.xs,
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
        viewModel.cachedSamplesByKind = grouped
        viewModel.cachedLatestByKind = latest
        viewModel.cachedCustomSamples = customGrouped
        viewModel.cachedCustomLatest = customLatest
    }

    private func presentMetricDetail(_ kind: MetricKind, requestID: UUID) {
        requestedMetricDetailKind = kind
        metricDetailPath = [kind]
        router.consumeMetricDetailRequest(requestID)
    }

    private func scheduleMetricDetailPresentation(_ kind: MetricKind, requestID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard router.metricDetailRequestID == requestID else { return }
            presentMetricDetail(kind, requestID: requestID)
        }
    }
}
