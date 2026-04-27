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
    private static let homePhotoWindowDays = 3650
    @ObservedObject private var settingsStore = AppSettingsStore.shared

    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.profile.userAge) private var userAgeValue: Int = 0
    @AppSetting(\.profile.userGender) private var userGenderRaw: String = "notSpecified"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.profile.profilePhotoData) private var profilePhotoData: Data? = nil
    @AppSetting(\.health.isSyncEnabled) var isSyncEnabled: Bool = false
    @AppSetting(\.home.showLastPhotosOnHome) private var showLastPhotosOnHome: Bool = true
    @AppSetting(\.home.showMeasurementsOnHome) private var showMeasurementsOnHome: Bool = true
    @AppSetting(\.home.showHealthMetricsOnHome) private var showHealthMetricsOnHome: Bool = true
    @AppSetting(\.home.showStreakOnHome) private var showStreakOnHome: Bool = true
    @AppSetting(\.home.homeTabScrollOffset) private var homeTabScrollOffset: Double = 0.0
    @AppSetting(\.onboarding.onboardingFlowVersion) private var onboardingFlowVersion: Int = 0
    @AppSetting(\.onboarding.onboardingSkippedHealthKit) private var onboardingSkippedHealthKit: Bool = false
    @AppSetting(\.onboarding.onboardingSkippedReminders) private var onboardingSkippedReminders: Bool = false
    // activationTriggerQuickAdd removed — first measurement now happens during onboarding
    @AppSetting(\.onboarding.onboardingChecklistShow) private var showOnboardingChecklistOnHome: Bool = true
    @AppSetting(\.onboarding.onboardingChecklistMetricsCompleted) private var onboardingChecklistMetricsCompleted: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistMetricsExplored) private var onboardingChecklistMetricsExplored: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistPremiumExplored) private var onboardingChecklistPremiumExplored: Bool = false
    @AppSetting(\.onboarding.onboardingChecklistCollapsed) private var onboardingChecklistCollapsed: Bool = false
    @AppSetting(\.onboarding.onboardingPrimaryGoal) private var onboardingPrimaryGoalsRaw: String = ""
    @AppSetting(\.onboarding.activationCurrentTaskID) private var activationCurrentTaskID: String = ""
    @AppSetting(\.onboarding.activationCompletedTaskIDs) private var activationCompletedTaskIDsRaw: String = ""
    @AppSetting(\.onboarding.activationSkippedTaskIDs) private var activationSkippedTaskIDsRaw: String = ""
    @AppSetting(\.onboarding.activationIsDismissed) private var activationIsDismissed: Bool = false
    @AppSetting(\.home.settingsOpenTrackedMeasurements) private var settingsOpenTrackedMeasurements: Bool = false
    @AppSetting(\.home.settingsOpenReminders) private var settingsOpenReminders: Bool = false
    @AppSetting(\.home.settingsOpenHomeSettings) private var settingsOpenHomeSettings: Bool = false
    @AppSetting(\.home.settingsOpenProfile) private var settingsOpenProfile: Bool = false
    @AppSetting(\.home.homePhotoMetricSyncLastDate) private var photoMetricSyncLastDate: Double = 0
    @AppSetting(\.home.homePhotoMetricSyncLastID) private var photoMetricSyncLastID: String = ""
    @AppStorage("home.comparePhotosCardDismissed") private var comparePhotosCardDismissed: Bool = false
    
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var streakManager: StreakManager

    @Query private var recentSamples: [MetricSample]

    @Query private var goals: [MetricGoal]

    @Query private var recentPhotos: [PhotoEntry]

    @Query private var customDefinitions: [CustomMetricDefinition]
    
    @State private var showQuickAddSheet = false
    @State private var quickAddKinds: [MetricKind] = []
    @State private var showActivationMetricsSheet = false
    @State private var showActivationAddPhotoSheet = false
    @State private var showHomeSettingsSheet = false
    @State private var showHomeCompareChooser = false
    @State private var showStreakDetail = false
    @State private var showGoalStatusLegendSheet = false
    @State private var showActivationReminderPrompt = false
    @State private var isRequestingActivationReminder = false
    @State private var pendingActivationMetricCompletion = false
    @State private var didShowActivationReminderPrompt = false
    @State private var selectedPhotoForFullScreen: PhotoEntry?
    @State private var selectedHomeComparePair: HomeComparePair?
    @State private var scrollOffset: CGFloat = 0
    @State private var checklistStatusText: String?
    @State private var isChecklistConnectingHealth: Bool = false
    @State private var shouldShowHealthSettingsShortcut: Bool = false
    @State private var shouldPromptToOpenHealthSettings: Bool = false
    @State private var reminderChecklistCompleted: Bool = false
    @State private var showMoreChecklistItems: Bool = false
    @State private var didTrackPrimaryChecklistShown: Bool = false
    @State private var expandedSecondaryMetrics: Set<MetricKind> = []
    @State private var didCheckSevenDayPaywallPrompt: Bool = false
    @State private var didRunStartupPhases = false
    @State private var didEmitHomeInitialRender = false
    @State private var isPhotoMetricSyncInFlight = false
    @State private var hasAnySavedPhotosInStore = false
    @State private var hasEnoughSavedPhotosForCompareInStore = false
    @State private var isLastPhotosSectionMounted = false
    @State private var isHealthSectionMounted = false
    @State private var deferredPhaseBTask: Task<Void, Never>?
    @State private var deferredPhaseCTask: Task<Void, Never>?
    @State private var deferredSectionMountTask: Task<Void, Never>?
    
    // Dane HealthKit
    @State var latestBodyFat: Double?
    @State var latestLeanMass: Double?
    @State private var hasAnyMeasurements = false
    @State private var totalMetricSampleCount = 0

    // Zbuforowane dane pochodne - odswiezane przez onChange zamiast przeliczania przy kazdym renderze
    @State private var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @State private var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    @State private var cachedGoalsByKind: [MetricKind: MetricGoal] = [:]
    @State private var cachedCustomSamplesByIdentifier: [String: [MetricSample]] = [:]
    @State private var cachedCustomLatestByIdentifier: [String: MetricSample] = [:]
    @State private var cachedCustomGoalsByIdentifier: [String: MetricGoal] = [:]
    @State private var cachedDashboardItems: [HomeModuleLayoutItem] = []
    @State private var cachedVisiblePhotoTiles: [HomePhotoTile] = []
    @State private var cachedNextFocusInsight: HomeNextFocusInsight?

    private let maxVisibleMetrics = 5
    private let maxVisiblePhotos = 6
    private let autoCheckPaywallPrompt: Bool
    private let isUITestMode = UITestArgument.isPresent(.mode)
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

    private var isWelcomeHomeState: Bool {
        showActivationHub || isFreshHomeState
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
        let homePhotoWindowStart = Calendar.current.date(
            byAdding: .day,
            value: -Self.homePhotoWindowDays,
            to: AppClock.now
        ) ?? .distantPast
        _recentPhotos = Query(
            filter: #Predicate<PhotoEntry> { $0.date >= homePhotoWindowStart },
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
        let contextLabel: String
        let summary: String
        let cta: String
        let action: Action
        let accessibilityValue: String
    }

    private struct HomeNextFocusCandidate {
        let insight: HomeNextFocusInsight
        let score: Double
    }

    private struct PhotoSyncSnapshotPayload: Sendable {
        let kindRaw: String
        let value: Double
        let date: Date
    }

    private struct PhotoSyncCandidatePayload: Sendable {
        let date: Date
        let linkedMetrics: [PhotoSyncSnapshotPayload]
    }

    fileprivate enum HomePhotoTile: Identifiable {
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
    
    /// Widoczne metryki (maksymalnie 5)
    private var visibleMetrics: [MetricKind] {
        Array(metricsStore.keyMetrics.prefix(maxVisibleMetrics))
    }

    /// Metryki renderowane w widget boardzie.
    /// Kafelki glowne renderuja poziomy pasek na Home.
    private var dashboardVisibleMetrics: [MetricKind] {
        Array(visibleMetrics.prefix(maxVisibleMetrics))
    }

    /// Unified key metric identifiers (built-in + custom) for Home dashboard.
    private var dashboardKeyIdentifiers: [String] {
        metricsStore.keyMetricIdentifiers
    }

    private var customDefinitionsMap: [String: CustomMetricDefinition] {
        Dictionary(uniqueKeysWithValues: customDefinitions.map { ($0.identifier, $0) })
    }
    
    
    /// Widoczne kafelki zdjęć (persisted + pending, maksymalnie 6)
    private var visiblePhotoTiles: [HomePhotoTile] {
        cachedVisiblePhotoTiles
    }

    private var dashboardRecentPhotoTiles: [HomePhotoTile] {
        guard let newest = visiblePhotoTiles.first else { return [] }
        let olderCandidates = Array(visiblePhotoTiles.dropFirst())
        guard !olderCandidates.isEmpty else { return [newest] }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: AppClock.now) ?? 0
        return [newest, olderCandidates[day % olderCandidates.count]]
    }

    private var dashboardRecentPhotoTileViewModels: [HomeRecentPhotoTileViewModel] {
        dashboardRecentPhotoTiles.map { tile in
            switch tile {
            case .persisted(let photo):
                return .persisted(photo)
            case .pending(let item):
                return .pending(item)
            }
        }
    }

    private var homeCompareCandidates: [PhotoEntry] {
        recentPhotos
    }

    private var hasEnoughSavedPhotosForCompare: Bool {
        hasEnoughSavedPhotosForCompareInStore
    }

    private var hasAnyPhotoContent: Bool {
        hasAnySavedPhotosInStore || !pendingPhotoSaveStore.pendingItems.isEmpty
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
            samplesByKind: cachedSamplesByKind,
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
            latestHips: latestHips,
            samplesByKind: cachedSamplesByKind,
            unitsSystem: unitsSystem
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

        var customGrouped: [String: [MetricSample]] = [:]
        var customLatest: [String: MetricSample] = [:]

        for sample in recentSamples {
            if sample.kindRaw.hasPrefix("custom_") {
                customGrouped[sample.kindRaw, default: []].append(sample)
                if customLatest[sample.kindRaw] == nil {
                    customLatest[sample.kindRaw] = sample
                }
                continue
            }
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            grouped[kind, default: []].append(sample)
            if kindsToKeep.contains(kind), latest[kind] == nil {
                latest[kind] = sample
            }
        }

        cachedSamplesByKind = grouped
        cachedLatestByKind = latest
        cachedCustomSamplesByIdentifier = customGrouped
        cachedCustomLatestByIdentifier = customLatest

        // Cache custom goals
        var customGoals: [String: MetricGoal] = [:]
        for goal in goals where goal.kindRaw.hasPrefix("custom_") {
            if customGoals[goal.kindRaw] == nil {
                customGoals[goal.kindRaw] = goal
            }
        }
        cachedCustomGoalsByIdentifier = customGoals

        let fetchedMetricCount = allowFallbackFetch
            ? ((try? modelContext.fetchCount(FetchDescriptor<MetricSample>())) ?? recentSamples.count)
            : recentSamples.count
        totalMetricSampleCount = fetchedMetricCount
        hasAnyMeasurements = fetchedMetricCount > 0

        rebuildNextFocusInsightCache()
        refreshActivationProgress()
        autoHideChecklistIfCompleted()
    }

    private func metricDeltaTextFromCache(kind: MetricKind, days: Int) -> String? {
        (cachedSamplesByKind[kind] ?? []).deltaText(days: days, kind: kind, unitsSystem: unitsSystem)
    }

    private func refreshPhotoStoreState() {
        var descriptor = FetchDescriptor<PhotoEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        let newestPhotos = (try? modelContext.fetch(descriptor)) ?? []
        hasAnySavedPhotosInStore = !newestPhotos.isEmpty
        hasEnoughSavedPhotosForCompareInStore = newestPhotos.count >= 2
        rebuildVisiblePhotoTilesCache()
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

    private nonisolated static func latestPhotoSyncSnapshotByKey(
        from candidates: [PhotoSyncCandidatePayload]
    ) -> [String: PhotoSyncSnapshotPayload] {
        let calendar = Calendar.current
        var latestByKey: [String: PhotoSyncSnapshotPayload] = [:]
        for candidate in candidates {
            let dayStart = calendar.startOfDay(for: candidate.date).timeIntervalSince1970
            for snapshot in candidate.linkedMetrics {
                let key = "\(snapshot.kindRaw)|\(dayStart)"
                latestByKey[key] = snapshot
            }
        }
        return latestByKey
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
    private func syncMeasurementsFromPhotosIfNeeded(force: Bool = false) async {
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

        let syncCandidates: [PhotoSyncCandidatePayload] = photosWithMetrics.map { photo in
            PhotoSyncCandidatePayload(
                date: photo.date,
                linkedMetrics: photo.linkedMetrics.compactMap { snapshot in
                    guard let kindRaw = snapshot.kind?.rawValue else { return nil }
                    return PhotoSyncSnapshotPayload(kindRaw: kindRaw, value: snapshot.value, date: photo.date)
                }
            )
        }

        let latestSnapshotByKey = await Task.detached(priority: .utility) {
            HomeView.latestPhotoSyncSnapshotByKey(from: syncCandidates)
        }.value

        guard !latestSnapshotByKey.isEmpty else {
            updatePhotoSyncCursor(using: candidatePhotos)
            return
        }

        let syncedKindsRaw = Set(latestSnapshotByKey.values.map(\.kindRaw))
        let dayStarts = latestSnapshotByKey.keys.compactMap { key -> Double? in
            let components = key.split(separator: "|")
            guard components.count == 2 else { return nil }
            return Double(components[1])
        }
        let minDayStart = dayStarts.min()
        let maxDayStart = dayStarts.max()

        // Buduje cache istniejacych probek po (kindRaw, dayStart)
        var existingByKey: [String: MetricSample] = [:]
        do {
            let descriptor: FetchDescriptor<MetricSample>
            if syncedKindsRaw.isEmpty {
                descriptor = FetchDescriptor<MetricSample>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            } else if let minDayStart, let maxDayStart {
                let kinds = Array(syncedKindsRaw)
                let minDate = Date(timeIntervalSince1970: minDayStart)
                let maxDateExclusive = Calendar.current.date(
                    byAdding: .day,
                    value: 1,
                    to: Date(timeIntervalSince1970: maxDayStart)
                ) ?? Date(timeIntervalSince1970: maxDayStart)
                descriptor = FetchDescriptor<MetricSample>(
                    predicate: #Predicate<MetricSample> { sample in
                        kinds.contains(sample.kindRaw)
                        && sample.date >= minDate
                        && sample.date < maxDateExclusive
                    },
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
            for sample in existing {
                let startOfDay = cal.startOfDay(for: sample.date)
                let key = "\(sample.kindRaw)|\(startOfDay.timeIntervalSince1970)"
                if existingByKey[key] == nil { existingByKey[key] = sample }
            }
        } catch {
            AppLog.debug("⚠️ Failed to build existing samples index: \(error)")
        }

        for (key, payload) in latestSnapshotByKey {
            if let sample = existingByKey[key] {
                sample.value = payload.value
                sample.date = payload.date
            } else if let kind = MetricKind(rawValue: payload.kindRaw) {
                let sample = MetricSample(kind: kind, value: payload.value, date: payload.date)
                modelContext.insert(sample)
                existingByKey[key] = sample
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
        isLastPhotosSectionMounted = true
        isHealthSectionMounted = true
    }

    private func scheduleDeferredStartupPhaseB() {
        deferredPhaseBTask?.cancel()
        deferredPhaseBTask = Task { @MainActor in
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
        deferredPhaseCTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }

            let deferredSyncState = StartupInstrumentation.begin("HomeDeferredSync")
            StartupInstrumentation.event("HomeDeferredSyncStart")
            await syncMeasurementsFromPhotosIfNeeded(force: forceSync)
            StartupInstrumentation.event("HomeDeferredSyncEnd")
            StartupInstrumentation.end("HomeDeferredSync", state: deferredSyncState)
        }
    }

    private func scheduleDeferredSectionMounts() {
        deferredSectionMountTask?.cancel()
        deferredSectionMountTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            StartupInstrumentation.event("HomeLastPhotosMountStart")
            isLastPhotosSectionMounted = true
            StartupInstrumentation.event("HomeLastPhotosMountEnd")

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
        rebuildNextFocusInsightCache()
    }

    private func rebuildVisiblePhotoTilesCache() {
        let persistedCandidateLimit = maxVisiblePhotos * 3
        let persistedTiles = recentPhotos.prefix(persistedCandidateLimit).map { HomePhotoTile.persisted($0) }
        let pendingTiles = pendingPhotoSaveStore.pendingItems.map { HomePhotoTile.pending($0) }
        cachedVisiblePhotoTiles = Array(
            (persistedTiles + pendingTiles)
                .sorted { lhs, rhs in lhs.date > rhs.date }
                .prefix(maxVisiblePhotos)
        )
    }

    private func rebuildNextFocusInsightCache() {
        cachedNextFocusInsight = computeNextFocusInsight()
    }

    private var dashboardColumns: Int {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular ? 4 : 2
    }

    private var renderedDashboardItems: [HomeModuleLayoutItem] {
        cachedDashboardItems
    }

    private func rebuildDashboardItemsCache() {
        let layout = settingsStore.homeLayoutSnapshot()
        let runtimeVisibleItems = layout.items.map { item in
            var next = item
            next.isVisible = item.isVisible && shouldRenderModule(item.kind)
            if item.kind == .summaryHero {
                next.size = .wide
            }
            return next
        }
        cachedDashboardItems = HomeLayoutCompactor.compact(runtimeVisibleItems, columns: dashboardColumns)
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
            kinds: quickAddKinds.isEmpty ? metricsStore.activeKinds : quickAddKinds,
            latest: Dictionary(
                uniqueKeysWithValues: cachedLatestByKind.map { ($0.key, ($0.value.value, $0.value.date)) }
            ),
            unitsSystem: unitsSystem
        ) {
            quickAddKinds = []
            showQuickAddSheet = false
            refreshMeasurementCaches()
            refreshChecklistState()
        }
    }

    private var homeUITestHooks: some View {
        VStack(spacing: 0) {
            if showActivationHub {
                Text("1")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.module.activationHub.visible")
                    .frame(width: 1, height: 1)
                    .clipped()
                Text(activationCurrentTask?.rawValue ?? "")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.activation.currentTask")
                    .frame(width: 1, height: 1)
                    .clipped()
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

            ForEach(homeSecondaryMetricUITestKinds, id: \.self) { kind in
                Button {
                    if expandedSecondaryMetrics.contains(kind) {
                        expandedSecondaryMetrics.remove(kind)
                    } else {
                        expandedSecondaryMetrics.insert(kind)
                    }
                } label: {
                    Color.clear
                        .frame(width: 80, height: 80)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).toggle")
            }

            ForEach(Array(expandedSecondaryMetrics), id: \.self) { kind in
                VStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("expanded")
                .accessibilityIdentifier("home.keyMetrics.secondary.\(kind.rawValue).expanded")
                .frame(width: 44, height: 44)
                .opacity(0.01)
                .allowsHitTesting(false)
            }

            ForEach(Array(expandedSecondaryMetrics), id: \.self) { kind in
                Button("collapse") { collapseSecondaryMetric(kind) }
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

    private var homeSecondaryMetricUITestKinds: [MetricKind] {
        let visibleBuiltInSecondary = dashboardKeyIdentifiers.dropFirst().compactMap(MetricKind.init(rawValue:))
        if !visibleBuiltInSecondary.isEmpty {
            return visibleBuiltInSecondary
        }

        let fallbackKinds: [MetricKind] = [.bodyFat, .leanBodyMass, .waist]
        let activeFallbackKinds = fallbackKinds.filter { metricsStore.activeKinds.contains($0) }
        return activeFallbackKinds.isEmpty ? fallbackKinds : activeFallbackKinds
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { value in
                handleHomeScrollOffsetChange(value)
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
            .sheet(isPresented: $showActivationAddPhotoSheet) {
                NavigationStack {
                    AddPhotoView {
                        completeActivationTask(.addPhoto)
                    }
                    .environmentObject(metricsStore)
                }
            }
            .sheet(isPresented: $showActivationMetricsSheet) {
                ActivationMetricSelectionSheet(
                    recommendedKinds: activationRecommendedKinds,
                    metricsStore: metricsStore
                ) {
                    completeActivationTask(.chooseMetrics)
                }
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
                HomeCompareChooserOnDemandSheet(
                    initialOlderPhoto: secondLatestSavedPhoto,
                    initialNewerPhoto: latestSavedPhoto
                ) { olderPhoto, newerPhoto in
                    selectedHomeComparePair = HomeComparePair(olderPhoto: olderPhoto, newerPhoto: newerPhoto)
                }
                .presentationBackground(AppColorRoles.surfaceCanvas)
            }
            .sheet(item: $selectedHomeComparePair) { pair in
                ComparePhotosView(olderPhoto: pair.olderPhoto, newerPhoto: pair.newerPhoto)
            }
            .sheet(isPresented: $showStreakDetail) {
                StreakDetailView(streakManager: streakManager)
            }
            .sheet(isPresented: $showGoalStatusLegendSheet) {
                GoalStatusLegendSheet(currentStatus: goalStatus, currentStatusColor: goalStatusColor)
                    .presentationDetents([.fraction(0.42), .medium])
                    .presentationDragIndicator(.visible)
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
            .alert(
                FlowLocalization.app(
                    "Want a nudge to log again tomorrow?",
                    "Chcesz przypomnienie, żeby jutro znów coś zapisać?",
                    "¿Quieres un recordatorio para registrar de nuevo mañana?",
                    "Möchtest du morgen an den nächsten Eintrag erinnert werden?",
                    "Voulez-vous un rappel pour enregistrer à nouveau demain ?",
                    "Quer um lembrete para registrar de novo amanhã?"
                ),
                isPresented: $showActivationReminderPrompt
            ) {
                Button(FlowLocalization.app("Not now", "Nie teraz", "Ahora no", "Nicht jetzt", "Pas maintenant", "Agora não"), role: .cancel) {
                    declineActivationReminderPrompt()
                }
                .accessibilityIdentifier("home.activation.reminder.skip")

                Button(FlowLocalization.app("Remind me tomorrow", "Przypomnij mi jutro", "Recordarme mañana", "Morgen erinnern", "Me le rappeler demain", "Lembrar amanhã")) {
                    acceptActivationReminderPrompt()
                }
                .accessibilityIdentifier("home.activation.reminder.accept")
            } message: {
                Text(FlowLocalization.app(
                    "You just logged your first measurement. A timely reminder can help make the second one easier.",
                    "Właśnie zapisano pierwszy pomiar. Dobre przypomnienie może ułatwić drugi.",
                    "Acabas de registrar tu primera medida. Un recordatorio a tiempo puede facilitar la segunda.",
                    "Du hast gerade deine erste Messung eingetragen. Eine passende Erinnerung macht die zweite leichter.",
                    "Vous venez d'enregistrer votre première mesure. Un rappel au bon moment peut faciliter la deuxième.",
                    "Você acabou de registrar sua primeira medição. Um lembrete no momento certo pode facilitar a segunda."
                ))
            }
    }

    private func lifecycleObservedHomeRoot<Content: View>(
        _ content: Content,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        content
            .onAppear {
                handleHomeAppear()
            }
            .onDisappear {
                handleHomeDisappear()
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeScrollToChecklist)) { _ in
                scrollToChecklist(using: scrollProxy)
            }
    }

    private func refreshingHomeRoot<Content: View>(_ content: Content) -> some View {
        let contentWithMeasurementObservers = content
            .onChange(of: recentSamplesSignature) { _, _ in
                refreshMeasurementCaches()
            }
            .onChange(of: metricsStore.activeKinds) { _, _ in
                refreshMeasurementCaches()
                rebuildVisiblePhotoTilesCache()
            }
            .onChange(of: goals.count) { _, _ in
                rebuildGoalsCache()
                refreshActivationProgress()
                rebuildDashboardItemsCache()
            }

        let contentWithChecklistObservers = contentWithMeasurementObservers
            .onChange(of: settingsStore.snapshot.homeLayout.layoutData) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: horizontalSizeClass) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: isSyncEnabled) { _, _ in
                refreshChecklistState()
                fetchHealthKitData()
            }
            .onChange(of: recentPhotos.count) { _, _ in
                refreshPhotoStoreState()
                refreshChecklistState()
                if didRunStartupPhases {
                    scheduleDeferredStartupPhaseC(delayMilliseconds: 900)
                }
            }
            .onChange(of: pendingPhotoItemsSignature) { _, _ in
                refreshPhotoStoreState()
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
            .onChange(of: activationCurrentTaskID) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: activationIsDismissed) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: onboardingFlowVersion) { _, _ in
                rebuildDashboardItemsCache()
            }

        let observedContent = contentWithChecklistObservers
            .onChange(of: activeChecklistItems.count) { _, newCount in
                withAnimation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate)) {
                    rebuildDashboardItemsCache()
                }
                if newCount <= collapsedChecklistItems.count {
                    showMoreChecklistItems = false
                }
            }
            .onChange(of: showMeasurementsOnHome) { _, _ in
                rebuildDashboardItemsCache()
                rebuildNextFocusInsightCache()
            }
            .onChange(of: showLastPhotosOnHome) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: showHealthMetricsOnHome) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: showOnboardingChecklistOnHome) { _, _ in
                rebuildDashboardItemsCache()
            }
            .onChange(of: router.selectedTab) { _, newTab in
                if newTab == .home {
                    refreshChecklistState()
                }
                if newTab == .measurements && !onboardingChecklistMetricsExplored && isWelcomeHomeState {
                    onboardingChecklistMetricsExplored = true
                    withAnimation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate)) {
                        rebuildDashboardItemsCache()
                    }
                }
            }

        return observedContent
            .refreshable {
                await refreshHomeContent()
            }
    }

    private func handleHomeAppear() {
        Task { @MainActor in
            refreshPhotoStoreState()
            rebuildVisiblePhotoTilesCache()
            rebuildDashboardItemsCache()
            if autoCheckPaywallPrompt && !didCheckSevenDayPaywallPrompt {
                didCheckSevenDayPaywallPrompt = true
                premiumStore.checkSevenDayPromptIfNeeded()
            }
            if UITestArgument.isPresent(.expandChecklist) {
                showMoreChecklistItems = true
            }
            emitHomeInitialRenderIfNeeded()
            runStartupPhasesIfNeeded()
        }
    }

    private func handleHomeDisappear() {
        expandedSecondaryMetrics.removeAll()
    }

    private func scrollToChecklist(using scrollProxy: ScrollViewProxy) {
        withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
            scrollProxy.scrollTo(HomeModuleKind.activationHub.rawValue, anchor: .top)
        }
    }

    private func handleHomeScrollOffsetChange(_ value: CGFloat) {
        scrollOffset = value
        let normalizedOffset = Double(value)
        // Defer AppSetting write to avoid publishing during the view-update pass.
        if abs(homeTabScrollOffset - normalizedOffset) > 8 {
            Task { @MainActor in
                homeTabScrollOffset = normalizedOffset
            }
        }
    }

    private func handleUITestShowMoreChecklistTap() {
        showMoreChecklistItems = true
    }

    private func refreshHomeContent() async {
        guard !showStreakDetail else { return }
        await syncMeasurementsFromPhotosIfNeeded(force: true)
        refreshMeasurementCaches()
        rebuildGoalsCache()
        rebuildVisiblePhotoTilesCache()
        fetchHealthKitData()
        refreshChecklistState()
    }

    private func collapseSecondaryMetric(_ kind: MetricKind) {
        withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
            _ = expandedSecondaryMetrics.remove(kind)
        }
    }

    private func shouldRenderModule(_ kind: HomeModuleKind) -> Bool {
        switch kind {
        case .summaryHero:
            return true
        case .quickActions:
            return false
        case .keyMetrics:
            if isWelcomeHomeState { return showMeasurementsOnHome }
            return showMeasurementsOnHome
        case .recentPhotos:
            if isWelcomeHomeState { return hasAnyPhotoContent && showLastPhotosOnHome }
            return showLastPhotosOnHome
        case .healthSummary:
            return false
        case .activationHub:
            return false
        case .setupChecklist:
            return false
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
        case .activationHub:
            EmptyView()
        case .setupChecklist:
            EmptyView()
        }
    }

    private var moduleAccentText: Color {
        colorScheme == .dark ? FeatureTheme.home.accent : AppColorRoles.textSecondary
    }

    private var homeHeroTint: Color {
        colorScheme == .dark ? homeTheme.strongTint : .clear
    }

    private var neutralRowFill: Color {
        AppColorRoles.surfaceInteractive
    }

    private var neutralRowStroke: Color {
        AppColorRoles.borderSubtle
    }

    private var checklistIconSurface: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : AppColorRoles.surfaceAccentSoft
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
        HomeTopSummarySection(
            dateText: homeHeaderDateText,
            greetingTitle: greetingTitle,
            avatarText: homeAvatarText,
            profilePhotoData: profilePhotoData,
            isPremium: homeSummaryIsPremium,
            insights: homeAIInsights,
            analysisItems: homeAIAnalysisItems,
            onUnlockPremium: {
                Haptics.selection()
                premiumStore.presentPaywall(reason: .feature("AI Insights"))
            },
            onOpenProfile: {
                Haptics.selection()
                settingsOpenProfile = true
                router.selectedTab = .settings
            }
        )
    }

    private var homeSummaryIsPremium: Bool {
        #if DEBUG
        if UITestArgument.isPresent(.forceNonPremium) {
            return false
        }
        if UITestArgument.isPresent(.forcePremium) {
            return true
        }
        #endif
        return premiumStore.isPremium
    }

    private var quickActionsModule: some View {
        HomeWidgetCard(
            tint: FeatureTheme.home.softTint,
            depth: .floating,
            contentPadding: 14,
            accessibilityIdentifier: "home.module.quickActions"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Header with step counter
                HStack {
                    Text(AppLocalization.string("home.quickactions.title"))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Spacer()
                    Text(AppLocalization.string("home.discovery.counter", completedDiscoverySteps.count, discoverySteps.count))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }

                // Completed steps — compact checkmarks
                if !completedDiscoverySteps.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(completedDiscoverySteps, id: \.id) { step in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColorRoles.stateSuccess)
                                Text(step.title)
                                    .font(AppTypography.microEmphasis)
                                    .foregroundStyle(AppColorRoles.textTertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColorRoles.stateSuccess.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Current step — prominent single action
                if let current = currentDiscoveryStep {
                    Button {
                        performChecklistAction(current.id)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: current.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.appAccent.opacity(0.16))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(current.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Text(current.detail)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColorRoles.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(AppColorRoles.surfaceSecondary.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var discoverySteps: [SetupChecklistItem] {
        [
            SetupChecklistItem(
                id: "explore_metrics",
                title: AppLocalization.string("home.discovery.explore_metrics.title"),
                detail: AppLocalization.string("home.discovery.explore_metrics.detail"),
                icon: "chart.line.uptrend.xyaxis",
                isCompleted: onboardingChecklistMetricsExplored,
                isLoading: false
            ),
            SetupChecklistItem(
                id: "first_measurement",
                title: AppLocalization.string("home.discovery.first_measurement.title"),
                detail: AppLocalization.string("home.discovery.first_measurement.detail"),
                icon: "ruler.fill",
                isCompleted: hasAnyMeasurements,
                isLoading: false
            ),
            SetupChecklistItem(
                id: "first_photo",
                title: AppLocalization.string("home.discovery.first_photo.title"),
                detail: AppLocalization.string("home.discovery.first_photo.detail"),
                icon: "camera.fill",
                isCompleted: hasAnyPhotoContent,
                isLoading: false
            ),
            SetupChecklistItem(
                id: "choose_metrics",
                title: AppLocalization.string("home.discovery.choose_metrics.title"),
                detail: AppLocalization.string("home.discovery.choose_metrics.detail"),
                icon: "slider.horizontal.3",
                isCompleted: onboardingChecklistMetricsCompleted,
                isLoading: false
            ),
        ]
    }

    private var currentDiscoveryStep: SetupChecklistItem? {
        discoverySteps.first(where: { !$0.isCompleted })
    }

    private var completedDiscoverySteps: [SetupChecklistItem] {
        discoverySteps.filter(\.isCompleted)
    }

    private var keyMetricsModule: some View {
        HomeKeyMetricsCard(
            snapshot: HomeKeyMetricsSnapshot(
                subtitle: keyMetricsSubtitle,
                state: keyMetricsState
            ),
            onAddMeasurement: { showQuickAddSheet = true },
            onOpenMeasurements: { router.selectTab(.measurements) },
            onEdit: openTrackedMetricsSettings
        ) {
            let ids = dashboardKeyIdentifiers
            let defMap = customDefinitionsMap
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(ids, id: \.self) { id in
                        keyMetricTile(for: id, definitions: defMap)
                            .containerRelativeFrame(.horizontal, count: 2, spacing: 12)
                            .frame(minWidth: 156, maxWidth: 188)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    @ViewBuilder
    private func keyMetricTile(
        for id: String,
        definitions: [String: CustomMetricDefinition]
    ) -> some View {
        if let kind = MetricKind(rawValue: id) {
            NavigationLink {
                MetricDetailView(kind: kind)
            } label: {
                HomeKeyMetricTile(
                    title: kind.title,
                    valueText: cachedLatestByKind[kind].map { formattedMetricValue(for: kind, metricValue: $0.value) },
                    deltaChip: metricDeltaChip(for: kind, days: 30),
                    goalProgress: keyMetricGoalProgress(for: kind),
                    samples: samplesForKind(kind),
                    trendKind: kind,
                    goal: cachedGoalsByKind[kind]
                )
            }
            .buttonStyle(PressableTileStyle())
            .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
        } else if let definition = definitions[id] {
            NavigationLink {
                CustomMetricDetailView(definition: definition)
            } label: {
                HomeCustomKeyMetricTile(
                    definition: definition,
                    latest: cachedCustomLatestByIdentifier[id],
                    deltaChip: customMetricDeltaChip(for: definition, days: 30),
                    goalProgress: customKeyMetricGoalProgress(for: definition),
                    samples: cachedCustomSamplesByIdentifier[id] ?? [],
                    goal: cachedCustomGoalsByIdentifier[id]
                )
            }
            .buttonStyle(PressableTileStyle())
        }
    }

    private func openTrackedMetricsSettings() {
        Haptics.selection()
        settingsOpenTrackedMeasurements = true
        router.selectedTab = .settings
    }

    private var homeHeaderDateText: String {
        AppClock.now
            .formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            .uppercased(with: AppLocalization.currentLanguage.locale)
    }

    private var homeAvatarText: String {
        guard let first = trimmedUserName.first else { return "M" }
        return String(first).uppercased(with: AppLocalization.currentLanguage.locale)
    }

    private var homeAIInsights: [HomeAIInsightItem] {
        var items: [HomeAIInsightItem] = []

        for kind in dashboardVisibleMetrics {
            guard let delta = metricDeltaChip(for: kind, days: 30) else { continue }
            let tone = homeInsightTone(for: kind)
            items.append(
                HomeAIInsightItem(
                    symbol: tone == .positive ? "arrow.down.right" : "arrow.up.right",
                    text: FlowLocalization.app(
                        "\(kind.title): \(delta.text) in 30 days.",
                        "\(kind.title): \(delta.text) w 30 dni.",
                        "\(kind.title): \(delta.text) en 30 dias.",
                        "\(kind.title): \(delta.text) in 30 Tagen.",
                        "\(kind.title) : \(delta.text) en 30 jours.",
                        "\(kind.title): \(delta.text) em 30 dias."
                    ),
                    tone: tone
                )
            )
            if items.count == 2 { break }
        }

        if hasEnoughSavedPhotosForCompare, let latestSavedPhoto, let secondLatestSavedPhoto {
            let days = max(Calendar.current.dateComponents([.day], from: secondLatestSavedPhoto.date, to: latestSavedPhoto.date).day ?? 0, 0)
            items.append(
                HomeAIInsightItem(
                    symbol: "camera.viewfinder",
                    text: FlowLocalization.app(
                        "Progress photos are ready for a \(days)-day comparison.",
                        "Zdjecia postepu sa gotowe do porownania z \(days) dni.",
                        "Las fotos de progreso estan listas para comparar \(days) dias.",
                        "Fortschrittsfotos sind bereit fur einen \(days)-Tage-Vergleich.",
                        "Les photos de progression sont pretes pour \(days) jours de comparaison.",
                        "Fotos de progresso prontas para comparar \(days) dias."
                    ),
                    tone: .neutral
                )
            )
        }

        if items.isEmpty {
            items.append(
                HomeAIInsightItem(
                    symbol: "plus.circle",
                    text: FlowLocalization.app(
                        "Add a few measurements to unlock sharper trend summaries.",
                        "Dodaj kilka pomiarow, aby zobaczyc trafniejsze podsumowania trendow.",
                        "Agrega algunas mediciones para ver resumenes mas claros.",
                        "Fuge ein paar Messungen hinzu, um klarere Trends zu sehen.",
                        "Ajoutez quelques mesures pour des tendances plus nettes.",
                        "Adicione algumas medidas para ver tendencias mais claras."
                    ),
                    tone: .neutral
                )
            )
        }

        return Array(items.prefix(3))
    }

    private var homeAIAnalysisItems: [HomeAIAnalysisItem] {
        var items: [HomeAIAnalysisItem] = []

        if let strongest = strongestPositiveAnalysisItem {
            items.append(strongest)
        }

        if let composition = compositionAnalysisItem {
            items.append(composition)
        }

        items.append(consistencyAnalysisItem)

        if let risk = riskAnalysisItem {
            items.append(risk)
        }

        if let pace = paceOrGoalAnalysisItem {
            items.append(pace)
        }

        return HomeAIAnalysisItemsPolicy.visibleItems(primary: items, fallback: fallbackAnalysisItems)
    }

    private var strongestPositiveAnalysisItem: HomeAIAnalysisItem? {
        let candidates = dashboardVisibleMetrics.compactMap { kind -> (HomeAIAnalysisItem, Double)? in
            guard let window = trendWindowSamples(for: kind, days: 30) ?? trendWindowSamples(for: kind, days: 7) else { return nil }
            guard kind.trendOutcome(from: window.oldest.value, to: window.newest.value, goal: cachedGoalsByKind[kind]) == .positive else { return nil }
            let newest = kind.valueForDisplay(fromMetric: window.newest.value, unitsSystem: unitsSystem)
            let oldest = kind.valueForDisplay(fromMetric: window.oldest.value, unitsSystem: unitsSystem)
            let delta = newest - oldest
            let absoluteDelta = abs(delta)
            guard absoluteDelta >= minimumInsightDelta(for: kind) else { return nil }
            let deltaText = kind.formattedDisplayValue(absoluteDelta, unitsSystem: unitsSystem)
            let signedDelta = delta >= 0 ? "+\(deltaText)" : "-\(deltaText)"
            return (
                HomeAIAnalysisItem(
                    symbol: delta >= 0 ? "arrow.up.right" : "arrow.down.right",
                    title: "\(kind.title) \(signedDelta)",
                    detail: FlowLocalization.app(
                        "Your strongest 30-day signal. Keep the same logging rhythm to confirm the trend.",
                        "Najmocniejszy sygnał z 30 dni. Utrzymaj rytm zapisów, żeby potwierdzić trend.",
                        "Tu señal más fuerte de 30 días. Mantén el ritmo de registro para confirmar la tendencia.",
                        "Dein stärkstes 30-Tage-Signal. Behalte den Rhythmus bei, um den Trend zu bestätigen.",
                        "Votre signal le plus net sur 30 jours. Gardez le même rythme pour confirmer la tendance.",
                        "Seu sinal mais forte em 30 dias. Mantenha o ritmo de registros para confirmar a tendência."
                    ),
                    tone: .positive
                ),
                absoluteDelta / minimumInsightDelta(for: kind)
            )
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    private var compositionAnalysisItem: HomeAIAnalysisItem? {
        if let leanDelta = metricDeltaChip(for: .leanBodyMass, days: 30),
           let weightDelta = metricDeltaChip(for: .weight, days: 30) {
            return HomeAIAnalysisItem(
                symbol: "figure.strengthtraining.traditional",
                title: FlowLocalization.app(
                    "Composition: lean mass \(leanDelta.text)",
                    "Kompozycja: masa beztłuszczowa \(leanDelta.text)",
                    "Composición: masa magra \(leanDelta.text)",
                    "Komposition: fettfreie Masse \(leanDelta.text)",
                    "Composition : masse maigre \(leanDelta.text)",
                    "Composição: massa magra \(leanDelta.text)"
                ),
                detail: FlowLocalization.app(
                    "Weight moved \(weightDelta.text) in the same window, so composition matters more than scale alone.",
                    "Waga zmieniła się o \(weightDelta.text) w tym samym okresie, więc skład ciała mówi więcej niż sama waga.",
                    "El peso cambió \(weightDelta.text) en el mismo período; la composición importa más que la báscula.",
                    "Das Gewicht änderte sich im selben Zeitraum um \(weightDelta.text); die Zusammensetzung zählt mehr.",
                    "Le poids a changé de \(weightDelta.text) sur la même période ; la composition compte plus que la balance.",
                    "O peso mudou \(weightDelta.text) no mesmo período; composição vale mais que a balança."
                ),
                tone: .positive
            )
        }

        if let bodyFatDelta = metricDeltaChip(for: .bodyFat, days: 30) {
            return HomeAIAnalysisItem(
                symbol: "percent",
                title: "\(MetricKind.bodyFat.title) \(bodyFatDelta.text)",
                detail: FlowLocalization.app(
                    "Body fat trend is the clearest composition signal available right now.",
                    "Trend tkanki tłuszczowej to teraz najczytelniejszy sygnał kompozycji.",
                    "La tendencia de grasa corporal es la señal de composición más clara ahora.",
                    "Der Körperfetttrend ist derzeit das klarste Kompositionssignal.",
                    "La tendance de masse grasse est le signal de composition le plus lisible.",
                    "A tendência de gordura corporal é o sinal de composição mais claro agora."
                ),
                tone: homeInsightTone(for: .bodyFat)
            )
        }

        return nil
    }

    private var consistencyAnalysisItem: HomeAIAnalysisItem {
        let streak = streakManager.currentStreak
        if streak > 0 {
            return HomeAIAnalysisItem(
                symbol: "bolt.fill",
                title: FlowLocalization.app(
                    "\(streak)-day streak",
                    "\(streak)-dniowa seria",
                    "Racha de \(streak) días",
                    "\(streak)-Tage-Serie",
                    "Série de \(streak) jours",
                    "Sequência de \(streak) dias"
                ),
                detail: FlowLocalization.app(
                    "Daily logging improves goal accuracy and makes trend shifts easier to spot.",
                    "Codzienne zapisy poprawiają trafność celów i ułatwiają wychwycenie zmian trendu.",
                    "Registrar a diario mejora la precisión de objetivos y revela cambios de tendencia.",
                    "Tägliche Einträge verbessern Zielgenauigkeit und machen Trendwechsel sichtbarer.",
                    "Les entrées quotidiennes améliorent la précision des objectifs et révèlent les changements.",
                    "Registros diários melhoram a precisão das metas e revelam mudanças de tendência."
                ),
                tone: .neutral
            )
        }

        return HomeAIAnalysisItem(
            symbol: "calendar.badge.clock",
            title: FlowLocalization.app(
                "\(currentWeekCheckInDays) check-ins this week",
                "\(currentWeekCheckInDays) zapisy w tym tygodniu",
                "\(currentWeekCheckInDays) registros esta semana",
                "\(currentWeekCheckInDays) Einträge diese Woche",
                "\(currentWeekCheckInDays) suivis cette semaine",
                "\(currentWeekCheckInDays) registros nesta semana"
            ),
            detail: FlowLocalization.app(
                "Three or more check-ins per week gives AI a cleaner trend baseline.",
                "Trzy lub więcej zapisów tygodniowo daje AI czystszą bazę trendu.",
                "Tres o más registros por semana dan una base de tendencia más clara.",
                "Drei oder mehr Einträge pro Woche geben eine bessere Trendbasis.",
                "Trois suivis ou plus par semaine donnent une base de tendance plus nette.",
                "Três ou mais registros por semana dão uma base de tendência melhor."
            ),
            tone: currentWeekCheckInDays >= 3 ? .positive : .neutral
        )
    }

    private var riskAnalysisItem: HomeAIAnalysisItem? {
        let height = manualHeight > 0 ? manualHeight : latestHeight
        if let bmi = HealthMetricsCalculator.calculateBMI(weightKg: latestWeight, heightCm: height, age: userAge) {
            let isWarning = bmi.bmi >= 25 || bmi.bmi < 18.5
            return HomeAIAnalysisItem(
                symbol: isWarning ? "exclamationmark.triangle" : "heart.fill",
                title: String(format: "BMI %.1f", bmi.bmi),
                detail: isWarning
                    ? FlowLocalization.app(
                        "Slightly outside the typical range. Waist and composition trends are more useful than BMI alone.",
                        "Lekko poza typowym zakresem. Trend talii i kompozycji jest ważniejszy niż samo BMI.",
                        "Algo fuera del rango típico. Cintura y composición importan más que el BMI solo.",
                        "Etwas außerhalb des typischen Bereichs. Taille und Komposition zählen mehr als BMI allein.",
                        "Légèrement hors de la plage typique. Taille et composition comptent plus que l'IMC seul.",
                        "Um pouco fora da faixa típica. Cintura e composição importam mais que o BMI isolado."
                    )
                    : FlowLocalization.app(
                        "Within the typical range. Keep watching waist and body composition trends.",
                        "W typowym zakresie. Nadal obserwuj talię i kompozycję ciała.",
                        "Dentro del rango típico. Sigue observando cintura y composición.",
                        "Im typischen Bereich. Beobachte weiter Taille und Komposition.",
                        "Dans la plage typique. Continuez à suivre taille et composition.",
                        "Dentro da faixa típica. Continue observando cintura e composição."
                    ),
                tone: isWarning ? .warning : .positive
            )
        }

        if let whtr = HealthMetricsCalculator.calculateWHtR(waistCm: latestWaist, heightCm: height) {
            let isWarning = whtr.ratio >= 0.5
            return HomeAIAnalysisItem(
                symbol: isWarning ? "exclamationmark.triangle" : "heart.fill",
                title: String(format: "WHtR %.2f", whtr.ratio),
                detail: isWarning
                    ? FlowLocalization.app(
                        "Waist-to-height ratio is above the main threshold; waist trend deserves priority.",
                        "Stosunek talii do wzrostu jest powyżej progu; trend talii ma priorytet.",
                        "La relación cintura-altura supera el umbral; prioriza la cintura.",
                        "Taille-Größe-Verhältnis liegt über dem Schwellenwert; priorisiere Taille.",
                        "Le ratio taille/taille dépasse le seuil ; priorisez le tour de taille.",
                        "A relação cintura-altura está acima do limite; priorize a cintura."
                    )
                    : FlowLocalization.app(
                        "Waist-to-height ratio is in a healthier zone.",
                        "Stosunek talii do wzrostu jest w zdrowszej strefie.",
                        "La relación cintura-altura está en una zona más saludable.",
                        "Taille-Größe-Verhältnis liegt in einem gesünderen Bereich.",
                        "Le ratio taille/taille est dans une zone plus saine.",
                        "A relação cintura-altura está em uma zona mais saudável."
                    ),
                tone: isWarning ? .warning : .positive
            )
        }

        return nil
    }

    private var paceOrGoalAnalysisItem: HomeAIAnalysisItem? {
        if goalStatus != .noGoals {
            return HomeAIAnalysisItem(
                symbol: "target",
                title: goalStatusText,
                detail: FlowLocalization.app(
                    "Goal status is based on your selected key metrics and latest logged values.",
                    "Status celu bazuje na kluczowych metrykach i najnowszych zapisanych wartościach.",
                    "El estado del objetivo usa tus métricas clave y los valores más recientes.",
                    "Der Zielstatus basiert auf Schlüsselmetriken und neuesten Werten.",
                    "Le statut d'objectif s'appuie sur vos métriques clés et dernières valeurs.",
                    "O status da meta usa suas métricas principais e valores mais recentes."
                ),
                tone: goalStatus == .needsAttention ? .warning : .positive
            )
        }

        if hasEnoughSavedPhotosForCompare, let latestSavedPhoto, let secondLatestSavedPhoto {
            let days = max(Calendar.current.dateComponents([.day], from: secondLatestSavedPhoto.date, to: latestSavedPhoto.date).day ?? 0, 0)
            return HomeAIAnalysisItem(
                symbol: "camera.viewfinder",
                title: FlowLocalization.app(
                    "\(days)-day photo comparison",
                    "Porównanie zdjęć: \(days) dni",
                    "Comparación de \(days) días",
                    "\(days)-Tage-Fotovergleich",
                    "Comparaison photo de \(days) jours",
                    "Comparação de fotos: \(days) dias"
                ),
                detail: FlowLocalization.app(
                    "Your photos are ready for a visual check against the metric trend.",
                    "Zdjęcia są gotowe do wizualnego porównania z trendem metryk.",
                    "Tus fotos están listas para revisar contra la tendencia.",
                    "Deine Fotos sind bereit für den Abgleich mit dem Trend.",
                    "Vos photos sont prêtes pour une comparaison avec les tendances.",
                    "Suas fotos estão prontas para comparação com a tendência."
                ),
                tone: .neutral
            )
        }

        return nil
    }

    private var fallbackAnalysisItems: [HomeAIAnalysisItem] {
        [
            HomeAIAnalysisItem(
                symbol: "plus.circle",
                title: FlowLocalization.app("Add 3 measurements", "Dodaj 3 pomiary", "Añade 3 medidas", "Füge 3 Messungen hinzu", "Ajoutez 3 mesures", "Adicione 3 medições"),
                detail: FlowLocalization.app(
                    "AI needs a short history before it can rank your strongest trends.",
                    "AI potrzebuje krótkiej historii, żeby ocenić najmocniejsze trendy.",
                    "La IA necesita historial para clasificar tus tendencias.",
                    "KI braucht eine kurze Historie, um Trends zu bewerten.",
                    "L'IA a besoin d'un historique court pour classer les tendances.",
                    "A IA precisa de histórico para classificar tendências."
                ),
                tone: .neutral
            ),
            HomeAIAnalysisItem(
                symbol: "camera.fill",
                title: FlowLocalization.app("Add progress photos", "Dodaj zdjęcia postępu", "Añade fotos de progreso", "Füge Fortschrittsfotos hinzu", "Ajoutez des photos", "Adicione fotos de progresso"),
                detail: FlowLocalization.app(
                    "Two photos at least a few weeks apart make visual progress easier to validate.",
                    "Dwa zdjęcia w odstępie kilku tygodni ułatwią ocenę wizualnego postępu.",
                    "Dos fotos separadas por semanas facilitan validar el progreso visual.",
                    "Zwei Fotos mit ein paar Wochen Abstand helfen beim visuellen Vergleich.",
                    "Deux photos espacées de quelques semaines facilitent la validation.",
                    "Duas fotos com semanas de diferença ajudam a validar progresso visual."
                ),
                tone: .neutral
            )
        ]
    }

    private func homeInsightTone(for kind: MetricKind) -> HomeAIInsightItem.Tone {
        guard let window = trendWindowSamples(for: kind, days: 30) ?? trendWindowSamples(for: kind, days: 7) else {
            return .neutral
        }
        switch kind.trendOutcome(from: window.oldest.value, to: window.newest.value, goal: cachedGoalsByKind[kind]) {
        case .positive:
            return .positive
        case .negative:
            return .warning
        case .neutral:
            return .neutral
        }
    }

    private func keyMetricGoalProgress(for kind: MetricKind) -> HomeKeyMetricGoalProgress? {
        guard let goal = cachedGoalsByKind[kind],
              let latest = cachedLatestByKind[kind] else { return nil }
        let baseline = baselineValue(for: kind, goal: goal)
        return HomeKeyMetricGoalProgress(
            progress: goalProgressValue(goal: goal, latestValue: latest.value, baselineValue: baseline),
            label: secondaryMetricGoalSummary(for: kind) ?? AppLocalization.string("Progress")
        )
    }

    private func customKeyMetricGoalProgress(for definition: CustomMetricDefinition) -> HomeKeyMetricGoalProgress? {
        guard let goal = cachedCustomGoalsByIdentifier[definition.identifier],
              let latest = cachedCustomLatestByIdentifier[definition.identifier] else { return nil }
        let samples = cachedCustomSamplesByIdentifier[definition.identifier] ?? []
        let baseline: Double
        if let startValue = goal.startValue {
            baseline = startValue
        } else {
            let sorted = samples.sorted { $0.date < $1.date }
            let anchorDate = goal.startDate ?? goal.createdDate
            baseline = sorted.last(where: { $0.date <= anchorDate })?.value
                ?? sorted.first?.value
                ?? latest.value
        }
        return HomeKeyMetricGoalProgress(
            progress: goalProgressValue(goal: goal, latestValue: latest.value, baselineValue: baseline),
            label: AppLocalization.string("Progress")
        )
    }

    private func goalProgressValue(goal: MetricGoal, latestValue: Double, baselineValue: Double) -> Double {
        switch goal.direction {
        case .increase:
            let denominator = goal.targetValue - baselineValue
            guard denominator > 0 else { return 0 }
            return min(max((latestValue - baselineValue) / denominator, 0), 1)
        case .decrease:
            let denominator = baselineValue - goal.targetValue
            guard denominator > 0 else { return 0 }
            return min(max((baselineValue - latestValue) / denominator, 0), 1)
        }
    }

    private func baselineValue(for kind: MetricKind, goal: MetricGoal) -> Double {
        if let startValue = goal.startValue { return startValue }
        let sorted = samplesForKind(kind).sorted { $0.date < $1.date }
        let anchorDate = goal.startDate ?? goal.createdDate
        return sorted.last(where: { $0.date <= anchorDate })?.value
            ?? sorted.first?.value
            ?? cachedLatestByKind[kind]?.value
            ?? goal.targetValue
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
        HomeRecentPhotosCard(
            snapshot: HomeRecentPhotosSnapshot(
                subtitle: recentPhotosSubtitle,
                contextPrimary: recentPhotosContextPrimary,
                contextSecondary: recentPhotosContextSecondary,
                insightTitle: recentPhotosInsightTitle,
                insightDetail: recentPhotosInsightDetail,
                insightNote: recentPhotosInsightNote,
                hasEnoughSavedPhotosForCompare: hasEnoughSavedPhotosForCompare,
                tileCount: dashboardRecentPhotoTiles.count
            ),
            tiles: dashboardRecentPhotoTileViewModels,
            onOpenPhotos: { router.selectTab(.photos) },
            onOpenPhoto: { photo in selectedPhotoForFullScreen = photo },
            onCompare: handleRecentPhotosCompareTap
        )
    }

    private var recentPhotosEmptyModule: some View {
        HomeRecentPhotosEmptyCard {
            router.selectTab(.photos)
        }
    }

    private var healthSummaryModule: some View {
        Group {
            if isHealthSectionMounted {
                HomeHealthSummaryCard(
                    snapshot: HomeHealthSummarySnapshot(
                        subtitle: healthModuleSubtitle,
                        pillText: healthModulePillText,
                        emptyTitle: healthEmptyStateTitle,
                        emptyDetail: healthEmptyStateDetail,
                        emptyCTA: healthEmptyStateCTA,
                        summaryTitle: homeHealthSummaryTitle,
                        summaryDetail: homeHealthSummaryDetail,
                        isPremium: premiumStore.isPremium,
                        isSyncEnabled: isSyncEnabled
                    ),
                    items: homeHealthStatItemViewModels,
                    previewItems: visibleHomeHealthStatItemViewModels,
                    onConnectHealth: connectHealthKitFromChecklist,
                    onOpenSettings: { router.selectTab(.settings) },
                    onOpenHealth: { router.openMeasurementsSection("health") },
                    onOpenPremium: {
                        Haptics.selection()
                        premiumStore.presentPaywall(reason: .feature("Health Summary & Physique"))
                    }
                )
            } else {
                healthSectionPlaceholder
            }
        }
    }

    private var activationHubModule: some View {
        HomeActivationCard(
            snapshot: HomeActivationSnapshot(
                stepIndex: activationStepIndex,
                totalSteps: activationTaskSequence.count,
                title: OnboardingCopy.activationTaskTitle(activationCurrentTask ?? .initial),
                body: OnboardingCopy.activationTaskBody(
                    activationCurrentTask ?? .initial,
                    metricName: activationPrimaryMetric?.title
                ),
                primaryCTA: OnboardingCopy.activationPrimaryCTA(activationCurrentTask ?? .initial),
                skipCTA: OnboardingCopy.activationSkipCTA,
                dismissCTA: OnboardingCopy.activationDismissCTA
            ),
            onPrimary: performActivationPrimaryAction,
            onSkip: skipActivationTask,
            onDismiss: dismissActivationHub
        )
    }

    private var checklistModule: some View {
        HomeChecklistCard(
            snapshot: HomeChecklistSnapshot(
                activeCount: activeChecklistItems.count,
                isCollapsed: onboardingChecklistCollapsed,
                showMoreVisible: !showMoreChecklistItems && activeChecklistItems.count > collapsedChecklistItems.count,
                remainingCount: max(activeChecklistItems.count - collapsedChecklistItems.count, 0),
                statusText: checklistStatusText
            ),
            items: shownChecklistItems.map {
                HomeChecklistItemViewModel(
                    id: $0.id,
                    title: $0.title,
                    detail: $0.detail,
                    icon: $0.icon
                )
            },
            iconSurface: checklistIconSurface,
            rowFill: neutralRowFill,
            rowStroke: neutralRowStroke,
            onHide: {
                Haptics.selection()
                showOnboardingChecklistOnHome = false
                settingsStore.setHomeModuleVisibility(false, for: .setupChecklist)
            },
            onToggleCollapse: {
                Haptics.selection()
                onboardingChecklistCollapsed.toggle()
            },
            onItemTap: performChecklistAction,
            onShowMore: {
                Haptics.selection()
                showMoreChecklistItems = true
            }
        )
    }

    private var activationCurrentTask: ActivationTask? {
        guard onboardingFlowVersion >= 2 else { return nil }
        guard !activationCurrentTaskID.isEmpty else { return nil }
        if let task = ActivationTask(rawValue: activationCurrentTaskID) {
            return task
        }
        if ["addMetric", "premium", "celebrate"].contains(activationCurrentTaskID) {
            return .initial
        }
        return nil
    }

    private var activationTaskSequence: [ActivationTask] {
        var sequence: [ActivationTask] = [.firstMeasurement, .addPhoto, .chooseMetrics, .setGoal, .setReminders, .explorePremium]
        if premiumStore.isPremium {
            sequence.removeAll { $0 == .explorePremium }
        }
        return sequence
    }

    private var activationCompletedTaskIDs: Set<String> {
        activationIDSet(from: activationCompletedTaskIDsRaw)
    }

    private var activationSkippedTaskIDs: Set<String> {
        activationIDSet(from: activationSkippedTaskIDsRaw)
    }

    private var activationRecommendedKinds: [MetricKind] {
        GoalMetricPack.recommendedKinds(for: resolvedOnboardingPriority)
    }

    private var activationPrimaryMetric: MetricKind? {
        activationRecommendedKinds.first
    }

    private var showActivationHub: Bool {
        let isEnabledInLayout = settingsStore.homeLayoutSnapshot().item(for: .activationHub)?.isVisible ?? true
        let isActivationHubUITest = isUITestMode && UITestArgument.isPresent(.activationHub)
        let isActivationDismissed = activationIsDismissed && !isActivationHubUITest
        return onboardingFlowVersion >= 2
            && (isEnabledInLayout || isActivationHubUITest)
            && !isActivationDismissed
            && activationCurrentTask != nil
    }

    private var activationStepIndex: Int {
        guard let activationCurrentTask,
              let index = activationTaskSequence.firstIndex(of: activationCurrentTask) else {
            return activationTaskSequence.count
        }
        return index + 1
    }

    private var resolvedOnboardingPriority: OnboardingPriority {
        OnboardingPriority(rawValue: onboardingPrimaryGoalsRaw) ?? .improveHealth
    }

    private var goalStatusColor: Color {
        switch goalStatus {
        case .onTrack:
            return AppColorRoles.stateSuccess
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
        cachedNextFocusInsight ?? fallbackNextFocusInsight
    }

    private var heroPrimaryMeasurement: HomeHeroMeasurementSnapshot? {
        guard hasAnyMeasurements else {
            return nil
        }

        let selectedPair: (kind: MetricKind, sample: MetricSample)?
        if let keyKind = dashboardVisibleMetrics.first,
           let keySample = cachedLatestByKind[keyKind] {
            selectedPair = (keyKind, keySample)
        } else if let fallbackSample = recentSamples.first,
                  let fallbackKind = MetricKind(rawValue: fallbackSample.kindRaw) {
            selectedPair = (fallbackKind, fallbackSample)
        } else {
            selectedPair = nil
        }

        guard let selectedPair else {
            return nil
        }

        let kind = selectedPair.kind
        let sample = selectedPair.sample
        let value = kind.formattedMetricValue(fromMetric: sample.value, unitsSystem: unitsSystem)
        let label = kind.title
        let detail = metricDeltaTextFromCache(kind: kind, days: 7)
            ?? secondaryMetricGoalSummary(for: kind)
            ?? AppLocalization.string("home.keymetrics.delta.empty")

        return HomeHeroMeasurementSnapshot(
            label: label,
            value: value,
            detail: detail
        )
    }

    private var fallbackNextFocusInsight: HomeNextFocusInsight {
        HomeNextFocusInsight(
            headline: AppLocalization.string("Set goal"),
            primaryValue: nil,
            supportingLabel: nil,
            contextLabel: FlowLocalization.app("Setup", "Konfiguracja", "Configurar", "Einrichtung", "Configuration", "Configuração"),
            summary: AppLocalization.string("home.nextfocus.fallback.summary"),
            cta: AppLocalization.string("home.nextfocus.cta.goal"),
            action: .measurements,
            accessibilityValue: "setGoal"
        )
    }

    private func computeNextFocusInsight() -> HomeNextFocusInsight {
        if isUITestMode && UITestArgument.isPresent(.longNextFocusInsight) {
            return HomeNextFocusInsight(
                headline: nil,
                primaryValue: AppLocalization.string("home.nextfocus.uitest.long.primary"),
                supportingLabel: AppLocalization.string("home.nextfocus.uitest.long.supporting"),
                contextLabel: FlowLocalization.app("30 days", "30 dni", "30 días", "30 Tage", "30 jours", "30 dias"),
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

        return fallbackNextFocusInsight
    }

    // MARK: - Living Pulse Hero Signal

    private func computeHeroPulseSignal() -> HeroPulseSignal {
        let streak = streakManager.currentStreak
        let milestoneThresholds: Set<Int> = [3, 7, 14, 30, 60, 100, 200]
        let now = AppClock.now
        let calendar = Calendar.current
        let lastSampleDate = recentSamples.first?.date
        let daysSinceLastSample: Int? = lastSampleDate.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day
        }

        // 1. Fresh state: no samples yet.
        if !hasAnyMeasurements {
            return HeroPulseSignal(
                kind: .fresh,
                icon: "sparkles",
                title: FlowLocalization.app(
                    "Small steps still count.",
                    "Małe kroki też się liczą.",
                    "Los pequeños pasos cuentan.",
                    "Auch kleine Schritte zählen.",
                    "Les petits pas comptent.",
                    "Pequenos passos também contam."
                ),
                subtitle: FlowLocalization.app(
                    "Log your first measurement to start.",
                    "Dodaj pierwszy pomiar, żeby zacząć.",
                    "Registra tu primera medida para empezar.",
                    "Erfasse deine erste Messung, um zu starten.",
                    "Enregistre ta première mesure pour commencer.",
                    "Registe a primeira medida para começar."
                ),
                tint: .accent,
                useStreakBadge: false,
                streakCount: 0,
                animateStreak: false,
                action: .quickAdd
            )
        }

        // 2. Streak milestone — shouldPlayAnimation OR hit a milestone threshold.
        if streak > 0 && (streakManager.shouldPlayAnimation || milestoneThresholds.contains(streak)) {
            return HeroPulseSignal(
                kind: .streakMilestone,
                icon: "flame.fill",
                title: FlowLocalization.app(
                    "\(streak)-week streak!",
                    "\(streak) tygodni z rzędu!",
                    "¡Racha de \(streak) semanas!",
                    "\(streak) Wochen in Folge!",
                    "Série de \(streak) semaines !",
                    "Sequência de \(streak) semanas!"
                ),
                subtitle: FlowLocalization.app(
                    "Keep the momentum going.",
                    "Utrzymaj tempo.",
                    "Mantén el impulso.",
                    "Behalte den Schwung.",
                    "Garde le rythme.",
                    "Mantém o ritmo."
                ),
                tint: .accent,
                useStreakBadge: true,
                streakCount: streak,
                animateStreak: streakManager.shouldPlayAnimation,
                action: .streakDetail
            )
        }

        // 3. Streak risk — active streak but no log in 4+ days (approaching end of week).
        if streak >= 1, let days = daysSinceLastSample, days >= 4 {
            return HeroPulseSignal(
                kind: .streakRisk,
                icon: "flame.fill",
                title: FlowLocalization.app(
                    "\(streak)-week streak at risk",
                    "Seria \(streak) tygodni zagrożona",
                    "Racha de \(streak) semanas en riesgo",
                    "\(streak)-Wochen-Serie in Gefahr",
                    "Série de \(streak) semaines en danger",
                    "Sequência de \(streak) semanas em risco"
                ),
                subtitle: FlowLocalization.app(
                    "Log this week to keep it alive.",
                    "Dodaj pomiar w tym tygodniu, żeby ją utrzymać.",
                    "Registra esta semana para mantenerla.",
                    "Trage diese Woche etwas ein, um sie zu halten.",
                    "Enregistre cette semaine pour la garder.",
                    "Regista esta semana para a manteres."
                ),
                tint: .warning,
                useStreakBadge: true,
                streakCount: streak,
                animateStreak: false,
                action: .quickAdd
            )
        }

        // 4. Goal near complete — best non-achieved goal at >= 75%.
        if let (kind, progress) = mostProgressedGoalForPulse(), progress >= 0.75 {
            let pct = Int((progress * 100).rounded())
            return HeroPulseSignal(
                kind: .goalNearComplete,
                icon: "target",
                title: FlowLocalization.app(
                    "\(pct)% to your \(kind.title.lowercased()) goal",
                    "\(pct)% do celu: \(kind.title.lowercased())",
                    "\(pct)% hacia tu meta de \(kind.title.lowercased())",
                    "\(pct)% zum \(kind.title)-Ziel",
                    "\(pct)% vers ton objectif \(kind.title.lowercased())",
                    "\(pct)% da meta de \(kind.title.lowercased())"
                ),
                subtitle: FlowLocalization.app(
                    "Almost there — keep going.",
                    "Już blisko — trzymaj kurs.",
                    "Casi lo logras — sigue así.",
                    "Fast geschafft — weiter so.",
                    "Presque fini — continue.",
                    "Quase lá — continua."
                ),
                tint: .success,
                useStreakBadge: false,
                streakCount: 0,
                animateStreak: false,
                action: .metricDetail(kind)
            )
        }

        // 5. Return nudge — > 7 days since last sample.
        if let days = daysSinceLastSample, days >= 7 {
            return HeroPulseSignal(
                kind: .returnNudge,
                icon: "clock.arrow.circlepath",
                title: FlowLocalization.app(
                    "\(days) days since last check-in",
                    "\(days) dni od ostatniego pomiaru",
                    "\(days) días desde el último registro",
                    "\(days) Tage seit deiner letzten Messung",
                    "\(days) jours depuis ta dernière mesure",
                    "\(days) dias desde o último registo"
                ),
                subtitle: FlowLocalization.app(
                    "A quick log keeps your trends fresh.",
                    "Szybki pomiar odświeży Twoje trendy.",
                    "Un registro rápido mantiene tus tendencias al día.",
                    "Ein kurzer Eintrag hält deine Trends aktuell.",
                    "Une mesure rapide garde tes tendances à jour.",
                    "Um registo rápido mantém as tendências em dia."
                ),
                tint: .neutral,
                useStreakBadge: false,
                streakCount: 0,
                animateStreak: false,
                action: .quickAdd
            )
        }

        // 6. Trend highlight — use next-focus insight when it surfaces a real trend.
        let insight = nextFocusInsight
        if insight.primaryValue != nil, case .metric(let kind) = insight.action {
            let detail = [insight.primaryValue, insight.supportingLabel].compactMap { $0 }.joined(separator: " · ")
            return HeroPulseSignal(
                kind: .trendHighlight,
                icon: "chart.line.uptrend.xyaxis",
                title: insight.summary,
                subtitle: detail.isEmpty ? insight.contextLabel : detail,
                tint: .success,
                useStreakBadge: false,
                streakCount: 0,
                animateStreak: false,
                action: .metricDetail(kind)
            )
        }

        // 7. Streak active (idle).
        if streak >= 1 {
            return HeroPulseSignal(
                kind: .streakActive,
                icon: "flame.fill",
                title: FlowLocalization.app(
                    "\(streak)-week streak",
                    "\(streak) tygodni z rzędu",
                    "Racha de \(streak) semanas",
                    "\(streak)-Wochen-Serie",
                    "Série de \(streak) semaines",
                    "Sequência de \(streak) semanas"
                ),
                subtitle: FlowLocalization.app(
                    "Keep it going this week.",
                    "Utrzymaj ją w tym tygodniu.",
                    "Mantenla esta semana.",
                    "Halte sie diese Woche aufrecht.",
                    "Garde-la cette semaine.",
                    "Mantém-na esta semana."
                ),
                tint: .accent,
                useStreakBadge: true,
                streakCount: streak,
                animateStreak: false,
                action: .streakDetail
            )
        }

        // 8. Generic fallback — has data, no streak, no trend, no nudge.
        return HeroPulseSignal(
            kind: .fresh,
            icon: "sparkles",
            title: FlowLocalization.app(
                "Small steps still count.",
                "Małe kroki też się liczą.",
                "Los pequeños pasos cuentan.",
                "Auch kleine Schritte zählen.",
                "Les petits pas comptent.",
                "Pequenos passos também contam."
            ),
            subtitle: FlowLocalization.app(
                "Log today to build momentum.",
                "Dodaj pomiar, żeby zbudować tempo.",
                "Registra hoy para ganar impulso.",
                "Trage heute etwas ein, um Schwung aufzubauen.",
                "Enregistre aujourd'hui pour prendre de l'élan.",
                "Regista hoje para ganhar ritmo."
            ),
            tint: .accent,
            useStreakBadge: false,
            streakCount: 0,
            animateStreak: false,
            action: .quickAdd
        )
    }

    private func mostProgressedGoalForPulse() -> (MetricKind, Double)? {
        var best: (kind: MetricKind, progress: Double)?
        for (kind, goal) in cachedGoalsByKind {
            guard let latest = cachedLatestByKind[kind] else { continue }
            guard !goal.isAchieved(currentValue: latest.value) else { continue }
            let baseline = goalBaselineValue(for: kind, goal: goal)
            let fullDistance = abs(goal.targetValue - baseline)
            guard fullDistance > 0.0001 else { continue }
            let remaining = abs(goal.remainingToGoal(currentValue: latest.value))
            let progress = max(0, min(1, 1 - (remaining / fullDistance)))
            if best == nil || progress > best!.progress {
                best = (kind, progress)
            }
        }
        return best.map { ($0.kind, $0.progress) }
    }

    private func handlePulseAction(_ action: HeroPulseAction) {
        Haptics.selection()
        switch action {
        case .streakDetail:
            showStreakDetail = true
        case .quickAdd:
            showQuickAddSheet = true
        case .metricDetail:
            // Navigate to measurements tab; in-app navigation to specific metric
            // uses the existing measurements tab which lists all metrics.
            router.selectedTab = .measurements
        case .measurementsTab:
            router.selectedTab = .measurements
        case .none:
            break
        }
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
                contextLabel: FlowLocalization.app("Goal", "Cel", "Meta", "Ziel", "Objectif", "Meta"),
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
        let deltaText = kind.formattedDisplayValue(absoluteDelta, unitsSystem: unitsSystem)
        let periodKey = days >= 30 ? "home.nextfocus.period.30d" : "home.nextfocus.period.7d"
        let periodChipKey = days >= 30 ? "home.nextfocus.periodchip.30d" : "home.nextfocus.periodchip.7d"

        return HomeNextFocusCandidate(
            insight: HomeNextFocusInsight(
                headline: nil,
                primaryValue: delta >= 0 ? "+\(deltaText)" : "-\(deltaText)",
                supportingLabel: nil,
                contextLabel: AppLocalization.string(periodChipKey),
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
            return AppLocalization.plural("home.thisweek.multiple", currentWeekCheckInDays)
        }
    }

    private var summaryThisWeekDetail: String {
        guard latestCheckInThisWeek != nil else {
            return AppLocalization.string("home.thisweek.detail.empty")
        }
        return AppLocalization.string("home.thisweek.detail.logged", latestCheckInWeekday)
    }

    private var keyMetricsSubtitle: String {
        if !hasAnyMeasurements && cachedLatestByKind.isEmpty && cachedCustomLatestByIdentifier.isEmpty {
            return AppLocalization.string("home.keymetrics.empty.subtitle")
        }
        let ids = dashboardKeyIdentifiers
        if ids.isEmpty {
            return AppLocalization.string("home.keymetrics.empty.selection.subtitle")
        }
        return AppLocalization.string("home.keymetrics.ready.subtitle", ids.count)
    }

    private var keyMetricsState: HomeKeyMetricsState {
        if !hasAnyMeasurements && cachedLatestByKind.isEmpty && cachedCustomLatestByIdentifier.isEmpty {
            return .noMeasurements
        }
        if dashboardKeyIdentifiers.isEmpty {
            return .noSelection
        }
        return .content
    }

    private var recentPhotosInsightTitle: String {
        if hasEnoughSavedPhotosForCompare {
            if let secondLatestSavedPhoto {
                return AppLocalization.string(
                    "Latest vs. %@",
                    relativeDescription(since: secondLatestSavedPhoto.date)
                )
            }
            return AppLocalization.string("home.photos.compare.title")
        }
        return AppLocalization.string("home.photos.first.title")
    }

    private var recentPhotosInsightDetail: String {
        if comparePhotosCardDismissed { return "" }
        if hasEnoughSavedPhotosForCompare {
            return AppLocalization.string("home.photos.compare.detail.home")
        }
        return AppLocalization.string("home.photos.first.detail")
    }

    private var recentPhotosInsightNote: String? {
        if comparePhotosCardDismissed { return nil }
        return nil
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
            items.append(HomeHealthStatItem(label: MetricKind.bodyFat.title, value: MetricKind.bodyFat.formattedDisplayValue(latestBodyFat, unitsSystem: unitsSystem)))
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

    private var homeHealthStatItemViewModels: [HomeHealthStatItemViewModel] {
        homeHealthStatItems.map { item in
            HomeHealthStatItemViewModel(label: item.label, value: item.value, badge: item.badge)
        }
    }

    private var visibleHomeHealthStatItemViewModels: [HomeHealthStatItemViewModel] {
        visibleHomeHealthStatItems.map { item in
            HomeHealthStatItemViewModel(label: item.label, value: item.value, badge: item.badge)
        }
    }

    private var homeHealthSummaryTitle: String {
        if let bodyFat = latestBodyFat, bodyFat > 0 {
            return AppLocalization.string("home.health.summary.bodyfat", MetricKind.bodyFat.formattedDisplayValue(bodyFat, unitsSystem: unitsSystem))
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
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(greetingTitle)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(AppColorRoles.textPrimary)

                if hasAnyMeasurements {
                    Text(encouragementText)
                        .font(.subheadline)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                if goalStatus != .noGoals {
                    Text(goalStatusText)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textSecondary)
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

    private var primaryChecklistItem: SetupChecklistItem? {
        activeChecklistItems.first
    }

    private var secondaryChecklistItems: [SetupChecklistItem] {
        guard activeChecklistItems.count > 1 else { return [] }
        return Array(activeChecklistItems.dropFirst())
    }

    private var shownSecondaryChecklistItems: [SetupChecklistItem] {
        showMoreChecklistItems ? secondaryChecklistItems : Array(secondaryChecklistItems.prefix(2))
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
                    Text(AppLocalization.string("Finish setup"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)
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
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AppLocalization.string("accessibility.setup.checklist.options"))
                    .accessibilityHint(AppLocalization.string("accessibility.setup.checklist.options.hint"))
                }

                if onboardingChecklistCollapsed {
                    Text(AppLocalization.string("Checklist collapsed. Open menu to expand."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                } else {
                    // Primary task — large, prominent
                    if let primary = primaryChecklistItem {
                        Button {
                            performChecklistAction(primary.id)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: primary.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.appAccent)
                                    .frame(width: 40, height: 40)
                                    .background(Color.appAccent.opacity(0.16))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(primary.title)
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(AppColorRoles.textPrimary)
                                    Text(primary.detail)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 8)

                                if primary.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.appAccent)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appAccent.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.appAccent.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(primary.isLoading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(primary.title). \(primary.detail)")
                        .accessibilityIdentifier("home.checklist.primary.\(primary.id)")
                        .accessibilityIdentifier("home.checklist.item.\(primary.id)")
                    }

                    // Secondary tasks — subdued
                    if !shownSecondaryChecklistItems.isEmpty {
                        Text(AppLocalization.string("More to set up"))
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(AppColorRoles.textTertiary)
                            .padding(.top, 2)

                        ForEach(shownSecondaryChecklistItems) { item in
                            Button {
                                performChecklistAction(item.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(item.isCompleted ? AppColorRoles.stateSuccess : Color.appAccent)
                                        .frame(width: 26, height: 26)
                                        .background(AppColorRoles.surfaceAccentSoft)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(AppTypography.captionEmphasis)
                                            .foregroundStyle(AppColorRoles.textPrimary)
                                        Text(item.detail)
                                            .font(AppTypography.micro)
                                            .foregroundStyle(AppColorRoles.textSecondary)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 8)

                                    if item.isLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(Color.appAccent)
                                    } else if item.isCompleted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(AppColorRoles.stateSuccess)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(AppColorRoles.textTertiary)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColorRoles.surfacePrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                                )
                                .opacity(0.72)
                            }
                            .buttonStyle(.plain)
                            .disabled(item.isLoading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(item.title). \(item.detail)")
                            .accessibilityIdentifier("home.checklist.item.\(item.id)")
                        }

                        if !showMoreChecklistItems, secondaryChecklistItems.count > 2 {
                            Button {
                                Haptics.selection()
                                showMoreChecklistItems = true
                            } label: {
                                Text(AppLocalization.plural("Show %d more", secondaryChecklistItems.count - 2))
                                    .font(AppTypography.captionEmphasis)
                                    .foregroundStyle(Color.appAccent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 2)
                            }
                            .buttonStyle(.plain)
                        }
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
        if totalMetricSampleCount == 1 && hasAnyMeasurements {
            if name.isEmpty {
                return FlowLocalization.app(
                    "Week 1 - you're on the board.",
                    "Tydzień 1 - jesteś na planszy.",
                    "Semana 1 - ya estás en marcha.",
                    "Woche 1 - du bist dabei.",
                    "Semaine 1 - vous êtes lancé.",
                    "Semana 1 - você começou."
                )
            }
            return FlowLocalization.app(
                "Week 1 - \(name), you're on the board.",
                "Tydzień 1 - \(name), jesteś na planszy.",
                "Semana 1 - \(name), ya estás en marcha.",
                "Woche 1 - \(name), du bist dabei.",
                "Semaine 1 - \(name), vous êtes lancé.",
                "Semana 1 - \(name), você começou."
            )
        }
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

    private var pendingPhotoItemsSignature: String {
        pendingPhotoSaveStore.pendingItems.map {
            "\($0.id.uuidString)|\($0.date.timeIntervalSince1970)|\($0.progress)|\($0.status.rawValue)"
        }
        .joined(separator: ",")
    }

    private var latestCheckInThisWeek: MetricSample? {
        let calendar = Calendar.current
        return recentSamples.first { calendar.isDate($0.date, equalTo: AppClock.now, toGranularity: .weekOfYear) }
    }

    private var latestCheckInWeekday: String {
        guard let latestCheckInThisWeek else { return "" }
        return latestCheckInThisWeek.date.formatted(.dateTime.weekday(.wide))
    }

    fileprivate enum GoalStatusLevel {
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
        kind.formattedMetricValue(fromMetric: metricValue, unitsSystem: unitsSystem)
    }

    private func relativeDescription(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppLocalization.currentLanguage.locale
        return formatter.localizedString(for: date, relativeTo: AppClock.now)
    }

    private func secondaryMetricCard(for kind: MetricKind) -> some View {
        let latestText = cachedLatestByKind[kind].map { formattedMetricValue(for: kind, metricValue: $0.value) } ?? AppLocalization.string("No data yet")
        let deltaChip = metricDeltaChip(for: kind)
        let samples = samplesForKind(kind)
        let detailText = secondaryMetricGoalSummary(for: kind)
            ?? (deltaChip == nil
                ? AppLocalization.string("Log another check-in to reveal the trend.")
                : FlowLocalization.app("Last 7 days", "Ostatnie 7 dni", "Últimos 7 días", "Letzte 7 Tage", "7 derniers jours", "Últimos 7 dias"))

        return HomeSecondaryMetricToggleRow(
            kind: kind,
            latestText: latestText,
            detailText: detailText,
            isExpanded: expandedSecondaryMetrics.contains(kind),
            onToggle: {
                withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                    if expandedSecondaryMetrics.contains(kind) {
                        expandedSecondaryMetrics.remove(kind)
                    } else {
                        expandedSecondaryMetrics.insert(kind)
                    }
                }
            }
        ) {
            NavigationLink {
                MetricDetailView(kind: kind)
            } label: {
                HomeKeyMetricRow(
                    kind: kind,
                    latest: cachedLatestByKind[kind],
                    goal: cachedGoalsByKind[kind],
                    samples: samples,
                    unitsSystem: unitsSystem,
                    showsBackground: false
                )
            }
            .buttonStyle(PressableTileStyle())
            .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
        }
        .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
        .accessibilityHint(detailText)
    }

    private func metricDeltaChip(for kind: MetricKind, days: Int = 7) -> HomeMetricDeltaChip? {
        guard let text = metricDeltaTextFromCache(kind: kind, days: days) else { return nil }
        let tint: Color
        if let window = trendWindowSamples(for: kind, days: days) ?? trendWindowSamples(for: kind, days: 30) {
            switch kind.trendOutcome(from: window.oldest.value, to: window.newest.value, goal: cachedGoalsByKind[kind]) {
            case .positive:
                tint = AppColorRoles.stateSuccess
            case .negative:
                tint = Color(hex: "#EF4444")
            case .neutral:
                tint = AppColorRoles.textTertiary
            }
        } else {
            tint = Color.appAccent
        }
        return HomeMetricDeltaChip(text: text, tint: tint)
    }

    private func customSecondaryMetricCard(for definition: CustomMetricDefinition) -> some View {
        let id = definition.identifier
        let latestText = cachedCustomLatestByIdentifier[id].map {
            String(format: "%.1f %@", $0.value, definition.unitLabel)
        } ?? AppLocalization.string("No data yet")
        let deltaChip = customMetricDeltaChip(for: definition)

        return NavigationLink {
            CustomMetricDetailView(definition: definition)
        } label: {
            HomeCustomSecondaryMetricRow(
                definition: definition,
                latestText: latestText,
                deltaChip: deltaChip
            )
        }
        .buttonStyle(.plain)
    }

    private func customMetricDeltaChip(for definition: CustomMetricDefinition, days: Int = 7) -> HomeMetricDeltaChip? {
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: AppClock.now) else {
            return nil
        }
        let window = (cachedCustomSamplesByIdentifier[definition.identifier] ?? [])
            .filter { $0.date >= startDate }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID else {
            return nil
        }

        let delta = newest.value - oldest.value
        guard abs(delta) > 0.0001 else {
            return HomeMetricDeltaChip(
                text: String(format: "%.1f %@", abs(delta), definition.unitLabel),
                tint: AppColorRoles.textTertiary
            )
        }

        let isPositive = definition.favorsDecrease ? delta < 0 : delta > 0
        return HomeMetricDeltaChip(
            text: String(format: "%@%.1f %@", delta >= 0 ? "+" : "-", abs(delta), definition.unitLabel),
            tint: isPositive ? AppColorRoles.stateSuccess : Color(hex: "#EF4444")
        )
    }

    private func toggleSecondaryMetric(_ kind: MetricKind) {
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.3)) {
            if expandedSecondaryMetrics.contains(kind) {
                _ = expandedSecondaryMetrics.remove(kind)
            } else {
                _ = expandedSecondaryMetrics.insert(kind)
            }
        }
    }

    private func moduleHeader(
        eyebrow: String,
        title: String,
        subtitle: String,
        accent: Color,
        accessibilityIdentifier: String? = nil,
        actions: [ModuleHeaderAction] = []
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

            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button(action: action.action) {
                            Image(systemName: action.systemImage)
                                .font(AppTypography.iconMedium)
                                .foregroundStyle(accent)
                                .frame(width: 36, height: 36)
                                .background(AppColorRoles.surfaceInteractive)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.accessibilityLabel)
                    }
                }
            }
        }
    }

    private struct ModuleHeaderAction: Identifiable {
        let id = UUID()
        let systemImage: String
        let accessibilityLabel: String
        let action: () -> Void
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
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(text)
                .font(AppTypography.badge)
                .foregroundStyle(AppColorRoles.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
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

            if !detail.isEmpty {
                Text(detail)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)
            }

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
        if isFreshHomeState {
            quickAddKinds = [.weight]
            showQuickAddSheet = true
            return
        }
        switch nextFocusInsight.action {
        case .metric(_):
            router.selectedTab = .measurements
        case .measurements:
            router.selectedTab = .measurements
        }
    }

    private func handleGoalStatusTap() {
        Haptics.selection()
        if goalStatus == .noGoals {
            router.selectTab(.measurements)
        } else {
            showGoalStatusLegendSheet = true
        }
    }

    private func handleRecentPhotosCompareTap() {
        guard hasEnoughSavedPhotosForCompare else { return }
        Haptics.selection()
        guard premiumStore.isPremium else {
            premiumStore.presentPaywall(reason: .feature("photo_compare"))
            return
        }
        comparePhotosCardDismissed = true
        AnalyticsFirstEventTracker.trackFirstCompareSessionIfNeeded(source: "home_recent_photos")
        showHomeCompareChooser = true
    }

    private func activationIDSet(from raw: String) -> Set<String> {
        Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func performActivationPrimaryAction() {
        guard let task = activationCurrentTask else { return }
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.activation.task_started",
            parameters: ["task": task.rawValue]
        )
        Haptics.selection()

        switch task {
        case .firstMeasurement:
            showQuickAddSheet = true
        case .addPhoto:
            showActivationAddPhotoSheet = true
        case .chooseMetrics:
            showActivationMetricsSheet = true
        case .setGoal:
            if !goals.isEmpty {
                completeActivationTask(.setGoal)
            } else {
                router.selectedTab = .measurements
            }
        case .setReminders:
            if effects.reminderChecklistCompleted() {
                completeActivationTask(.setReminders)
            } else {
                settingsOpenReminders = true
                router.selectedTab = .settings
            }
        case .explorePremium:
            onboardingChecklistPremiumExplored = true
            premiumStore.presentPaywall(reason: .onboarding)
            completeActivationTask(.explorePremium)
        }
    }

    private func acceptActivationReminderPrompt() {
        guard !isRequestingActivationReminder else { return }
        isRequestingActivationReminder = true
        Analytics.shared.track(.notificationsPromptShown)

        Task { @MainActor in
            let granted = await effects.requestNotificationAuthorization()
            effects.setNotificationsEnabled(granted)
            onboardingSkippedReminders = !granted

            if granted {
                effects.seedTomorrowReminder()
                Analytics.shared.track(.notificationsAccepted)
                Analytics.shared.track(.remindersSetupCompleted)
            }

            isRequestingActivationReminder = false
            finishPendingActivationMetricCompletion()
        }
    }

    private func declineActivationReminderPrompt() {
        onboardingSkippedReminders = true
        finishPendingActivationMetricCompletion()
    }

    private func finishPendingActivationMetricCompletion() {
        guard pendingActivationMetricCompletion else { return }
        pendingActivationMetricCompletion = false
    }

    private func skipActivationTask() {
        guard let task = activationCurrentTask else { return }
        var skipped = activationSkippedTaskIDs
        skipped.insert(task.rawValue)
        activationSkippedTaskIDsRaw = skipped.sorted().joined(separator: ",")
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.activation.task_skipped",
            parameters: ["task": task.rawValue]
        )
        advanceActivation(from: task)
    }

    private func completeActivationTask(_ task: ActivationTask) {
        var completed = activationCompletedTaskIDs
        completed.insert(task.rawValue)
        activationCompletedTaskIDsRaw = completed.sorted().joined(separator: ",")
        Analytics.shared.track(
            signalName: "com.jacekzieba.measureme.activation.task_completed",
            parameters: ["task": task.rawValue]
        )
        advanceActivation(from: task)
    }

    private func advanceActivation(from task: ActivationTask) {
        guard let currentIndex = activationTaskSequence.firstIndex(of: task) else { return }
        let remainingTasks = activationTaskSequence.dropFirst(currentIndex + 1)
        if let nextTask = remainingTasks.first(where: { !isActivationTaskSatisfied($0) }) {
            activationCurrentTaskID = nextTask.rawValue
        } else {
            activationCurrentTaskID = ""
            activationIsDismissed = true
            settingsStore.setHomeModuleVisibility(false, for: .activationHub)
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.activation.completed_all",
                parameters: [:]
            )
        }
        rebuildDashboardItemsCache()
    }

    private func isActivationTaskSatisfied(_ task: ActivationTask) -> Bool {
        switch task {
        case .firstMeasurement:
            return hasAnyMeasurements
        case .addPhoto:
            return hasAnyPhotoContent
        case .chooseMetrics:
            return onboardingChecklistMetricsCompleted
        case .setGoal:
            return !goals.isEmpty
        case .setReminders:
            return effects.reminderChecklistCompleted()
        case .explorePremium:
            return premiumStore.isPremium || onboardingChecklistPremiumExplored
        }
    }

    private func dismissActivationHub() {
        activationIsDismissed = true
        settingsStore.setHomeModuleVisibility(false, for: .activationHub)
        rebuildDashboardItemsCache()
    }

    private func homeMetricAccessibilityLabel(kind: MetricKind) -> String {
        if let latest = cachedLatestByKind[kind] {
            let valueText = kind.formattedMetricValue(fromMetric: latest.value, unitsSystem: unitsSystem)
            return AppLocalization.string("home.metric.accessibility.value", kind.title, valueText)
        }
        return AppLocalization.string("home.metric.accessibility.nodata", kind.title)
    }

    private func refreshChecklistState() {
        reminderChecklistCompleted = effects.reminderChecklistCompleted()
        refreshActivationProgress()
        autoHideChecklistIfCompleted()
        trackPrimaryChecklistShownIfNeeded()
    }

    private func refreshActivationProgress() {
        guard onboardingFlowVersion >= 2 else { return }

        if !isUITestMode,
           totalMetricSampleCount == 1,
           !didShowActivationReminderPrompt,
           !onboardingSkippedReminders,
           !effects.reminderChecklistCompleted() {
            didShowActivationReminderPrompt = true
            showActivationReminderPrompt = true
        }

        guard let task = activationCurrentTask else { return }

        switch task {
        case .firstMeasurement where hasAnyMeasurements:
            completeActivationTask(.firstMeasurement)
        case .addPhoto where hasAnyPhotoContent:
            completeActivationTask(.addPhoto)
        case .chooseMetrics where onboardingChecklistMetricsCompleted:
            completeActivationTask(.chooseMetrics)
        case .setGoal where !goals.isEmpty:
            completeActivationTask(.setGoal)
        case .setReminders where effects.reminderChecklistCompleted():
            completeActivationTask(.setReminders)
        case .explorePremium where premiumStore.isPremium || onboardingChecklistPremiumExplored:
            completeActivationTask(.explorePremium)
        default:
            break
        }
    }

    private func trackPrimaryChecklistShownIfNeeded() {
        guard !didTrackPrimaryChecklistShown, primaryChecklistItem != nil else { return }
        didTrackPrimaryChecklistShown = true
        Analytics.shared.track(.checklistTaskShown)
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
        Analytics.shared.track(.checklistTaskCompleted)
        switch id {
        case "explore_metrics":
            Haptics.selection()
            router.selectedTab = .measurements
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
                    .foregroundStyle(AppColorRoles.textPrimary)

                if !hasAnyMeasurements && cachedLatestByKind.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalization.string("No measurements yet."))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(AppLocalization.string("Add your first measurement to unlock trends and goal progress."))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)

                        Button {
                            showQuickAddSheet = true
                        } label: {
                            Text(AppLocalization.string("Add measurement"))
                                .foregroundStyle(AppColorRoles.textOnAccent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                        .accessibilityIdentifier("home.quickadd.button")
                    }
                    .padding(12)
                    .background(AppColorRoles.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if visibleMetrics.isEmpty {
                    Text(AppLocalization.string("Select up to three key metrics in Settings."))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textSecondary)
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
                    .foregroundStyle(AppColorRoles.textPrimary)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
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
                    .foregroundStyle(AppColorRoles.textPrimary)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
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
                        .foregroundStyle(AppColorRoles.textPrimary)
                    
                    Spacer()
                    
                    if (recentPhotos.count + pendingPhotoSaveStore.pendingItems.count) > maxVisiblePhotos {
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
                
                HomeLastPhotosGrid(
                    tiles: visiblePhotoTiles,
                    onPersistedTap: { selectedPhotoForFullScreen = $0 }
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
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("No photos yet. Capture progress photos to see changes beyond the scale."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Button {
                    router.selectedTab = .photos
                } label: {
                    Text(AppLocalization.string("Add photo"))
                        .foregroundStyle(AppColorRoles.textOnAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
            }
        }
    }
}

private struct GoalStatusLegendSheet: View {
    let currentStatus: HomeView.GoalStatusLevel
    let currentStatusColor: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("home.goalstatus.legend.title"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(AppLocalization.string("home.goalstatus.legend.subtitle"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsCard(tint: AppColorRoles.surfacePrimary) {
                        goalLegendRow(
                            color: AppColorRoles.stateSuccess,
                            titleKey: "home.goalstatus.legend.ontrack.title",
                            descriptionKey: "home.goalstatus.legend.ontrack.description"
                        )
                        SettingsRowDivider()
                        goalLegendRow(
                            color: AppColorRoles.stateWarning,
                            titleKey: "home.goalstatus.legend.slightlyoff.title",
                            descriptionKey: "home.goalstatus.legend.slightlyoff.description"
                        )
                        SettingsRowDivider()
                        goalLegendRow(
                            color: AppColorRoles.stateError,
                            titleKey: "home.goalstatus.legend.needsattention.title",
                            descriptionKey: "home.goalstatus.legend.needsattention.description"
                        )
                    }

                    SettingsCard(tint: currentStatusColor.opacity(0.18)) {
                        Text(AppLocalization.string("home.goalstatus.legend.current.title"))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(AppColorRoles.textTertiary)

                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(currentStatusColor)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentStatusTitle)
                                    .font(AppTypography.bodyStrong)
                                    .foregroundStyle(AppColorRoles.textPrimary)

                                Text(currentStatusDescription)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
            }
            .background(AppColorRoles.surfaceCanvas.ignoresSafeArea())
            .navigationTitle(AppLocalization.string("home.goalstatus.legend.navtitle"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentStatusTitle: String {
        switch currentStatus {
        case .onTrack:
            return AppLocalization.string("home.goalstatus.legend.current.ontrack")
        case .slightlyOff:
            return AppLocalization.string("home.goalstatus.legend.current.slightlyoff")
        case .needsAttention:
            return AppLocalization.string("home.goalstatus.legend.current.needsattention")
        case .noGoals:
            return AppLocalization.string("home.goalstatus.legend.current.nogoals")
        }
    }

    private var currentStatusDescription: String {
        switch currentStatus {
        case .onTrack:
            return AppLocalization.string("home.goalstatus.legend.ontrack.description")
        case .slightlyOff:
            return AppLocalization.string("home.goalstatus.legend.slightlyoff.description")
        case .needsAttention:
            return AppLocalization.string("home.goalstatus.legend.needsattention.description")
        case .noGoals:
            return AppLocalization.string("home.goalstatus.legend.nogoals.description")
        }
    }

    private func goalLegendRow(color: Color, titleKey: String, descriptionKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(titleKey))
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string(descriptionKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HomeLastPhotosGrid: View {
    let tiles: [HomeView.HomePhotoTile]
    let onPersistedTap: (PhotoEntry) -> Void

    private let columns = 3
    private let spacing: CGFloat = 8
    private let minimumSide: CGFloat = 86

    var body: some View {
        GeometryReader { geometry in
            let side = tileSide(for: geometry.size.width)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(tiles) { tile in
                    switch tile {
                    case .persisted(let photo):
                        Button {
                            onPersistedTap(photo)
                        } label: {
                            PhotoGridThumb(
                                photo: photo,
                                size: side,
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
                            targetSize: CGSize(width: side, height: side),
                            cornerRadius: 12,
                            cacheID: pending.id.uuidString,
                            showsStatusLabel: false,
                            accessibilityIdentifier: "home.lastPhotos.pending.item"
                        )
                        .frame(width: side, height: side)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(tiles.count) / Double(columns))))
        return CGFloat(rows) * minimumSide + CGFloat(max(rows - 1, 0)) * spacing
    }

    private func tileSide(for width: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        guard width.isFinite, width > totalSpacing else { return minimumSide }
        let raw = (width - totalSpacing) / CGFloat(columns)
        guard raw.isFinite, raw > 0 else { return minimumSide }
        return max(floor(raw), minimumSide)
    }
}
