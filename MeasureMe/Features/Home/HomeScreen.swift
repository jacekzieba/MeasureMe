import SwiftUI
import SwiftData

/// HomeView - Ulepszona wersja z mini wykresami i sekcją ostatnich zdjęć
/// 
/// Funkcje:
/// - Maksymalnie 3 kluczowe metryki na Home (z "View more" poniżej)
/// - Nagłówek sekcji "Measurements"
/// - Ulepszone kafelki z mini wykresami sparkline (30 dni)
/// - Sekcja "Last Photos" z maksymalnie 6 ostatnimi zdjęciami (2 rzędy po 3)
/// - Kolorystyka: wzrost = zielony, spadek = czerwony
struct HomeView: View {
    @ObservedObject private var settingsStore = AppSettingsStore.shared

    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.health.isSyncEnabled) var isSyncEnabled: Bool = false
    @AppSetting(\.home.showLastPhotosOnHome) private var showLastPhotosOnHome: Bool = true
    @AppSetting(\.home.showMeasurementsOnHome) private var showMeasurementsOnHome: Bool = true
    @AppSetting(\.home.showHealthMetricsOnHome) private var showHealthMetricsOnHome: Bool = true
    @AppSetting(\.home.showStreakOnHome) private var showStreakOnHome: Bool = true
    @AppSetting(\.home.homeTabScrollOffset) private var homeTabScrollOffset: Double = 0.0
    @AppSetting(\.onboarding.onboardingSkippedHealthKit) private var onboardingSkippedHealthKit: Bool = false
    @AppSetting(\.onboarding.onboardingSkippedReminders) private var onboardingSkippedReminders: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistShow) private var showOnboardingChecklistOnHome: Bool = true
    @AppSetting(\.onboarding.onboardingChecklistMetricsCompleted) private var onboardingChecklistMetricsCompleted: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistPremiumExplored) private var onboardingChecklistPremiumExplored: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistCollapsed) private var onboardingChecklistCollapsed: Bool = false
    @AppSetting(\.home.settingsOpenTrackedMeasurements) private var settingsOpenTrackedMeasurements: Bool = false
    @AppSetting(\.home.settingsOpenReminders) private var settingsOpenReminders: Bool = false
    @AppSetting(\.home.homePhotoMetricSyncLastDate) private var photoMetricSyncLastDate: Double = 0
    @AppSetting(\.home.homePhotoMetricSyncLastID) private var photoMetricSyncLastID: String = ""
    
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var streakManager: StreakManager

    @Query private var recentSamples: [MetricSample]
    
    @Query private var goals: [MetricGoal]
    
    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)])
    private var allPhotos: [PhotoEntry]
    
    @State private var showQuickAddSheet = false
    @State private var selectedPhotoForFullScreen: PhotoEntry?
    @State private var scrollOffset: CGFloat = 0
    @State private var lastPhotosGridWidth: CGFloat = 0
    @State private var checklistStatusText: String?
    @State private var isChecklistConnectingHealth: Bool = false
    @State private var reminderChecklistCompleted: Bool = false
    @State private var showMoreChecklistItems: Bool = false
    @State private var didCheckSevenDayPaywallPrompt: Bool = false
    @State private var didRunStartupPhases = false
    @State private var didEmitHomeInitialRender = false
    @State private var isPhotoMetricSyncInFlight = false
    @State private var isLastPhotosSectionMounted = false
    @State private var isHealthSectionMounted = false
    @State private var deferredPhaseBTask: Task<Void, Never>?
    @State private var deferredPhaseCTask: Task<Void, Never>?
    @State private var deferredSectionMountTask: Task<Void, Never>?
    
    // Dane HealthKit
    @State var latestBodyFat: Double?
    @State var latestLeanMass: Double?
    @State private var hasAnyMeasurements = false

    // Zbuforowane dane pochodne - odswiezane przez onChange zamiast przeliczania przy kazdym renderze
    @State private var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @State private var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    @State private var cachedGoalsByKind: [MetricKind: MetricGoal] = [:]

    private let maxVisibleMetrics = 3
    private let maxVisiblePhotos = 6
    private let autoCheckPaywallPrompt: Bool
    let effects: HomeEffects
    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    // Designated initializer that accepts an explicit streakManager to avoid touching MainActor in default params (Swift 6 safe)
    init(
        autoCheckPaywallPrompt: Bool = true,
        streakManager: StreakManager,
        effects: HomeEffects = .live
    ) {
        self.autoCheckPaywallPrompt = autoCheckPaywallPrompt
        self.effects = effects
        _streakManager = ObservedObject(wrappedValue: streakManager)
        let recentWindowStart = Calendar.current.date(byAdding: .day, value: -120, to: AppClock.now) ?? .distantPast
        _recentSamples = Query(
            filter: #Predicate<MetricSample> { $0.date >= recentWindowStart },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    // Convenience initializer that safely captures the MainActor-isolated singleton
    init(
        autoCheckPaywallPrompt: Bool = true,
        effects: HomeEffects = .live
    ) {
        // Access StreakManager.shared on the main actor to satisfy isolation rules
        let manager: StreakManager = StreakManager.shared
        self.init(
            autoCheckPaywallPrompt: autoCheckPaywallPrompt,
            streakManager: manager,
            effects: effects
        )
    }

    private struct SetupChecklistItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let isCompleted: Bool
        let isLoading: Bool
    }

    private enum HomePhotoTile: Identifiable {
        case persisted(PhotoEntry)
        case pending(PendingPhotoSaveItem)

        var id: String {
            switch self {
            case .persisted(let photo):
                return "persisted_\(String(describing: photo.persistentModelID))"
            case .pending(let item):
                return "pending_\(item.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .persisted(let photo):
                return photo.date
            case .pending(let item):
                return item.date
            }
        }
    }
    
    private var lastPhotosGridSide: CGFloat {
        let spacing: CGFloat = 8
        let totalSpacing = spacing * 2
        guard lastPhotosGridWidth.isFinite, lastPhotosGridWidth > 0 else { return 86 }
        let raw = (lastPhotosGridWidth - totalSpacing) / 3
        guard raw.isFinite, raw > 0 else { return 86 }
        return max(floor(raw), 86)
    }

    
    /// Widoczne metryki (maksymalnie 3)
    private var visibleMetrics: [MetricKind] {
        Array(metricsStore.keyMetrics.prefix(maxVisibleMetrics))
    }

    /// Metryki renderowane w widget boardzie.
    /// Duzy kafel na iPhone nie miesci stabilnie 3 pelnych wierszy.
    private var dashboardVisibleMetrics: [MetricKind] {
        Array(visibleMetrics.prefix(2))
    }
    
    
    /// Widoczne kafelki zdjęć (persisted + pending, maksymalnie 6)
    private var visiblePhotoTiles: [HomePhotoTile] {
        let persistedCandidateLimit = maxVisiblePhotos * 3
        let persistedTiles = allPhotos.prefix(persistedCandidateLimit).map { HomePhotoTile.persisted($0) }
        let pendingTiles = pendingPhotoSaveStore.pendingItems.map { HomePhotoTile.pending($0) }
        return (persistedTiles + pendingTiles)
            .sorted { lhs, rhs in lhs.date > rhs.date }
            .prefix(maxVisiblePhotos)
            .map { $0 }
    }

    private var dashboardRecentPhotoTiles: [HomePhotoTile] {
        Array(visiblePhotoTiles.prefix(3))
    }

    private var hasAnyPhotoContent: Bool {
        !allPhotos.isEmpty || !pendingPhotoSaveStore.pendingItems.isEmpty
    }
    
    /// Słownik próbek dla każdego rodzaju metryki
    private func samplesForKind(_ kind: MetricKind) -> [MetricSample] {
        cachedSamplesByKind[kind] ?? []
    }
    
    /// Najnowsze pomiary dla wskaźników zdrowotnych
    private var latestWaist: Double? {
        cachedLatestByKind[.waist]?.value
    }

    private var latestHeight: Double? {
        cachedLatestByKind[.height]?.value
    }

    private var latestWeight: Double? {
        cachedLatestByKind[.weight]?.value
    }

    private var weightDelta7dText: String? {
        metricDeltaTextFromCache(kind: .weight, days: 7)
    }

    private var waistDelta7dText: String? {
        metricDeltaTextFromCache(kind: .waist, days: 7)
    }

    // MARK: - Cache Rebuild Helpers

    private var recentSamplesSignature: String {
        guard let newest = recentSamples.first else { return "0" }
        let oldest = recentSamples.last ?? newest
        return [
            String(recentSamples.count),
            String(describing: newest.persistentModelID),
            String(newest.date.timeIntervalSinceReferenceDate),
            String(describing: oldest.persistentModelID),
            String(oldest.date.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func refreshMeasurementCaches(allowFallbackFetch: Bool = true) {
        var grouped: [MetricKind: [MetricSample]] = [:]
        var latest: [MetricKind: MetricSample] = [:]
        let kindsToKeep = Set(metricsStore.activeKinds).union([.waist, .height, .weight, .bodyFat, .leanBodyMass, .hips])

        for sample in recentSamples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else {
                AppLog.debug("⚠️ Ignoring MetricSample with invalid kindRaw: \(sample.kindRaw)")
                continue
            }
            grouped[kind, default: []].append(sample)
            if kindsToKeep.contains(kind), latest[kind] == nil {
                latest[kind] = sample
            }
        }

        cachedSamplesByKind = grouped
        cachedLatestByKind = latest

        if !recentSamples.isEmpty {
            hasAnyMeasurements = true
        } else if allowFallbackFetch {
            var descriptor = FetchDescriptor<MetricSample>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            hasAnyMeasurements = ((try? modelContext.fetch(descriptor).isEmpty) == false)
        } else {
            hasAnyMeasurements = false
        }

        autoHideChecklistIfCompleted()
    }

    private func metricDeltaTextFromCache(kind: MetricKind, days: Int) -> String? {
        (cachedSamplesByKind[kind] ?? []).deltaText(days: days, kind: kind, unitsSystem: unitsSystem)
    }

    private enum PhotoSyncMode {
        case full
        case incremental
    }

    private var hasPhotoSyncCursor: Bool {
        photoMetricSyncLastDate > 0
    }

    private func syncMode(force: Bool) -> PhotoSyncMode {
        if force || !hasPhotoSyncCursor {
            return .full
        }
        return .incremental
    }

    private func photoCursorID(for photo: PhotoEntry) -> String {
        String(describing: photo.persistentModelID)
    }

    private func isPhotoAfterSyncCursor(_ photo: PhotoEntry) -> Bool {
        HomeView.isAfterPhotoSyncCursor(
            photoDate: photo.date,
            photoID: photoCursorID(for: photo),
            cursorDate: photoMetricSyncLastDate,
            cursorID: photoMetricSyncLastID
        )
    }

    private func updatePhotoSyncCursor(using photos: [PhotoEntry]) {
        let candidates = photos.map { (date: $0.date, id: photoCursorID(for: $0)) }
        guard let cursor = HomeView.newestPhotoSyncCursor(candidates: candidates) else { return }
        photoMetricSyncLastDate = cursor.date
        photoMetricSyncLastID = cursor.id
    }

    private func fetchSyncCandidatePhotos(mode: PhotoSyncMode) throws -> [PhotoEntry] {
        let descriptor: FetchDescriptor<PhotoEntry>
        switch mode {
        case .full:
            descriptor = FetchDescriptor<PhotoEntry>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        case .incremental:
            let cursorDate = Date(timeIntervalSince1970: photoMetricSyncLastDate)
            descriptor = FetchDescriptor<PhotoEntry>(
                predicate: #Predicate<PhotoEntry> { photo in
                    photo.date >= cursorDate
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        }
        return try modelContext.fetch(descriptor)
    }
    
    /// Synchronizuje probki Measurement ze snapshotami metryk zapisanymi przy zdjeciach.
    /// - Behavior:
    ///   - Dla kazdego PhotoEntry i MetricValueSnapshot upewnia sie, ze istnieje MetricSample dla daty snapshotu.
    ///   - Jesli probka dla (kind,date) istnieje, aktualizuje jej wartosc do wartosci snapshotu.
    ///   - If none exists, insert a new MetricSample.
    ///   - Nigdy nie usuwa MetricSample po usunieciu zdjecia; funkcja wykonuje tylko upsert.
    private func syncMeasurementsFromPhotosIfNeeded(force: Bool = false) {
        guard !isPhotoMetricSyncInFlight else { return }
        let mode = syncMode(force: force)
        let isIncrementalMode = mode == .incremental
        isPhotoMetricSyncInFlight = true
        defer {
            if isIncrementalMode {
                StartupInstrumentation.event("HomePhotoSyncIncrementalEnd")
            }
            isPhotoMetricSyncInFlight = false
        }

        switch mode {
        case .full:
            StartupInstrumentation.event("HomePhotoSyncModeFull")
        case .incremental:
            StartupInstrumentation.event("HomePhotoSyncModeIncremental")
            StartupInstrumentation.event("HomePhotoSyncIncrementalStart")
        }

        let candidatePhotos: [PhotoEntry]
        do {
            candidatePhotos = try fetchSyncCandidatePhotos(mode: mode)
        } catch {
            AppLog.debug("⚠️ Failed to fetch sync candidate photos: \(error)")
            return
        }
        guard !candidatePhotos.isEmpty else { return }

        let photosWithMetrics: [PhotoEntry]
        switch mode {
        case .full:
            photosWithMetrics = candidatePhotos.filter { !$0.linkedMetrics.isEmpty }
        case .incremental:
            photosWithMetrics = candidatePhotos.filter { photo in
                !photo.linkedMetrics.isEmpty && isPhotoAfterSyncCursor(photo)
            }
        }
        guard !photosWithMetrics.isEmpty else {
            updatePhotoSyncCursor(using: candidatePhotos)
            return
        }

        let syncedKindsRaw = Set(
            photosWithMetrics
                .flatMap(\.linkedMetrics)
                .compactMap { $0.kind?.rawValue }
        )

        // Buduje cache istniejacych probek po (kindRaw, dayStart)
        var existingByKey: [String: MetricSample] = [:]
        do {
            let descriptor: FetchDescriptor<MetricSample>
            if syncedKindsRaw.isEmpty {
                descriptor = FetchDescriptor<MetricSample>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            } else {
                let kinds = Array(syncedKindsRaw)
                descriptor = FetchDescriptor<MetricSample>(
                    predicate: #Predicate<MetricSample> { sample in
                        kinds.contains(sample.kindRaw)
                    },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            }
            let existing = try modelContext.fetch(descriptor)
            let cal = Calendar.current
            for s in existing {
                let startOfDay = cal.startOfDay(for: s.date)
                let key = "\(s.kindRaw)|\(startOfDay.timeIntervalSince1970)"
                if existingByKey[key] == nil { existingByKey[key] = s }
            }
        } catch {
            AppLog.debug("⚠️ Failed to build existing samples index: \(error)")
        }

        // Iteruje po zdjeciach i wykonuje upsert probek dla kazdego snapshotu
        let calendar = Calendar.current
        for photo in photosWithMetrics {
            let photoDate = photo.date
            let dayStart = calendar.startOfDay(for: photoDate)
            for snapshot in photo.linkedMetrics {
                guard let kind = snapshot.kind else { continue }
                let kindRaw = kind.rawValue
                let key = "\(kindRaw)|\(dayStart.timeIntervalSince1970)"
                if let sample = existingByKey[key] {
                    // Aktualizuje istniejaca probke do wartosci snapshotu i daty zdjecia (dokladny czas)
                    sample.value = snapshot.value
                    sample.date = photoDate
                } else {
                    let sample = MetricSample(kind: kind, value: snapshot.value, date: photoDate)
                    modelContext.insert(sample)
                    existingByKey[key] = sample
                }
            }
        }

        // Celowo bez usuwania (usuniecie zdjecia nie powinno kasowac probek)
        updatePhotoSyncCursor(using: candidatePhotos)
    }

    private func emitHomeInitialRenderIfNeeded() {
        guard !didEmitHomeInitialRender else { return }
        didEmitHomeInitialRender = true
        StartupInstrumentation.event("HomeInitialRender")
    }

    private func runStartupPhasesIfNeeded() {
        guard !didRunStartupPhases else { return }
        didRunStartupPhases = true
        runCriticalStartupPhaseA()
        scheduleDeferredStartupPhaseB()
        scheduleDeferredStartupPhaseC()
        scheduleDeferredSectionMounts()
    }

    private func runCriticalStartupPhaseA() {
        hasAnyMeasurements = !recentSamples.isEmpty
        isLastPhotosSectionMounted = false
        isHealthSectionMounted = false
    }

    private func scheduleDeferredStartupPhaseB() {
        deferredPhaseBTask?.cancel()
        deferredPhaseBTask = Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            refreshMeasurementCaches()
            rebuildGoalsCache()
            refreshChecklistState()
            fetchHealthKitData()
            streakManager.recordAppOpen(context: modelContext)
        }
    }

    private func scheduleDeferredStartupPhaseC(
        delayMilliseconds: Int = 1500,
        forceSync: Bool = false
    ) {
        deferredPhaseCTask?.cancel()
        deferredPhaseCTask = Task(priority: .background) { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }

            let deferredSyncState = StartupInstrumentation.begin("HomeDeferredSync")
            StartupInstrumentation.event("HomeDeferredSyncStart")
            syncMeasurementsFromPhotosIfNeeded(force: forceSync)
            StartupInstrumentation.event("HomeDeferredSyncEnd")
            StartupInstrumentation.end("HomeDeferredSync", state: deferredSyncState)
        }
    }

    private func scheduleDeferredSectionMounts() {
        deferredSectionMountTask?.cancel()
        deferredSectionMountTask = Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            StartupInstrumentation.event("HomeLastPhotosMountStart")
            isLastPhotosSectionMounted = true
            StartupInstrumentation.event("HomeLastPhotosMountEnd")

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            StartupInstrumentation.event("HomeHealthMountStart")
            isHealthSectionMounted = true
            StartupInstrumentation.event("HomeHealthMountEnd")
        }
    }

    /// Przebudowuje goalsByKind na podstawie tablicy celow @Query.
    private func rebuildGoalsCache() {
        var dict: [MetricKind: MetricGoal] = [:]
        for goal in goals {
            if let kind = MetricKind(rawValue: goal.kindRaw) {
                dict[kind] = goal
            }
        }
        cachedGoalsByKind = dict
    }

    private var dashboardColumns: Int {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular ? 4 : 2
    }

    private var normalizedHomeLayout: HomeLayoutSnapshot {
        let layout = settingsStore.homeLayoutSnapshot()
        return HomeLayoutNormalizer.normalize(layout, using: settingsStore.snapshot)
    }

    private var renderedDashboardItems: [HomeModuleLayoutItem] {
        let runtimeVisibleItems = normalizedHomeLayout.items.map { item in
            var next = item
            next.isVisible = item.isVisible && shouldRenderModule(item.kind)
            return next
        }
        return HomeLayoutCompactor.compact(runtimeVisibleItems, columns: dashboardColumns)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(
                topHeight: 380,
                scrollOffset: scrollOffset,
                tint: Color.cyan.opacity(0.22)
            )

            // Zawartość przewijalna
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: HomeScrollOffsetKey.self,
                                value: proxy.frame(in: .named("homeScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    HomeDashboardBoard(
                        items: renderedDashboardItems,
                        columns: dashboardColumns
                    ) { item in
                        homeModuleView(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { value in
                scrollOffset = value
                homeTabScrollOffset = Double(value)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrollOffset < -16 ? .visible : .hidden, for: .navigationBar)
        .sheet(isPresented: $showQuickAddSheet) {
            QuickAddSheetView(
                kinds: metricsStore.activeKinds,
                latest: Dictionary(
                    uniqueKeysWithValues: cachedLatestByKind.map { ($0.key, ($0.value.value, $0.value.date)) }
                ),
                unitsSystem: unitsSystem
            ) {
                showQuickAddSheet = false
            }
        }
        .sheet(item: $selectedPhotoForFullScreen) { photo in
            PhotoDetailView(photo: photo)
        }
        .onAppear {
            DispatchQueue.main.async {
                if autoCheckPaywallPrompt && !didCheckSevenDayPaywallPrompt {
                    didCheckSevenDayPaywallPrompt = true
                    premiumStore.checkSevenDayPromptIfNeeded()
                }
                emitHomeInitialRenderIfNeeded()
                runStartupPhasesIfNeeded()
            }
        }
        .onChange(of: recentSamplesSignature) { _, _ in
            refreshMeasurementCaches()
        }
        .onChange(of: metricsStore.activeKinds) { _, _ in
            refreshMeasurementCaches()
        }
        .onChange(of: goals.count) { _, _ in
            rebuildGoalsCache()
        }
        .onChange(of: isSyncEnabled) { _, _ in
            refreshChecklistState()
            fetchHealthKitData()
        }
        .onChange(of: allPhotos.count) { _, _ in
            refreshChecklistState()
            if didRunStartupPhases {
                scheduleDeferredStartupPhaseC(delayMilliseconds: 900)
            }
        }
        .onChange(of: onboardingChecklistMetricsCompleted) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: onboardingChecklistPremiumExplored) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: onboardingSkippedHealthKit) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: onboardingSkippedReminders) { _, _ in
            refreshChecklistState()
        }
        .refreshable {
            syncMeasurementsFromPhotosIfNeeded(force: true)
            refreshMeasurementCaches()
            rebuildGoalsCache()
            fetchHealthKitData()
            refreshChecklistState()
        }
    }

    private func shouldRenderModule(_ kind: HomeModuleKind) -> Bool {
        switch kind {
        case .summaryHero, .quickActions:
            return true
        case .keyMetrics:
            return showMeasurementsOnHome
        case .recentPhotos:
            return showLastPhotosOnHome
        case .healthSummary:
            return showHealthMetricsOnHome && premiumStore.isPremium
        case .setupChecklist:
            return showOnboardingChecklistOnHome && !activeChecklistItems.isEmpty
        }
    }

    @ViewBuilder
    private func homeModuleView(for item: HomeModuleLayoutItem) -> some View {
        switch item.kind {
        case .summaryHero:
            summaryHeroModule
        case .quickActions:
            quickActionsModule
        case .keyMetrics:
            keyMetricsModule
        case .recentPhotos:
            recentPhotosModule
        case .healthSummary:
            healthSummaryModule
        case .setupChecklist:
            checklistModule
        }
    }

    private var moduleAccentText: Color {
        Color.appAccent
    }

    private var summaryHeroModule: some View {
        HomeWidgetCard(
            tint: Color.appAccent.opacity(0.18),
            depth: .floating,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.summaryHero"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image("BrandButton")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    Text("MeasureMe")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer()

                    if showStreakOnHome && streakManager.currentStreak > 0 {
                        StreakBadge(
                            count: streakManager.currentStreak,
                            shouldAnimate: streakManager.shouldPlayAnimation,
                            onAnimationComplete: { streakManager.markAnimationPlayed() }
                        )
                    }
                }

                Text(greetingTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(goalStatusText)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(goalStatusColor)

                HStack(alignment: .top, spacing: 12) {
                    summaryHighlightCard(
                        label: AppLocalization.string("Next focus"),
                        value: summaryFocusTitle,
                        detail: summaryFocusDetail,
                        icon: "scope",
                        emphasized: true
                    )

                    summaryHighlightCard(
                        label: AppLocalization.string("This week"),
                        value: summaryThisWeekTitle,
                        detail: summaryThisWeekDetail,
                        icon: "calendar"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func summaryHighlightCard(
        label: String,
        value: String,
        detail: String,
        icon: String? = nil,
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(emphasized ? Color.appAccent : .white.opacity(0.62))
                }

                Text(label)
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(emphasized ? Color.appAccent : .white.opacity(0.62))
            }

            Text(value)
                .font(emphasized ? .system(size: 22, weight: .bold, design: .rounded) : AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(detail)
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(emphasized ? Color.appAccent.opacity(0.12) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(emphasized ? Color.appAccent.opacity(0.26) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var quickActionsModule: some View {
        HomeWidgetCard(
            tint: Color.cyan.opacity(0.14),
            depth: .base,
            contentPadding: 14,
            accessibilityIdentifier: "home.module.quickActions"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.string("Quick actions"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 10) {
                    HomeQuickActionButton(
                        title: AppLocalization.string("Quick Add"),
                        systemImage: "plus.circle.fill",
                        tint: Color.appAccent
                    ) {
                        Haptics.light()
                        showQuickAddSheet = true
                    }
                    .accessibilityIdentifier("home.quickadd.button")

                    HomeQuickActionButton(
                        title: AppLocalization.string("Add Photo"),
                        systemImage: "camera.fill",
                        tint: Color.cyan
                    ) {
                        Haptics.selection()
                        NotificationCenter.default.post(name: .homeOpenPhotoComposer, object: nil)
                        router.selectedTab = .photos
                    }

                    HomeQuickActionButton(
                        title: AppLocalization.string("Measurements"),
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: Color(hex: "#14B8A6")
                    ) {
                        Haptics.selection()
                        router.selectedTab = .measurements
                    }
                }
            }
        }
    }

    private var keyMetricsModule: some View {
        HomeWidgetCard(
            tint: Color.appAccent.opacity(0.16),
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.keyMetrics"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(AppLocalization.string("Key metrics"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("home.module.keyMetrics.title")
                    Spacer()
                    Button {
                        router.selectedTab = .measurements
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(moduleAccentText)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if !hasAnyMeasurements && cachedLatestByKind.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLocalization.string("No measurements yet."))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("Add your first measurement to unlock trends and goal progress."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.72))
                        Button {
                            showQuickAddSheet = true
                        } label: {
                            Text(AppLocalization.string("Add measurement"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
                    }
                } else if dashboardVisibleMetrics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("No key metrics selected"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("Choose tracked metrics in Settings to populate this board."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(dashboardVisibleMetrics, id: \.self) { kind in
                            NavigationLink {
                                MetricDetailView(kind: kind)
                            } label: {
                                HomeKeyMetricRow(
                                    kind: kind,
                                    latest: cachedLatestByKind[kind],
                                    goal: cachedGoalsByKind[kind],
                                    samples: samplesForKind(kind),
                                    unitsSystem: unitsSystem
                                )
                            }
                            .buttonStyle(PressableTileStyle())
                            .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
                            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
                        }
                    }
                }
            }
        }
    }

    private var recentPhotosModule: some View {
        Group {
            if isLastPhotosSectionMounted {
                if hasAnyPhotoContent {
                    recentPhotosContentModule
                } else {
                    recentPhotosEmptyModule
                }
            } else {
                lastPhotosPlaceholder
            }
        }
    }

    private var recentPhotosContentModule: some View {
        HomeWidgetCard(
            tint: Color.cyan.opacity(0.14),
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.recentPhotos"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppLocalization.string("Recent photos"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("home.module.recentPhotos.title")
                    Spacer()
                    Button {
                        router.selectedTab = .photos
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.cyan)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.string("accessibility.open.photos"))
                }

                Text(String(dashboardRecentPhotoTiles.count))
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.recentPhotos.tileCount")
                    .frame(width: 1, height: 1)
                    .clipped()

                GeometryReader { proxy in
                    let spacing: CGFloat = 8
                    let side = max(min((proxy.size.width - (spacing * 2)) / 3, 112), 0)
                    HStack(spacing: spacing) {
                        ForEach(Array(dashboardRecentPhotoTiles.enumerated()), id: \.element.id) { index, tile in
                            switch tile {
                            case .persisted(let photo):
                                Button {
                                    selectedPhotoForFullScreen = photo
                                } label: {
                                    PhotoGridThumb(
                                        photo: photo,
                                        size: side,
                                        cacheID: String(describing: photo.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("home.recentPhotos.item.\(index)")
                            case .pending(let pending):
                                PendingPhotoGridCell(
                                    thumbnailData: pending.thumbnailData,
                                    progress: pending.progress,
                                    status: pending.status,
                                    targetSize: CGSize(width: side, height: side),
                                    cornerRadius: 12,
                                    cacheID: pending.id.uuidString,
                                    showsStatusLabel: false,
                                    accessibilityIdentifier: "home.recentPhotos.item.\(index)"
                                )
                                .frame(width: side, height: side)
                            }
                        }

                        ForEach(0..<max(0, 3 - dashboardRecentPhotoTiles.count), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                                .frame(width: side, height: side)
                                .hidden()
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112)
            }
        }
    }

    private var recentPhotosEmptyModule: some View {
        HomeWidgetCard(
            tint: Color.cyan.opacity(0.14),
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.recentPhotos"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.string("Recent photos"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)
                Text(AppLocalization.string("No photos yet. Capture progress photos to see changes beyond the scale."))
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Button {
                    router.selectedTab = .photos
                } label: {
                    Text(AppLocalization.string("Open Photos"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
            }
        }
    }

    private var healthSummaryModule: some View {
        Group {
            if isHealthSectionMounted {
                HomeWidgetCard(
                    tint: Color.cyan.opacity(0.16),
                    depth: .base,
                    contentPadding: 12,
                    accessibilityIdentifier: "home.module.healthSummary"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLocalization.string("Health"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("home.module.healthSummary.title")
                        HealthMetricsSection(
                            latestWaist: latestWaist,
                            latestHeight: latestHeight,
                            latestWeight: latestWeight,
                            latestHips: cachedLatestByKind[.hips]?.value,
                            latestBodyFat: latestBodyFat,
                            latestLeanMass: latestLeanMass,
                            weightDelta7dText: weightDelta7dText,
                            waistDelta7dText: waistDelta7dText,
                            displayMode: .summaryOnly,
                            title: ""
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                healthSectionPlaceholder
            }
        }
    }

    private var checklistModule: some View {
        HomeWidgetCard(
            tint: Color.appAccent.opacity(0.14),
            depth: .base,
            contentPadding: 14,
            accessibilityIdentifier: "home.module.setupChecklist"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("Finish setup"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("Tasks left: %d", activeChecklistItems.count))
                            .font(AppTypography.micro)
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()

                    Menu {
                        Button(AppLocalization.string("Hide checklist")) {
                            Haptics.selection()
                            showOnboardingChecklistOnHome = false
                            settingsStore.setHomeModuleVisibility(false, for: .setupChecklist)
                        }
                        Button(onboardingChecklistCollapsed ? AppLocalization.string("Expand checklist") : AppLocalization.string("Collapse checklist")) {
                            Haptics.selection()
                            onboardingChecklistCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }

                if onboardingChecklistCollapsed {
                    Text(AppLocalization.string("Checklist collapsed. Open menu to expand."))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else if let nextItem = activeChecklistItems.first {
                    Button {
                        performChecklistAction(nextItem.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: nextItem.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(nextItem.title)
                                    .font(AppTypography.captionEmphasis)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(nextItem.detail)
                                    .font(AppTypography.micro)
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    private var goalStatusColor: Color {
        switch goalStatus {
        case .onTrack:
            return Color(hex: "#22C55E")
        case .slightlyOff:
            return Color.appAccent
        case .needsAttention:
            return Color(hex: "#EF4444")
        case .noGoals:
            return Color.white.opacity(0.82)
        }
    }

    private var summaryFocusTitle: String {
        if let firstVisibleMetric = visibleMetrics.first {
            return firstVisibleMetric.title
        }
        return AppLocalization.string("Build your first trend")
    }

    private var summaryFocusDetail: String {
        guard let firstVisibleMetric = visibleMetrics.first else {
            return AppLocalization.string("Add measurements to unlock the board.")
        }

        if let delta = metricDeltaTextFromCache(kind: firstVisibleMetric, days: 7) {
            return delta
        }

        if let latest = cachedLatestByKind[firstVisibleMetric] {
            let shown = firstVisibleMetric.valueForDisplay(fromMetric: latest.value, unitsSystem: unitsSystem)
            return String(format: "%.1f %@", shown, firstVisibleMetric.unitSymbol(unitsSystem: unitsSystem))
        }

        return AppLocalization.string("No recent data yet")
    }

    private var summaryThisWeekTitle: String {
        switch currentWeekCheckInDays {
        case ..<1:
            return AppLocalization.string("home.thisweek.empty")
        case 1:
            return AppLocalization.string("home.thisweek.single")
        default:
            return AppLocalization.string("home.thisweek.multiple", currentWeekCheckInDays)
        }
    }

    private var summaryThisWeekDetail: String {
        guard latestCheckInThisWeek != nil else {
            return AppLocalization.string("home.thisweek.detail.empty")
        }
        return AppLocalization.string("home.thisweek.detail.logged", latestCheckInWeekday)
    }

    private var greetingCard: some View {
        return AppGlassCard(
            depth: .floating,
            cornerRadius: 24,
            tint: Color.appAccent.opacity(0.26),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: hasAnyMeasurements ? 10 : 8) {
                HStack(spacing: 10) {
                    Image("BrandButton")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text("MeasureMe")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if showStreakOnHome && streakManager.currentStreak > 0 {
                        StreakBadge(
                            count: streakManager.currentStreak,
                            shouldAnimate: streakManager.shouldPlayAnimation,
                            onAnimationComplete: { streakManager.markAnimationPlayed() }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(greetingTitle)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                if hasAnyMeasurements {
                    Text(encouragementText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                if goalStatus != .noGoals {
                    Text(goalStatusText)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checklistItems: [SetupChecklistItem] {
        var items: [SetupChecklistItem] = [
            SetupChecklistItem(
                id: "first_measurement",
                title: AppLocalization.string("First measurement"),
                detail: AppLocalization.string("Start your trend with one quick check-in."),
                icon: "ruler.fill",
                isCompleted: hasAnyMeasurements,
                isLoading: false
            ),
            SetupChecklistItem(
                id: "first_photo",
                title: AppLocalization.string("First Photo"),
                detail: AppLocalization.string("Photos make progress easier to notice."),
                icon: "camera.fill",
                isCompleted: hasAnyPhotoContent,
                isLoading: false
            )
        ]

        items.append(
            SetupChecklistItem(
                id: "healthkit",
                title: AppLocalization.string("Apple Health"),
                detail: AppLocalization.string("Import history and keep data in sync."),
                icon: "heart.text.square",
                isCompleted: isSyncEnabled,
                isLoading: isChecklistConnectingHealth
            )
        )

        items.append(
            SetupChecklistItem(
                id: "choose_metrics",
                title: AppLocalization.string("Choose metrics"),
                detail: AppLocalization.string("Track only what matters to you."),
                icon: "slider.horizontal.3",
                isCompleted: onboardingChecklistMetricsCompleted,
                isLoading: false
            )
        )

        if onboardingSkippedReminders {
            items.append(
                SetupChecklistItem(
                    id: "reminders",
                    title: AppLocalization.string("Set reminders"),
                    detail: AppLocalization.string("One weekly nudge helps keep the habit."),
                    icon: "bell.badge",
                    isCompleted: reminderChecklistCompleted,
                    isLoading: false
                )
            )
        }

        items.append(
            SetupChecklistItem(
                id: "premium",
                title: AppLocalization.string("Explore Premium"),
                detail: AppLocalization.string("Try deeper insights and compare photos side-by-side."),
                icon: "sparkles",
                isCompleted: onboardingChecklistPremiumExplored || premiumStore.isPremium,
                isLoading: false
            )
        )

        return items
    }

    private var activeChecklistItems: [SetupChecklistItem] {
        checklistItems.filter { !$0.isCompleted }
    }

    private var allChecklistItemsCompleted: Bool {
        !checklistItems.isEmpty && checklistItems.allSatisfy(\.isCompleted)
    }

    private var primaryChecklistIDs: [String] {
        ["first_measurement", "first_photo", "healthkit"]
    }

    private var primaryChecklistItems: [SetupChecklistItem] {
        activeChecklistItems.filter { primaryChecklistIDs.contains($0.id) }
    }

    private var secondaryChecklistItems: [SetupChecklistItem] {
        activeChecklistItems.filter { !primaryChecklistIDs.contains($0.id) }
    }

    private var shownChecklistItems: [SetupChecklistItem] {
        if showMoreChecklistItems || primaryChecklistItems.isEmpty {
            return primaryChecklistItems + secondaryChecklistItems
        }
        return primaryChecklistItems
    }

    private var setupChecklistSection: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: 24,
            tint: Color.appAccent.opacity(0.16),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalization.string("Finish setup"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Menu {
                        Button(AppLocalization.string("Hide checklist")) {
                            Haptics.selection()
                            showOnboardingChecklistOnHome = false
                        }
                        Button(onboardingChecklistCollapsed ? AppLocalization.string("Expand checklist") : AppLocalization.string("Collapse checklist")) {
                            Haptics.selection()
                            onboardingChecklistCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AppLocalization.string("accessibility.setup.checklist.options"))
                    .accessibilityHint(AppLocalization.string("accessibility.setup.checklist.options.hint"))
                }

                if onboardingChecklistCollapsed {
                    Text(AppLocalization.string("Checklist collapsed. Open menu to expand."))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    ForEach(shownChecklistItems) { item in
                        Button {
                            performChecklistAction(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(item.isCompleted ? Color(hex: "#22C55E") : Color.appAccent)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(.white)
                                    Text(item.detail)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 10)

                                if item.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.appAccent)
                                } else if item.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#22C55E"))
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(item.isLoading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.title). \(item.detail)")
                        .accessibilityValue(
                            item.isLoading
                            ? AppLocalization.string("accessibility.setup.checklist.loading")
                            : (item.isCompleted
                               ? AppLocalization.string("accessibility.setup.checklist.completed")
                               : AppLocalization.string("accessibility.setup.checklist.incomplete"))
                        )
                    }

                    if !showMoreChecklistItems, !secondaryChecklistItems.isEmpty, !primaryChecklistItems.isEmpty {
                        Button {
                            Haptics.selection()
                            showMoreChecklistItems = true
                        } label: {
                            Text(AppLocalization.string("Show %d more", secondaryChecklistItems.count))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(Color.appAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let checklistStatusText {
                    Text(checklistStatusText)
                        .font(AppTypography.micro)
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
    }

    private var trimmedUserName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum DayPart {
        case morning
        case afternoon
        case evening
    }

    private var dayPart: DayPart {
        let hour = Calendar.current.component(.hour, from: AppClock.now)
        if hour < 12 { return .morning }
        if hour < 18 { return .afternoon }
        return .evening
    }

    private var greetingTitle: String {
        let name = trimmedUserName
        switch dayPart {
        case .morning:
            return name.isEmpty
                ? AppLocalization.string("home.greeting.morning")
                : AppLocalization.string("home.greeting.morning.named", name)
        case .afternoon:
            return name.isEmpty
                ? AppLocalization.string("home.greeting.afternoon")
                : AppLocalization.string("home.greeting.afternoon.named", name)
        case .evening:
            return name.isEmpty
                ? AppLocalization.string("home.greeting.evening")
                : AppLocalization.string("home.greeting.evening.named", name)
        }
    }

    private var encouragementText: String {
        AppLocalization.string("home.encouragement")
    }

    private var currentWeekCheckInDays: Int {
        let calendar = Calendar.current
        let days = recentSamples
            .filter { calendar.isDate($0.date, equalTo: AppClock.now, toGranularity: .weekOfYear) }
            .map { calendar.startOfDay(for: $0.date) }
        return Set(days).count
    }

    private var latestCheckInThisWeek: MetricSample? {
        let calendar = Calendar.current
        return recentSamples.first { calendar.isDate($0.date, equalTo: AppClock.now, toGranularity: .weekOfYear) }
    }

    private var latestCheckInWeekday: String {
        guard let latestCheckInThisWeek else { return "" }
        return latestCheckInThisWeek.date.formatted(.dateTime.weekday(.wide))
    }

    private enum GoalStatusLevel {
        case onTrack
        case slightlyOff
        case needsAttention
        case noGoals
    }

    private var goalStatus: GoalStatusLevel {
        let statuses: [GoalStatusLevel] = visibleMetrics.compactMap { kind in
            guard let goal = cachedGoalsByKind[kind], let latest = cachedLatestByKind[kind] else { return nil }
            if goal.isAchieved(currentValue: latest.value) { return .onTrack }
            let remaining = abs(goal.remainingToGoal(currentValue: latest.value))
            let target = max(abs(goal.targetValue), 0.0001)
            let ratio = remaining / target
            return ratio <= 0.10 ? .slightlyOff : .needsAttention
        }

        if statuses.isEmpty { return .noGoals }
        if statuses.contains(.needsAttention) { return .needsAttention }
        if statuses.contains(.slightlyOff) { return .slightlyOff }
        return .onTrack
    }

    private var goalStatusText: String {
        switch goalStatus {
        case .onTrack: return AppLocalization.string("home.goalstatus.ontrack")
        case .slightlyOff: return AppLocalization.string("home.goalstatus.slightlyoff")
        case .needsAttention: return AppLocalization.string("home.goalstatus.needsattention")
        case .noGoals: return AppLocalization.string("home.goalstatus.nogoals")
        }
    }

    private func homeMetricAccessibilityLabel(kind: MetricKind) -> String {
        if let latest = cachedLatestByKind[kind] {
            let shown = kind.valueForDisplay(fromMetric: latest.value, unitsSystem: unitsSystem)
            let unit = kind.unitSymbol(unitsSystem: unitsSystem)
            let valueText = String(format: "%.1f %@", shown, unit)
            return AppLocalization.string("home.metric.accessibility.value", kind.title, valueText)
        }
        return AppLocalization.string("home.metric.accessibility.nodata", kind.title)
    }

    private func refreshChecklistState() {
        reminderChecklistCompleted = effects.reminderChecklistCompleted()
        autoHideChecklistIfCompleted()
    }

    private func autoHideChecklistIfCompleted() {
        guard HomeChecklistLogic.shouldAutoHideChecklist(
            allChecklistItemsCompleted: allChecklistItemsCompleted,
            showOnboardingChecklistOnHome: showOnboardingChecklistOnHome
        ) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(AppMotion.animation(AppMotion.sectionExit, enabled: shouldAnimate)) {
                showOnboardingChecklistOnHome = false
            }
        }
    }

    private func performChecklistAction(_ id: String) {
        switch id {
        case "first_measurement":
            Haptics.selection()
            showQuickAddSheet = true
        case "first_photo":
            Haptics.selection()
            router.selectedTab = .photos
        case "choose_metrics":
            Haptics.selection()
            onboardingChecklistMetricsCompleted = true
            settingsOpenTrackedMeasurements = true
            router.selectedTab = .settings
        case "reminders":
            Haptics.selection()
            settingsOpenReminders = true
            router.selectedTab = .settings
        case "healthkit":
            connectHealthKitFromChecklist()
        case "premium":
            Haptics.light()
            onboardingChecklistPremiumExplored = true
            premiumStore.presentPaywall(reason: .onboarding)
        default:
            break
        }
    }

    private func connectHealthKitFromChecklist() {
        guard !isSyncEnabled, !isChecklistConnectingHealth else { return }

        checklistStatusText = AppLocalization.string("Requesting Health access...")
        isChecklistConnectingHealth = true

        Task { @MainActor in
            defer { isChecklistConnectingHealth = false }
            do {
                try await effects.requestHealthKitAuthorization()
                isSyncEnabled = true
                onboardingSkippedHealthKit = true
                checklistStatusText = AppLocalization.string("Connected to Apple Health.")
                Haptics.success()
                refreshChecklistState()
            } catch {
                isSyncEnabled = false
                checklistStatusText = AppLocalization.string("Health access denied. You can enable it later in Settings.")
                if let authError = error as? HealthKitAuthorizationError {
                    checklistStatusText = authError.errorDescription ?? checklistStatusText
                }
                Haptics.error()
            }
        }
    }
    
    // MARK: - Measurements Section
    
    private var measurementsSection: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.appAccent.opacity(0.18),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("Measurements"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)

                if !hasAnyMeasurements && cachedLatestByKind.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalization.string("No measurements yet."))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)

                        Text(AppLocalization.string("Add your first measurement to unlock trends and goal progress."))
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.7))

                        Button {
                            showQuickAddSheet = true
                        } label: {
                            Text(AppLocalization.string("Add measurement"))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                        .accessibilityIdentifier("home.quickadd.button")
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if visibleMetrics.isEmpty {
                    Text(AppLocalization.string("Select up to three key metrics in Settings."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    VStack(spacing: 12) {
                        ForEach(visibleMetrics, id: \.self) { kind in
                            NavigationLink {
                                MetricDetailView(kind: kind)
                            } label: {
                                HomeKeyMetricRow(
                                    kind: kind,
                                    latest: cachedLatestByKind[kind],
                                    goal: cachedGoalsByKind[kind],
                                    samples: samplesForKind(kind),
                                    unitsSystem: unitsSystem
                                )
                            }
                            .buttonStyle(PressableTileStyle())
                            .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
                            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
                        }
                    }
                }

                Button {
                    router.selectedTab = .measurements
                } label: {
                    HStack(spacing: 6) {
                        Text(AppLocalization.string("View more"))
                            .font(AppTypography.sectionAction)
                        Image(systemName: "chevron.right")
                            .font(AppTypography.micro)
                    }
                    .foregroundStyle(Color(hex: "#FCA311"))
                }
                .buttonStyle(LiquidCapsuleButtonStyle(tint: Color.appAccent.opacity(0.88)))
                .accessibilityLabel(AppLocalization.string("accessibility.open.measurements"))
                .accessibilityHint(AppLocalization.string("accessibility.opens.measurements"))
            }
        }
    }
    
    // MARK: - Last Photos Section

    private var lastPhotosPlaceholder: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.cyan.opacity(0.14),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("Last Photos"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 160)
            }
            .redacted(reason: .placeholder)
        }
    }

    private var healthSectionPlaceholder: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: 24,
            tint: Color.cyan.opacity(0.16),
            contentPadding: 12
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("Health"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 92)
            }
            .redacted(reason: .placeholder)
        }
    }
    
    private var lastPhotosSection: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.cyan.opacity(0.14),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Nagłówek sekcji
                HStack {
                    Text(AppLocalization.string("Last Photos"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    if (allPhotos.count + pendingPhotoSaveStore.pendingItems.count) > maxVisiblePhotos {
                        Button {
                            router.selectedTab = .photos
                        } label: {
                            HStack(spacing: 4) {
                                Text(AppLocalization.string("View All"))
                                    .font(AppTypography.sectionAction)
                                Image(systemName: "chevron.right")
                                    .font(AppTypography.micro)
                            }
                            .foregroundStyle(Color(hex: "#FCA311"))
                        }
                        .buttonStyle(LiquidCapsuleButtonStyle(tint: Color.cyan.opacity(0.72)))
                        .accessibilityLabel(AppLocalization.string("accessibility.open.photos"))
                        .accessibilityHint(AppLocalization.string("accessibility.opens.photos"))
                    }
                }
                
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(lastPhotosGridSide), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(visiblePhotoTiles) { tile in
                        switch tile {
                        case .persisted(let photo):
                            Button {
                                selectedPhotoForFullScreen = photo
                            } label: {
                                PhotoGridThumb(
                                    photo: photo,
                                    size: lastPhotosGridSide,
                                    cacheID: String(describing: photo.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalization.string("accessibility.open.photo.details"))
                            .accessibilityValue(photo.date.formatted(date: .abbreviated, time: .omitted))
                        case .pending(let pending):
                            PendingPhotoGridCell(
                                thumbnailData: pending.thumbnailData,
                                progress: pending.progress,
                                status: pending.status,
                                targetSize: CGSize(width: lastPhotosGridSide, height: lastPhotosGridSide),
                                cornerRadius: 12,
                                cacheID: pending.id.uuidString,
                                showsStatusLabel: false,
                                accessibilityIdentifier: "home.lastPhotos.pending.item"
                            )
                            .frame(width: lastPhotosGridSide, height: lastPhotosGridSide)
                        }
                    }
                }
                .frame(height: {
                    let rows = max(1, Int(ceil(Double(visiblePhotoTiles.count) / 3.0)))
                    let spacing: CGFloat = 8
                    return CGFloat(rows) * lastPhotosGridSide + CGFloat(max(rows - 1, 0)) * spacing
                }())
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                let width = geo.size.width
                                if width.isFinite, width > 0 {
                                    lastPhotosGridWidth = width
                                }
                            }
                            .onChange(of: geo.size.width) { _, newValue in
                                if newValue.isFinite, newValue > 0 {
                                    lastPhotosGridWidth = newValue
                                }
                            }
                    }
                )
            }
        }
    }

    private var lastPhotosEmptyState: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.cyan.opacity(0.14),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("Last Photos"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)

                Text(AppLocalization.string("No photos yet. Capture progress photos to see changes beyond the scale."))
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    router.selectedTab = .photos
                } label: {
                    Text(AppLocalization.string("Add photo"))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
            }
        }
    }
}
