import SwiftUI
import SwiftData
import UIKit

private extension Notification.Name {
    static let homeScrollToChecklist = Notification.Name("homeScrollToChecklist")
    static let settingsOpenHomeSettingsRequested = Notification.Name("settingsOpenHomeSettingsRequested")
}

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
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.profile.userAge) private var userAgeValue: Int = 0
    @AppSetting(\.profile.userGender) private var userGenderRaw: String = "notSpecified"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
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
    @AppSetting(\.home.settingsOpenHomeSettings) private var settingsOpenHomeSettings: Bool = false
    @AppSetting(\.home.homePhotoMetricSyncLastDate) private var photoMetricSyncLastDate: Double = 0
    @AppSetting(\.home.homePhotoMetricSyncLastID) private var photoMetricSyncLastID: String = ""
    
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var streakManager: StreakManager

    @Query private var recentSamples: [MetricSample]
    
    @Query private var goals: [MetricGoal]
    
    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)])
    private var allPhotos: [PhotoEntry]
    
    @State private var showQuickAddSheet = false
    @State private var showHomeSettingsSheet = false
    @State private var showHomeCompareChooser = false
    @State private var showStreakDetail = false
    @State private var selectedPhotoForFullScreen: PhotoEntry?
    @State private var selectedHomeComparePair: HomeComparePair?
    @State private var scrollOffset: CGFloat = 0
    @State private var lastPhotosGridWidth: CGFloat = 0
    @State private var checklistStatusText: String?
    @State private var isChecklistConnectingHealth: Bool = false
    @State private var shouldShowHealthSettingsShortcut: Bool = false
    @State private var shouldPromptToOpenHealthSettings: Bool = false
    @State private var reminderChecklistCompleted: Bool = false
    @State private var showMoreChecklistItems: Bool = false
    @State private var expandedSecondaryMetrics: Set<MetricKind> = []
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
    private let isUITestMode = ProcessInfo.processInfo.arguments.contains("-uiTestMode")
    let effects: HomeEffects
    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var prefersStackedHeroPanels: Bool {
        dynamicTypeSize >= .xLarge || dynamicTypeSize.isAccessibilitySize
    }

    private var isFreshHomeState: Bool {
        !hasAnyMeasurements && !hasAnyPhotoContent && homeHealthStatItems.isEmpty
    }

    private var userAge: Int? {
        userAgeValue > 0 ? userAgeValue : nil
    }

    private var userGender: Gender {
        Gender(rawValue: userGenderRaw) ?? .notSpecified
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

    private struct HomeComparePair: Identifiable {
        let olderPhoto: PhotoEntry
        let newerPhoto: PhotoEntry

        var id: String {
            "\(olderPhoto.persistentModelID)-\(newerPhoto.persistentModelID)"
        }
    }

    private struct HomeHealthStatItem: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let badge: String?

        init(label: String, value: String, badge: String? = nil) {
            self.label = label
            self.value = value
            self.badge = badge
        }
    }

    private struct HomeNextFocusInsight {
        enum Action {
            case metric(MetricKind)
            case measurements
        }

        let headline: String?
        let primaryValue: String?
        let supportingLabel: String?
        let summary: String
        let cta: String
        let action: Action
        let accessibilityValue: String
    }

    private struct HomeNextFocusCandidate {
        let insight: HomeNextFocusInsight
        let score: Double
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
        Array(visibleMetrics.prefix(3))
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

    private var homeCompareCandidates: [PhotoEntry] {
        allPhotos
    }

    private var hasEnoughSavedPhotosForCompare: Bool {
        homeCompareCandidates.count >= 2
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

    private var latestShoulders: Double? {
        cachedLatestByKind[.shoulders]?.value
    }

    private var latestChest: Double? {
        cachedLatestByKind[.chest]?.value
    }

    private var latestBust: Double? {
        cachedLatestByKind[.bust]?.value
    }

    private var latestHips: Double? {
        cachedLatestByKind[.hips]?.value
    }

    private var weightDelta7dText: String? {
        metricDeltaTextFromCache(kind: .weight, days: 7)
    }

    private var waistDelta7dText: String? {
        metricDeltaTextFromCache(kind: .waist, days: 7)
    }

    private var homeMetricsSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.metricsInput(
            userName: userName,
            activeKinds: metricsStore.activeKinds,
            latestByKind: cachedLatestByKind,
            samplesByKind: cachedSamplesByKind,
            unitsSystem: unitsSystem
        )
    }

    private var homeHealthSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.healthInput(
            userName: userName,
            userGender: userGender,
            latestWaist: latestWaist,
            latestHeight: manualHeight > 0 ? manualHeight : latestHeight,
            latestWeight: latestWeight,
            latestHips: latestHips,
            latestBodyFat: latestBodyFat,
            latestLeanMass: latestLeanMass,
            unitsSystem: unitsSystem
        )
    }

    private var homePhysiqueSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.physiqueInput(
            userName: userName,
            userGender: userGender,
            latestWaist: latestWaist,
            latestHeight: manualHeight > 0 ? manualHeight : latestHeight,
            latestBodyFat: latestBodyFat,
            latestShoulders: latestShoulders,
            latestChest: latestChest,
            latestBust: latestBust,
            latestHips: latestHips
        )
    }

    private var homeBottomSummaryInput: SectionInsightInput? {
        AISectionSummaryInputBuilder.homeCombinedInput(
            userName: userName,
            metricsInput: homeMetricsSummaryInput,
            healthInput: homeHealthSummaryInput,
            physiqueInput: homePhysiqueSummaryInput
        )
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
        ScrollViewReader { scrollProxy in
            homeRoot(scrollProxy: scrollProxy)
        }
    }

    @ViewBuilder
    private func homeRoot(scrollProxy: ScrollViewProxy) -> some View {
        let presented = sheetPresentedHomeRoot(baseHomeRoot)
        let lifecycleObserved = lifecycleObservedHomeRoot(presented, scrollProxy: scrollProxy)
        refreshingHomeRoot(lifecycleObserved)
    }

    private var dashboardBoard: some View {
        HomeDashboardBoard(
            items: renderedDashboardItems,
            columns: dashboardColumns
        ) { item in
            homeModuleView(for: item)
                .id(item.kind.rawValue)
        }
    }

    private var quickAddSheet: some View {
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

    private var homeUITestHooks: some View {
        VStack(spacing: 0) {
            if shouldRenderModule(.setupChecklist) {
                Text("1")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.module.setupChecklist.visible")
                    .frame(width: 1, height: 1)
                    .clipped()

                Text("\(shownChecklistItems.count)")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.checklist.visibleCount")
                    .frame(width: 1, height: 1)
                    .clipped()

                Text(shownChecklistItems.map(\.id).joined(separator: ","))
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.checklist.visibleIDs")
                    .frame(width: 1, height: 1)
                    .clipped()

                Text("\(max(activeChecklistItems.count - collapsedChecklistItems.count, 0))")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.checklist.remainingCount")
                    .frame(width: 1, height: 1)
                    .clipped()

                if activeChecklistItems.count > collapsedChecklistItems.count {
                    Button("expand") {
                        showMoreChecklistItems = true
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .opacity(0.01)
                    .accessibilityIdentifier("home.checklist.showMore.hook")
                }
            }

            if showHomeSettingsSheet {
                Text("1")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.settings.sheet.present")
                    .frame(width: 1, height: 1)
                    .clipped()
            }

            Text(nextFocusInsight.accessibilityValue)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.nextFocus.mode")
                .frame(width: 1, height: 1)
                .clipped()

            Text(nextFocusInsight.cta)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.nextFocus.cta")
                .frame(width: 1, height: 1)
                .clipped()

            ForEach(Array(expandedSecondaryMetrics), id: \.self) { kind in
                Color.clear
                    .accessibilityElement()
                    .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).expanded")
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }

            ForEach(Array(expandedSecondaryMetrics), id: \.self) { kind in
                Button("collapse") {
                    withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                        _ = expandedSecondaryMetrics.remove(kind)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .opacity(0.01)
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).collapseHook")
            }

            Text("\(expandedSecondaryMetrics.count)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.keyMetrics.secondary.expandedCount")
                .frame(width: 1, height: 1)
                .clipped()

            Text(expandedSecondaryMetrics.map(\.rawValue).sorted().joined(separator: ","))
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.keyMetrics.secondary.expandedIDs")
                .frame(width: 1, height: 1)
                .clipped()
        }
    }

    private var baseHomeRoot: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(
                topHeight: 380,
                scrollOffset: scrollOffset,
                tint: Color.cyan.opacity(0.22)
            )

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

                    dashboardBoard

                    AISectionSummaryCard(
                        input: homeBottomSummaryInput,
                        missingDataMessage: AppLocalization.string("AI summary needs data from Metrics, Health Indicators, or Physique Indicators."),
                        tint: homeTheme.softTint,
                        accessibilityIdentifier: "home.bottom.ai.summary"
                    )
                    .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { value in
                scrollOffset = value
                let normalizedOffset = Double(value)
                // Defer AppSetting write to avoid publishing during the view-update pass.
                if abs(homeTabScrollOffset - normalizedOffset) > 0.5 {
                    Task { @MainActor in
                        homeTabScrollOffset = normalizedOffset
                    }
                }
            }

            if isUITestMode {
                homeUITestHooks
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrollOffset < -16 ? .visible : .hidden, for: .navigationBar)
        .animation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate), value: isLastPhotosSectionMounted)
        .animation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate), value: isHealthSectionMounted)
        .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate), value: showMoreChecklistItems)
        .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate), value: onboardingChecklistCollapsed)
    }

    private func sheetPresentedHomeRoot<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showQuickAddSheet) {
                quickAddSheet
            }
            .sheet(isPresented: $showHomeSettingsSheet) {
                NavigationStack {
                    HomeSettingsDetailView()
                }
            }
            .sheet(item: $selectedPhotoForFullScreen) { photo in
                PhotoDetailView(photo: photo)
            }
            .sheet(isPresented: $showHomeCompareChooser) {
                HomeCompareChooserSheet(photos: homeCompareCandidates) { olderPhoto, newerPhoto in
                    selectedHomeComparePair = HomeComparePair(olderPhoto: olderPhoto, newerPhoto: newerPhoto)
                }
                .presentationBackground(Color.black)
            }
            .sheet(item: $selectedHomeComparePair) { pair in
                ComparePhotosView(olderPhoto: pair.olderPhoto, newerPhoto: pair.newerPhoto)
            }
            .sheet(isPresented: $showStreakDetail) {
                StreakDetailView(streakManager: streakManager)
            }
            .alert(
                AppLocalization.string("Open iOS Settings now?"),
                isPresented: $shouldPromptToOpenHealthSettings
            ) {
                Button(AppLocalization.string("Open iOS Settings")) {
                    openAppSettings()
                }
                Button(AppLocalization.string("Not now"), role: .cancel) {}
            } message: {
                Text(AppLocalization.string("To enable Apple Health sync, go to iOS Settings → MeasureMe → Health."))
            }
    }

    private func lifecycleObservedHomeRoot<Content: View>(
        _ content: Content,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        content
            .onAppear {
                Task { @MainActor in
                    if autoCheckPaywallPrompt && !didCheckSevenDayPaywallPrompt {
                        didCheckSevenDayPaywallPrompt = true
                        premiumStore.checkSevenDayPromptIfNeeded()
                    }
                    if ProcessInfo.processInfo.arguments.contains("-uiTestExpandChecklist") {
                        showMoreChecklistItems = true
                    }
                    emitHomeInitialRenderIfNeeded()
                    runStartupPhasesIfNeeded()
                }
            }
            .onDisappear {
                expandedSecondaryMetrics.removeAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeScrollToChecklist)) { _ in
                withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                    scrollProxy.scrollTo(HomeModuleKind.setupChecklist.rawValue, anchor: .top)
                }
            }
    }

    private func refreshingHomeRoot<Content: View>(_ content: Content) -> some View {
        let observedContent = content
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
            .onChange(of: activeChecklistItems.count) { _, newCount in
                if newCount <= collapsedChecklistItems.count {
                    showMoreChecklistItems = false
                }
            }

        return Group {
            if showStreakDetail {
                observedContent
            } else {
                observedContent
                    .refreshable {
                        syncMeasurementsFromPhotosIfNeeded(force: true)
                        refreshMeasurementCaches()
                        rebuildGoalsCache()
                        fetchHealthKitData()
                        refreshChecklistState()
                    }
            }
        }
    }

    private func shouldRenderModule(_ kind: HomeModuleKind) -> Bool {
        switch kind {
        case .summaryHero:
            return true
        case .quickActions:
            return false
        case .keyMetrics:
            return showMeasurementsOnHome
        case .recentPhotos:
            return showLastPhotosOnHome
        case .healthSummary:
            return showHealthMetricsOnHome
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
        FeatureTheme.home.accent
    }

    private var homeTheme: FeatureTheme {
        .home
    }

    private var photosTheme: FeatureTheme {
        .photos
    }

    private var premiumTheme: FeatureTheme {
        .premium
    }

    private var healthTheme: FeatureTheme {
        .health
    }

    private var measurementsTheme: FeatureTheme {
        .measurements
    }

    private var summaryHeroModule: some View {
        HomeWidgetCard(
            tint: homeTheme.strongTint,
            depth: .floating,
            contentPadding: 18,
            accessibilityIdentifier: "home.module.summaryHero"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image("BrandButton")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    Text("MeasureMe")
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    Spacer()

                    if showStreakOnHome && streakManager.currentStreak > 0 {
                        Button { showStreakDetail = true } label: {
                            StreakBadge(
                                count: streakManager.currentStreak,
                                shouldAnimate: streakManager.shouldPlayAnimation,
                                onAnimationComplete: { streakManager.markAnimationPlayed() }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(greetingTitle)
                        .font(AppTypography.displayHero)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(prefersStackedHeroPanels ? 3 : 2)
                        .minimumScaleFactor(0.82)

                    heroGoalStatusRow
                }

                if isFreshHomeState {
                    freshHomePromptCard
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                Group {
                    if prefersStackedHeroPanels {
                        VStack(spacing: 10) {
                            nextFocusSummaryCard
                            thisWeekSummaryCard
                        }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            nextFocusSummaryCard
                            thisWeekSummaryCard
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var heroGoalStatusRow: some View {
        Group {
            if goalStatus == .noGoals {
                Button {
                    Haptics.selection()
                    router.selectedTab = .measurements
                } label: {
                    heroGoalStatusContent
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.goalStatus.button")
            } else {
                heroGoalStatusContent
            }
        }
    }

    private var heroGoalStatusContent: some View {
        HStack(spacing: 8) {
            Image(systemName: differentiateWithoutColor ? "flag.fill" : "circle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(goalStatusColor)

            Text(goalStatusText)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var nextFocusSummaryCard: some View {
        Button {
            handleNextFocusAction()
        } label: {
            VStack(alignment: .leading, spacing: heroSummaryCardVerticalSpacing) {
                HStack(alignment: .center, spacing: 8) {
                heroMiniLabel(
                    title: AppLocalization.string("home.nextfocus.label"),
                    icon: "chart.line.uptrend.xyaxis",
                    accent: homeTheme.accent
                )
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(homeTheme.accent.opacity(0.84))
                }

                if let primaryValue = nextFocusInsight.primaryValue {
                    VStack(alignment: .leading, spacing: heroSummaryCardContentSpacing) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(primaryValue)
                                .font(heroSummaryCardPrimaryFont)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("home.nextFocus.primaryValue")

                            if let supportingLabel = nextFocusInsight.supportingLabel {
                                Text(supportingLabel)
                                    .font(heroSummaryCardBadgeFont)
                                    .foregroundStyle(homeTheme.accent)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .padding(.horizontal, heroSummaryCardBadgeHorizontalPadding)
                                    .padding(.vertical, heroSummaryCardBadgeVerticalPadding)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(homeTheme.pillFill)
                                            .overlay(
                                                Capsule(style: .continuous)
                                                    .stroke(homeTheme.pillStroke, lineWidth: 1)
                                            )
                                    )
                                    .accessibilityIdentifier("home.nextFocus.supportingLabel")
                            }
                        }

                        Text(nextFocusInsight.summary)
                            .font(heroSummaryCardCaptionFont)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineLimit(heroSummaryCardSummaryLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("home.nextFocus.summary")
                    }
                } else {
                    VStack(alignment: .leading, spacing: heroSummaryCardContentSpacing) {
                        if let headline = nextFocusInsight.headline {
                            Text(headline)
                                .font(AppTypography.bodyStrong)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("home.nextFocus.headline")
                        }

                        Text(nextFocusInsight.summary)
                            .font(heroSummaryCardCaptionFont)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineLimit(heroSummaryCardSummaryLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("home.nextFocus.summary")
                    }
                }
            }
            .padding(heroSummaryCardPadding)
            .frame(maxWidth: .infinity, minHeight: heroSummaryCardMinHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(homeTheme.pillFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(homeTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.nextFocus.button")
    }

    private var thisWeekSummaryCard: some View {
        VStack(alignment: .leading, spacing: heroSummaryCardVerticalSpacing) {
            heroMiniLabel(
                title: AppLocalization.string("This week"),
                icon: "calendar",
                accent: AppColorRoles.textSecondary
            )

            Text(summaryThisWeekTitle)
                .font(AppTypography.displayStatement)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(summaryThisWeekDetail)
                .font(heroSummaryCardCaptionFont)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(3)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(heroSummaryCardPadding)
        .frame(maxWidth: .infinity, minHeight: heroSummaryCardMinHeight, alignment: .topLeading)
        .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
    }

    private var heroSummaryCardPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 6 : 10
    }

    private var heroSummaryCardVerticalSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 4 : 8
    }

    private var heroSummaryCardContentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 2 : 5
    }

    private var heroSummaryCardCaptionFont: Font {
        dynamicTypeSize.isAccessibilitySize ? AppTypography.caption : AppTypography.captionEmphasis
    }

    private var heroSummaryCardPrimaryFont: Font {
        let size = dynamicTypeSize.isAccessibilitySize ? 19.0 : (prefersStackedHeroPanels ? 22.0 : 24.0)
        return .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    private var heroSummaryCardBadgeFont: Font {
        dynamicTypeSize.isAccessibilitySize ? AppTypography.microEmphasis : AppTypography.badge
    }

    private var heroSummaryCardBadgeHorizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 4 : 6
    }

    private var heroSummaryCardBadgeVerticalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 2 : 3
    }

    private var heroSummaryCardSummaryLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    private var heroSummaryCardMinHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 96
        }
        return prefersStackedHeroPanels ? 120 : 124
    }

    private var freshHomePromptCard: some View {
        Button {
            handleNextFocusAction()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("home.hero.fresh.title"))
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string("home.hero.fresh.detail"))
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Text(AppLocalization.string("home.hero.fresh.cta"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(homeTheme.accent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func heroMiniLabel(title: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(dynamicTypeSize.isAccessibilitySize ? AppTypography.microEmphasis : AppTypography.iconSmall)
            Text(title)
                .font(dynamicTypeSize.isAccessibilitySize ? AppTypography.microEmphasis : AppTypography.eyebrow)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(accent)
    }

    private var quickActionsModule: some View {
        EmptyView()
    }

    private var keyMetricsModule: some View {
        HomeWidgetCard(
            tint: measurementsTheme.softTint,
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.keyMetrics"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                moduleHeader(
                    eyebrow: AppLocalization.string("home.module.metrics.eyebrow"),
                    title: AppLocalization.string("Key metrics"),
                    subtitle: keyMetricsSubtitle,
                    accent: moduleAccentText,
                    accessibilityIdentifier: "home.module.keyMetrics.title",
                    action: { router.selectedTab = .measurements },
                    actionAccessibilityLabel: AppLocalization.string("accessibility.open.measurements")
                )

                if !hasAnyMeasurements && cachedLatestByKind.isEmpty {
                    editorialEmptyStateCard(
                        eyebrow: AppLocalization.string("home.empty.eyebrow"),
                        title: AppLocalization.string("home.keymetrics.empty.title"),
                        detail: AppLocalization.string("home.keymetrics.empty.detail"),
                        accent: measurementsTheme.accent,
                        ctaTitle: AppLocalization.string("Add measurement")
                    ) {
                        showQuickAddSheet = true
                    }
                } else if dashboardVisibleMetrics.isEmpty {
                    editorialEmptyStateCard(
                        eyebrow: AppLocalization.string("home.empty.eyebrow"),
                        title: AppLocalization.string("home.keymetrics.empty.selection.title"),
                        detail: AppLocalization.string("home.keymetrics.empty.selection.detail"),
                        accent: measurementsTheme.accent,
                        ctaTitle: AppLocalization.string("Open Measurements")
                    ) {
                        router.selectedTab = .measurements
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        if let leadMetric = dashboardVisibleMetrics.first {
                            NavigationLink {
                                MetricDetailView(kind: leadMetric)
                            } label: {
                                HomeKeyMetricRow(
                                    kind: leadMetric,
                                    latest: cachedLatestByKind[leadMetric],
                                    goal: cachedGoalsByKind[leadMetric],
                                    samples: samplesForKind(leadMetric),
                                    unitsSystem: unitsSystem
                                )
                            }
                            .buttonStyle(PressableTileStyle())
                            .accessibilityLabel(homeMetricAccessibilityLabel(kind: leadMetric))
                            .accessibilityHint(AppLocalization.string("accessibility.opens.details", leadMetric.title))
                        }

                        ForEach(Array(dashboardVisibleMetrics.dropFirst()), id: \.self) { kind in
                            secondaryMetricCard(for: kind)
                        }
                    }
                }
            }
            .animation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate), value: expandedSecondaryMetrics)
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
            tint: photosTheme.softTint,
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.recentPhotos"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                moduleHeader(
                    eyebrow: AppLocalization.string("home.photos.latestsession"),
                    title: AppLocalization.string("Recent photos"),
                    subtitle: recentPhotosSubtitle,
                    accent: Color.cyan,
                    accessibilityIdentifier: "home.module.recentPhotos.title",
                    action: { router.selectedTab = .photos },
                    actionAccessibilityLabel: AppLocalization.string("accessibility.open.photos")
                )

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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        infoPill(text: recentPhotosContextPrimary, tint: photosTheme.accent)
                        infoPill(text: recentPhotosContextSecondary, tint: AppColorRoles.textSecondary)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        infoPill(text: recentPhotosContextPrimary, tint: photosTheme.accent)
                        infoPill(text: recentPhotosContextSecondary, tint: AppColorRoles.textSecondary)
                    }
                }

                Spacer(minLength: 2)

                Button {
                    handleRecentPhotosCompareTap()
                } label: {
                    dashboardInsightButtonCard(
                        eyebrow: AppLocalization.string("home.photos.latestsession"),
                        title: recentPhotosInsightTitle,
                        detail: recentPhotosInsightDetail,
                        note: recentPhotosInsightNote,
                        tint: photosTheme.pillFill,
                        stroke: photosTheme.border
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasEnoughSavedPhotosForCompare)
                .accessibilityIdentifier("home.recentPhotos.compare.button")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private var recentPhotosEmptyModule: some View {
        HomeWidgetCard(
            tint: photosTheme.softTint,
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.recentPhotos"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                moduleHeader(
                    eyebrow: AppLocalization.string("home.photos.latestsession"),
                    title: AppLocalization.string("Recent photos"),
                    subtitle: AppLocalization.string("home.photos.empty.subtitle"),
                    accent: photosTheme.accent
                )

                editorialEmptyStateCard(
                    eyebrow: AppLocalization.string("home.empty.eyebrow"),
                    title: AppLocalization.string("home.photos.empty.title"),
                    detail: AppLocalization.string("home.photos.empty.detail"),
                    accent: photosTheme.accent,
                    ctaTitle: AppLocalization.string("Open Photos")
                ) {
                    router.selectedTab = .photos
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private var healthSummaryModule: some View {
        Group {
            if isHealthSectionMounted {
                HomeWidgetCard(
                    tint: healthTheme.softTint,
                    depth: .base,
                    contentPadding: 16,
                    accessibilityIdentifier: "home.module.healthSummary"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            moduleHeader(
                                eyebrow: AppLocalization.string("home.health.snapshot"),
                                title: AppLocalization.string("Health"),
                                subtitle: healthModuleSubtitle,
                                accent: healthTheme.accent,
                                accessibilityIdentifier: "home.module.healthSummary.title"
                            )
                            infoPill(text: healthModulePillText, tint: healthTheme.accent)
                        }

                        if homeHealthStatItems.isEmpty {
                            editorialEmptyStateCard(
                                eyebrow: AppLocalization.string("home.empty.eyebrow"),
                                title: healthEmptyStateTitle,
                                detail: healthEmptyStateDetail,
                                accent: healthTheme.accent,
                                ctaTitle: healthEmptyStateCTA
                            ) {
                                if !isSyncEnabled {
                                    connectHealthKitFromChecklist()
                                } else {
                                    router.selectedTab = .settings
                                }
                            }
                        } else if premiumStore.isPremium {
                            dashboardInsightCard(
                                eyebrow: AppLocalization.string("home.health.summary.card"),
                                title: homeHealthSummaryTitle,
                                detail: homeHealthSummaryDetail,
                                tint: healthTheme.pillFill,
                                stroke: AppColorRoles.borderSubtle
                            )

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)
                                ],
                                spacing: 10
                            ) {
                                ForEach(visibleHomeHealthStatItems) { item in
                                    compactHealthStatCard(item)
                                }
                            }
                        } else {
                            ForEach(visibleHomeHealthStatItems) { item in
                                compactHealthStatCard(item)
                                    .accessibilityIdentifier("home.health.preview.metric")
                            }

                            if let previewLabel = visibleHomeHealthStatItems.first?.label {
                                Text(previewLabel)
                                    .font(.system(size: 1))
                                    .foregroundStyle(.clear)
                                    .accessibilityIdentifier("home.health.preview.label")
                                    .frame(width: 1, height: 1)
                                    .clipped()
                            }

                            if let previewBadge = visibleHomeHealthStatItems.first?.badge {
                                Text(previewBadge)
                                    .font(.system(size: 1))
                                    .foregroundStyle(.clear)
                                    .accessibilityIdentifier("home.health.preview.badge")
                                    .frame(width: 1, height: 1)
                                    .clipped()
                            }

                            Button {
                                Haptics.selection()
                                premiumStore.presentPaywall(reason: .feature("Health Summary & Physique"))
                            } label: {
                                dashboardInsightButtonCard(
                                    eyebrow: AppLocalization.string("home.health.summary.card"),
                                    title: AppLocalization.string("home.health.premium.title"),
                                    detail: AppLocalization.string("home.health.premium.detail"),
                                    note: AppLocalization.string("home.photos.compare.note.premium"),
                                    tint: premiumTheme.pillFill,
                                    stroke: premiumTheme.border
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.health.premium.button")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                healthSectionPlaceholder
            }
        }
    }

    private var checklistModule: some View {
        HomeWidgetCard(
            tint: homeTheme.softTint,
            depth: .base,
            contentPadding: 14,
            accessibilityIdentifier: "home.module.setupChecklist"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("home.module.setup.eyebrow"))
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(Color.appAccent)
                        Text(AppLocalization.string("Finish setup"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                        Text(AppLocalization.plural("home.module.setup.subtitle", activeChecklistItems.count))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()

                    infoPill(
                        text: AppLocalization.string("home.module.setup.pill", activeChecklistItems.count),
                        tint: Color.appAccent
                    )

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
                } else {
                    ForEach(shownChecklistItems) { item in
                        Button {
                            performChecklistAction(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.appAccent)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(AppTypography.captionEmphasis)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.detail)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.85)
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
                        .accessibilityIdentifier("home.checklist.item.\(item.id)")
                    }

                    if !showMoreChecklistItems, activeChecklistItems.count > collapsedChecklistItems.count {
                Button {
                    Haptics.selection()
                    showMoreChecklistItems = true
                } label: {
                            Text(AppLocalization.string("Show %d more", activeChecklistItems.count - collapsedChecklistItems.count))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(Color.appAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.checklist.showMore")
            }

                    Text("\(shownChecklistItems.count)")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("home.checklist.visibleCount")
                        .frame(width: 1, height: 1)
                        .clipped()

                    Text(shownChecklistItems.map(\.id).joined(separator: ","))
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("home.checklist.visibleIDs")
                        .frame(width: 1, height: 1)
                        .clipped()
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

    private var nextFocusInsightMetricKinds: [MetricKind] {
        var ordered: [MetricKind] = []
        for kind in dashboardVisibleMetrics + Array(cachedGoalsByKind.keys) + Array(cachedLatestByKind.keys) {
            if !ordered.contains(kind) {
                ordered.append(kind)
            }
        }
        return ordered
    }

    private var nextFocusInsight: HomeNextFocusInsight {
        if isUITestMode && ProcessInfo.processInfo.arguments.contains("-uiTestLongNextFocusInsight") {
            return HomeNextFocusInsight(
                headline: nil,
                primaryValue: AppLocalization.string("home.nextfocus.uitest.long.primary"),
                supportingLabel: AppLocalization.string("home.nextfocus.uitest.long.supporting"),
                summary: AppLocalization.string("home.nextfocus.uitest.long.summary"),
                cta: AppLocalization.string("home.nextfocus.cta.metric"),
                action: .metric(.waist),
                accessibilityValue: "metric"
            )
        }

        if let goalCandidate = nextFocusInsightMetricKinds
            .compactMap({ goalInsightCandidate(for: $0) })
            .max(by: { $0.score < $1.score }) {
            return goalCandidate.insight
        }

        if let trendCandidate = nextFocusInsightMetricKinds
            .compactMap({ positiveTrendCandidate(for: $0, days: 30) ?? positiveTrendCandidate(for: $0, days: 7) })
            .max(by: { $0.score < $1.score }) {
            return trendCandidate.insight
        }

        return HomeNextFocusInsight(
            headline: AppLocalization.string("Set goal"),
            primaryValue: nil,
            supportingLabel: nil,
            summary: AppLocalization.string("home.nextfocus.fallback.summary"),
            cta: AppLocalization.string("home.nextfocus.cta.goal"),
            action: .measurements,
            accessibilityValue: "setGoal"
        )
    }

    private func goalInsightCandidate(for kind: MetricKind) -> HomeNextFocusCandidate? {
        guard let goal = cachedGoalsByKind[kind],
              let latest = cachedLatestByKind[kind],
              !goal.isAchieved(currentValue: latest.value) else { return nil }

        let baseline = goalBaselineValue(for: kind, goal: goal)
        let fullDistance = abs(goal.targetValue - baseline)
        guard fullDistance > 0.0001 else { return nil }

        let remaining = abs(goal.remainingToGoal(currentValue: latest.value))
        let progress = max(0, min(1, 1 - (remaining / fullDistance)))
        guard progress >= 0.4 else { return nil }

        let remainingText = formattedMetricValue(for: kind, metricValue: remaining)
        return HomeNextFocusCandidate(
            insight: HomeNextFocusInsight(
                headline: nil,
                primaryValue: remainingText,
                supportingLabel: nil,
                summary: AppLocalization.string("home.nextfocus.insight.goal.summary", remainingText, kind.title),
                cta: AppLocalization.string("home.nextfocus.cta.metric"),
                action: .metric(kind),
                accessibilityValue: "metric"
            ),
            score: 2.5 + progress
        )
    }

    private func positiveTrendCandidate(for kind: MetricKind, days: Int) -> HomeNextFocusCandidate? {
        guard let window = trendWindowSamples(for: kind, days: days) else { return nil }
        let outcome = kind.trendOutcome(from: window.oldest.value, to: window.newest.value, goal: cachedGoalsByKind[kind])
        guard outcome == .positive else { return nil }

        let newestValue = kind.valueForDisplay(fromMetric: window.newest.value, unitsSystem: unitsSystem)
        let oldestValue = kind.valueForDisplay(fromMetric: window.oldest.value, unitsSystem: unitsSystem)
        let delta = newestValue - oldestValue
        let absoluteDelta = abs(delta)
        guard absoluteDelta >= minimumInsightDelta(for: kind) else { return nil }

        let directionKey = delta >= 0
            ? "home.nextfocus.insight.trend.up.summary"
            : "home.nextfocus.insight.trend.down.summary"
        let deltaText = String(format: "%.1f %@", absoluteDelta, kind.unitSymbol(unitsSystem: unitsSystem))
        let periodKey = days >= 30 ? "home.nextfocus.period.30d" : "home.nextfocus.period.7d"
        let periodChipKey = days >= 30 ? "home.nextfocus.periodchip.30d" : "home.nextfocus.periodchip.7d"

        return HomeNextFocusCandidate(
            insight: HomeNextFocusInsight(
                headline: nil,
                primaryValue: delta >= 0 ? "+\(deltaText)" : "-\(deltaText)",
                supportingLabel: AppLocalization.string(periodChipKey),
                summary: AppLocalization.string(directionKey, kind.title, AppLocalization.string(periodKey)),
                cta: AppLocalization.string("home.nextfocus.cta.metric"),
                action: .metric(kind),
                accessibilityValue: "metric"
            ),
            score: 1.0 + (days >= 30 ? 0.35 : 0.0) + min(absoluteDelta / minimumInsightDelta(for: kind), 2.0)
        )
    }

    private func trendWindowSamples(for kind: MetricKind, days: Int) -> (oldest: MetricSample, newest: MetricSample)? {
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: AppClock.now) else { return nil }
        let window = samplesForKind(kind).filter { $0.date >= startDate }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID else { return nil }
        return (oldest, newest)
    }

    private func minimumInsightDelta(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .weight:
            return unitsSystem == "imperial" ? 1.0 : 0.5
        case .length:
            return unitsSystem == "imperial" ? 0.25 : 0.5
        case .percent:
            return 0.3
        }
    }

    private func goalBaselineValue(for kind: MetricKind, goal: MetricGoal) -> Double {
        if let startValue = goal.startValue {
            return startValue
        }

        let sortedSamples = samplesForKind(kind).sorted { $0.date < $1.date }
        let anchorDate = goal.startDate ?? goal.createdDate
        if let baseline = sortedSamples.last(where: { $0.date <= anchorDate }) {
            return baseline.value
        }
        return sortedSamples.first?.value ?? cachedLatestByKind[kind]?.value ?? goal.targetValue
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

    private var keyMetricsSubtitle: String {
        if !hasAnyMeasurements && cachedLatestByKind.isEmpty {
            return AppLocalization.string("home.keymetrics.empty.subtitle")
        }
        if dashboardVisibleMetrics.isEmpty {
            return AppLocalization.string("home.keymetrics.empty.selection.subtitle")
        }
        return AppLocalization.string("home.keymetrics.ready.subtitle", dashboardVisibleMetrics.count)
    }

    private var recentPhotosInsightTitle: String {
        if hasEnoughSavedPhotosForCompare {
            return AppLocalization.string("home.photos.compare.title")
        }
        return AppLocalization.string("home.photos.first.title")
    }

    private var recentPhotosInsightDetail: String {
        if hasEnoughSavedPhotosForCompare {
            return premiumStore.isPremium
                ? AppLocalization.string("home.photos.compare.detail.home")
                : AppLocalization.string("home.photos.compare.detail.locked")
        }
        return AppLocalization.string("home.photos.first.detail")
    }

    private var recentPhotosInsightNote: String? {
        guard hasEnoughSavedPhotosForCompare, !premiumStore.isPremium else { return nil }
        return AppLocalization.string("home.photos.compare.note.premium")
    }

    private var latestSavedPhoto: PhotoEntry? {
        homeCompareCandidates.first
    }

    private var secondLatestSavedPhoto: PhotoEntry? {
        homeCompareCandidates.dropFirst().first
    }

    private var recentPhotosSubtitle: String {
        guard let latestSavedPhoto else {
            return AppLocalization.string("home.photos.empty.subtitle")
        }
        return AppLocalization.string("home.photos.meta.latest", relativeDescription(since: latestSavedPhoto.date))
    }

    private var recentPhotosContextPrimary: String {
        if let latestSavedPhoto {
            return AppLocalization.string("home.photos.context.primary", relativeDescription(since: latestSavedPhoto.date))
        }
        return AppLocalization.string("home.photos.context.primary.empty")
    }

    private var recentPhotosContextSecondary: String {
        if let latestSavedPhoto, let secondLatestSavedPhoto {
            let daysBetween = Calendar.current.dateComponents([.day], from: secondLatestSavedPhoto.date, to: latestSavedPhoto.date).day ?? 0
            let safeDaysBetween = max(daysBetween, 0)
            return AppLocalization.string("home.photos.context.secondary.gap", safeDaysBetween)
        }
        if pendingPhotoSaveStore.pendingItems.isEmpty {
            return AppLocalization.string("home.photos.context.secondary.empty")
        }
        return AppLocalization.string("home.photos.context.secondary.pending")
    }

    private var homeHealthStatItems: [HomeHealthStatItem] {
        var items: [HomeHealthStatItem] = []

        if let latestWeight {
            items.append(HomeHealthStatItem(label: MetricKind.weight.title, value: formattedMetricValue(for: .weight, metricValue: latestWeight)))
        }
        if let latestWaist {
            items.append(HomeHealthStatItem(label: MetricKind.waist.title, value: formattedMetricValue(for: .waist, metricValue: latestWaist)))
        }
        if let latestBodyFat, latestBodyFat > 0 {
            items.append(HomeHealthStatItem(label: MetricKind.bodyFat.title, value: String(format: "%.1f %%", latestBodyFat)))
        }
        if let latestLeanMass, latestLeanMass > 0 {
            items.append(HomeHealthStatItem(label: MetricKind.leanBodyMass.title, value: formattedMetricValue(for: .leanBodyMass, metricValue: latestLeanMass)))
        }

        return Array(items.prefix(4))
    }

    private var homeHealthPreviewItem: HomeHealthStatItem? {
        if let bmiResult = HealthMetricsCalculator.calculateBMI(
            weightKg: latestWeight,
            heightCm: manualHeight > 0 ? manualHeight : latestHeight,
            age: userAge
        ) {
            return HomeHealthStatItem(
                label: AppLocalization.string("BMI (Body Mass Index)"),
                value: String(format: "%.1f", bmiResult.bmi),
                badge: AppLocalization.string(bmiResult.category.rawValue)
            )
        }

        return homeHealthStatItems.first(where: { $0.label != MetricKind.weight.title }) ?? homeHealthStatItems.first
    }

    private var visibleHomeHealthStatItems: [HomeHealthStatItem] {
        premiumStore.isPremium ? homeHealthStatItems : (homeHealthPreviewItem.map { [$0] } ?? [])
    }

    private var homeHealthSummaryTitle: String {
        if let bodyFat = latestBodyFat, bodyFat > 0 {
            return AppLocalization.string("home.health.summary.bodyfat", String(format: "%.1f %%", bodyFat))
        }
        if let leanMass = latestLeanMass, leanMass > 0 {
            return AppLocalization.string("home.health.summary.leanmass", formattedMetricValue(for: .leanBodyMass, metricValue: leanMass))
        }
        if let weight = latestWeight {
            return AppLocalization.string("home.health.summary.weight", formattedMetricValue(for: .weight, metricValue: weight))
        }
        return AppLocalization.string("home.health.summary.default")
    }

    private var homeHealthSummaryDetail: String {
        if let waistDelta7dText {
            return waistDelta7dText
        }
        if let weightDelta7dText {
            return weightDelta7dText
        }
        return AppLocalization.string("home.health.summary.detail.default")
    }

    private var healthModuleSubtitle: String {
        if homeHealthStatItems.isEmpty {
            return isSyncEnabled
                ? AppLocalization.string("home.health.subtitle.waiting")
                : AppLocalization.string("home.health.subtitle.setup")
        }
        if !premiumStore.isPremium {
            return AppLocalization.string("home.health.subtitle.preview")
        }
        return AppLocalization.string("home.health.subtitle.ready")
    }

    private var healthModulePillText: String {
        if homeHealthStatItems.isEmpty {
            return AppLocalization.string("home.health.pill.setup")
        }
        return premiumStore.isPremium
            ? AppLocalization.string("home.health.pill.ready")
            : AppLocalization.string("home.health.pill.preview")
    }

    private var healthEmptyStateTitle: String {
        isSyncEnabled
            ? AppLocalization.string("home.health.empty.synced.title")
            : AppLocalization.string("home.health.empty.disconnected.title")
    }

    private var healthEmptyStateDetail: String {
        if !premiumStore.isPremium {
            return isSyncEnabled
                ? AppLocalization.string("home.health.empty.synced.detail.preview")
                : AppLocalization.string("home.health.empty.disconnected.detail.preview")
        }
        return isSyncEnabled
            ? AppLocalization.string("home.health.empty.synced.detail")
            : AppLocalization.string("home.health.empty.disconnected.detail")
    }

    private var healthEmptyStateCTA: String {
        isSyncEnabled
            ? AppLocalization.string("Settings")
            : AppLocalization.string("Connect Apple Health")
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
                        Button { showStreakDetail = true } label: {
                            StreakBadge(
                                count: streakManager.currentStreak,
                                shouldAnimate: streakManager.shouldPlayAnimation,
                                onAnimationComplete: { streakManager.markAnimationPlayed() }
                            )
                        }
                        .buttonStyle(.plain)
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

        let activeMetricCount = metricsStore.activeKinds.count
        let totalMetricCount = metricsStore.allKindsInOrder.count
        let inactiveMetricCount = totalMetricCount - activeMetricCount
        items.append(
            SetupChecklistItem(
                id: "choose_metrics",
                title: AppLocalization.string("Choose metrics"),
                detail: inactiveMetricCount > 0
                    ? AppLocalization.string("checklist.choosemetrics.detail.dynamic", activeMetricCount, inactiveMetricCount)
                    : AppLocalization.string("Track only what matters to you."),
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

    private var collapsedChecklistItems: [SetupChecklistItem] {
        Array(activeChecklistItems.prefix(3))
    }

    private var shownChecklistItems: [SetupChecklistItem] {
        if showMoreChecklistItems {
            return activeChecklistItems
        }
        return collapsedChecklistItems
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
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.85)
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

                    if !showMoreChecklistItems, activeChecklistItems.count > collapsedChecklistItems.count {
                        Button {
                            Haptics.selection()
                            showMoreChecklistItems = true
                        } label: {
                            Text(AppLocalization.string("Show %d more", activeChecklistItems.count - collapsedChecklistItems.count))
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

                if shouldShowHealthSettingsShortcut {
                    Button {
                        openAppSettings()
                    } label: {
                        Text(AppLocalization.string("Open iOS Settings"))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
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

    private func formattedMetricValue(for kind: MetricKind, metricValue: Double) -> String {
        let shown = kind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%.1f %@", shown, unit)
    }

    private func relativeDescription(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: AppClock.now)
    }

    private func secondaryMetricCard(for kind: MetricKind) -> some View {
        Group {
            if expandedSecondaryMetrics.contains(kind) {
                expandedSecondaryMetricCard(for: kind)
                    .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).expanded")
            } else {
                Button {
                    Haptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                        _ = expandedSecondaryMetrics.insert(kind)
                    }
                } label: {
                    compactMetricRow(for: kind)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).toggle")
                .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
                .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
            }
        }
    }

    private func compactMetricRow(for kind: MetricKind) -> some View {
        let latestText = cachedLatestByKind[kind].map { formattedMetricValue(for: kind, metricValue: $0.value) } ?? AppLocalization.string("No data yet")
        let detailText = metricDeltaTextFromCache(kind: kind, days: 7)
            ?? secondaryMetricGoalSummary(for: kind)
            ?? AppLocalization.string("Log another check-in to reveal the trend.")

        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                kind.iconView(font: AppTypography.captionEmphasis, size: 14, tint: Color.appAccent)
                Text(kind.title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(latestText)
                    .font(AppTypography.captionEmphasis.monospacedDigit())
                    .foregroundStyle(.white)
                Text(detailText)
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.44))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func expandedSecondaryMetricCard(for kind: MetricKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    Haptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                        _ = expandedSecondaryMetrics.remove(kind)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.66))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).collapse")
            }

            if isUITestMode {
                Button("collapse") {
                    withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                        _ = expandedSecondaryMetrics.remove(kind)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).collapseHook")
            }

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
            .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).openDetail")
        }
    }

    private func moduleHeader(
        eyebrow: String,
        title: String,
        subtitle: String,
        accent: Color,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil,
        actionAccessibilityLabel: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(accent)

                Text(title)
                    .font(AppTypography.displaySection)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .accessibilityIdentifier(accessibilityIdentifier ?? "")

                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let action {
                Button(action: action) {
                    Image(systemName: "arrow.up.right")
                        .font(AppTypography.iconMedium)
                        .foregroundStyle(accent)
                        .frame(width: 36, height: 36)
                        .background(AppColorRoles.surfaceInteractive)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionAccessibilityLabel ?? "")
            }
        }
    }

    private func editorialEmptyStateCard(
        eyebrow: String,
        title: String,
        detail: String,
        accent: Color,
        ctaTitle: String,
        ctaAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow)
                .font(AppTypography.eyebrow)
                .foregroundStyle(accent)

            Text(title)
                .font(AppTypography.titleCompact)
                .foregroundStyle(AppColorRoles.textPrimary)

            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(3)

            Button(action: ctaAction) {
                Text(ctaTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func infoPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTypography.badge)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func dashboardInsightCard(
        eyebrow: String,
        title: String,
        detail: String,
        tint: Color,
        stroke: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(AppTypography.eyebrow)
                .foregroundStyle(AppColorRoles.textTertiary)

            Text(title)
                .font(AppTypography.titleCompact)
                .foregroundStyle(AppColorRoles.textPrimary)

            Text(detail)
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
    }

    private func dashboardInsightButtonCard(
        eyebrow: String,
        title: String,
        detail: String,
        note: String?,
        tint: Color,
        stroke: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(AppTypography.eyebrow)
                .foregroundStyle(AppColorRoles.textTertiary)

            Text(title)
                .font(AppTypography.titleCompact)
                .foregroundStyle(AppColorRoles.textPrimary)

            Text(detail)
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineLimit(2)

            if let note {
                Text(note)
                    .font(AppTypography.badge)
                    .foregroundStyle(premiumTheme.accent)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(AppLocalization.string("home.card.open"))
                    .font(AppTypography.badge)
                Image(systemName: "arrow.right")
                    .font(AppTypography.iconSmall)
            }
            .foregroundStyle(AppColorRoles.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
    }

    private func compactHealthStatCard(_ item: HomeHealthStatItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.label)
                .font(AppTypography.eyebrow)
                .foregroundStyle(AppColorRoles.textTertiary)
                .lineLimit(1)

            Text(item.value)
                .font(AppTypography.dataDelta)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let badge = item.badge, !badge.isEmpty {
                Text(badge)
                    .font(AppTypography.badge)
                    .foregroundStyle(healthTheme.accent.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(healthTheme.pillFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(healthTheme.pillStroke, lineWidth: 1)
                            )
                    )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func secondaryMetricGoalSummary(for kind: MetricKind) -> String? {
        guard let goal = cachedGoalsByKind[kind],
              let latest = cachedLatestByKind[kind] else { return nil }

        if goal.isAchieved(currentValue: latest.value) {
            return AppLocalization.string("home.keymetrics.goal.achieved")
        }

        let remaining = abs(goal.remainingToGoal(currentValue: latest.value))
        let formattedRemaining = formattedMetricValue(for: kind, metricValue: remaining)
        return AppLocalization.string("home.keymetrics.goal.remaining", formattedRemaining)
    }

    private func handleNextFocusAction() {
        Haptics.selection()
        switch nextFocusInsight.action {
        case .metric(_):
            router.selectedTab = .measurements
        case .measurements:
            router.selectedTab = .measurements
        }
    }

    private func handleRecentPhotosCompareTap() {
        guard hasEnoughSavedPhotosForCompare else { return }
        Haptics.selection()
        if premiumStore.isPremium {
            showHomeCompareChooser = true
        } else {
            premiumStore.presentPaywall(reason: .feature("Photo Comparison Tool"))
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
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
        shouldShowHealthSettingsShortcut = false
        isChecklistConnectingHealth = true

        Task { @MainActor in
            defer { isChecklistConnectingHealth = false }
            do {
                try await effects.requestHealthKitAuthorization()
                isSyncEnabled = true
                onboardingSkippedHealthKit = true
                checklistStatusText = AppLocalization.string("Connected to Apple Health.")
                shouldShowHealthSettingsShortcut = false
                Haptics.success()
                refreshChecklistState()
            } catch {
                isSyncEnabled = false
                checklistStatusText = AppLocalization.string("Health access denied. Go to iOS Settings → MeasureMe → Health and allow access.")
                if let authError = error as? HealthKitAuthorizationError {
                    if authError == .denied {
                        shouldShowHealthSettingsShortcut = true
                        shouldPromptToOpenHealthSettings = true
                        Haptics.error()
                        return
                    } else {
                        checklistStatusText = authError.errorDescription ?? checklistStatusText
                    }
                }
                shouldShowHealthSettingsShortcut = true
                Haptics.error()
            }
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(settingsURL) else { return }
        UIApplication.shared.open(settingsURL)
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
                Text(AppLocalization.string("Recent photos"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 152)
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
                    .frame(height: 108)
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
                                    Task { @MainActor in
                                        lastPhotosGridWidth = width
                                    }
                                }
                            }
                            .onChange(of: geo.size.width) { _, newValue in
                                if newValue.isFinite, newValue > 0 {
                                    if abs(lastPhotosGridWidth - newValue) > 0.5 {
                                        Task { @MainActor in
                                            lastPhotosGridWidth = newValue
                                        }
                                    }
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
