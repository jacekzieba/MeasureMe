import SwiftUI
import SwiftData

/// Photo sync cursor accessor used by photo-sync logic moved into the ViewModel.
/// The view exposes its persisted `@AppSetting` cursor through these closures so
/// the ViewModel can read/update it without owning the AppSetting directly.
struct HomePhotoSyncCursorAccess {
    var getDate: () -> Double
    var getID: () -> String
    var setDate: (Double) -> Void
    var setID: (String) -> Void
}

/// Lightweight @Observable ViewModel for HomeView.
/// Holds query results and cached computed properties.
/// The view syncs @Query results here and reads data through the ViewModel.
@Observable @MainActor final class HomeViewModel {

    // MARK: - Query Results

    var recentSamples: [MetricSample] = []
    var goals: [MetricGoal] = []
    var recentPhotos: [PhotoEntry] = []
    var customDefinitions: [CustomMetricDefinition] = []

    // MARK: - Data state (moved from HomeView @State)

    var hasAnyMeasurements: Bool = false
    var totalMetricSampleCount: Int = 0
    var hasAnySavedPhotosInStore: Bool = false
    var hasEnoughSavedPhotosForCompareInStore: Bool = false
    var latestBodyFat: Double?
    var latestLeanMass: Double?

    // MARK: - Presentation State (moved from HomeView @State)

    /// Quick-add sheet kinds/source — set before presenting the sheet.
    var quickAddKinds: [MetricKind] = []
    var quickAddTelemetrySource: MeasurementTelemetrySource = .quickAdd

    /// Expanded secondary metrics in key metrics card.
    var expandedSecondaryMetrics: Set<MetricKind> = []

    /// Scroll offset of the home scroll view.
    var scrollOffset: CGFloat = 0

    /// Checklist / activation state flags.
    var isRequestingActivationReminder: Bool = false
    var pendingActivationMetricCompletion: Bool = false
    var didShowActivationReminderPrompt: Bool = false
    var reminderChecklistCompleted: Bool = false
    var checklistStatusText: String?
    var isChecklistConnectingHealth: Bool = false
    var shouldShowHealthSettingsShortcut: Bool = false

    /// Lifecycle / startup flags.
    var didCheckSevenDayPaywallPrompt: Bool = false
    var didRunStartupPhases: Bool = false
    var didEmitHomeInitialRender: Bool = false

    /// Section mounting flags (deferred rendering).
    var isLastPhotosSectionMounted: Bool = false
    var isHealthSectionMounted: Bool = false

    /// In-flight sync guard.
    var isPhotoMetricSyncInFlight: Bool = false

    /// Deferred startup tasks.
    var deferredPhaseBTask: Task<Void, Never>?
    var deferredPhaseCTask: Task<Void, Never>?
    var deferredSectionMountTask: Task<Void, Never>?

    // MARK: - Cached Properties (previously @State in HomeView)

    var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    var cachedGoalsByKind: [MetricKind: MetricGoal] = [:]
    var cachedCustomSamplesByIdentifier: [String: [MetricSample]] = [:]
    var cachedCustomLatestByIdentifier: [String: MetricSample] = [:]
    var cachedCustomGoalsByIdentifier: [String: MetricGoal] = [:]
    var cachedDashboardItems: [HomeModuleLayoutItem] = []
    var cachedVisiblePhotoTiles: [HomePhotoTile] = []
    var cachedNextFocusInsight: HomeNextFocusInsight?

    // MARK: - Rebuild: Measurement Caches

    /// Called by the view when recentSamples or activeKinds change.
    /// - Parameters:
    ///   - recentSamples: The @Query result from the view.
    ///   - goals: The @Query goals result from the view.
    ///   - activeKinds: Active metric kinds from ActiveMetricsStore.
    ///   - modelContext: For total count fetch.
    ///   - totalMetricSampleCountOut: Written back to caller (view @State).
    ///   - hasAnyMeasurementsOut: Written back to caller (view @State).
    func refreshMeasurementCaches(
        recentSamples: [MetricSample],
        goals: [MetricGoal],
        activeKinds: [MetricKind],
        modelContext: ModelContext,
        allowFallbackFetch: Bool = true,
        nextFocusComputer: () -> HomeNextFocusInsight?
    ) {
        var grouped: [MetricKind: [MetricSample]] = [:]
        var latest: [MetricKind: MetricSample] = [:]
        let kindsToKeep = Set(activeKinds).union([.waist, .height, .weight, .bodyFat, .leanBodyMass, .hips])

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

        cachedNextFocusInsight = nextFocusComputer()
    }

    // MARK: - Rebuild: Goals Cache

    /// Called by the view when goals change.
    func rebuildGoalsCache(
        goals: [MetricGoal],
        nextFocusComputer: () -> HomeNextFocusInsight?
    ) {
        var dict: [MetricKind: MetricGoal] = [:]
        for goal in goals {
            if let kind = MetricKind(rawValue: goal.kindRaw) {
                dict[kind] = goal
            }
        }
        cachedGoalsByKind = dict
        cachedNextFocusInsight = nextFocusComputer()
    }

    // MARK: - Rebuild: Visible Photo Tiles Cache

    /// Called by the view when photo state changes.
    func rebuildVisiblePhotoTilesCache(
        recentPhotos: [PhotoEntry],
        pendingItems: [PendingPhotoSaveItem],
        maxVisiblePhotos: Int
    ) {
        let persistedCandidateLimit = maxVisiblePhotos * 3
        let persistedTiles = recentPhotos.prefix(persistedCandidateLimit).map { HomePhotoTile.persisted($0) }
        let pendingTiles = pendingItems.map { HomePhotoTile.pending($0) }
        cachedVisiblePhotoTiles = Array(
            (persistedTiles + pendingTiles)
                .sorted { lhs, rhs in lhs.date > rhs.date }
                .prefix(maxVisiblePhotos)
        )
    }

    // MARK: - Rebuild: Next Focus Insight Cache

    func rebuildNextFocusInsightCache(
        nextFocusComputer: () -> HomeNextFocusInsight?
    ) {
        cachedNextFocusInsight = nextFocusComputer()
    }

    // MARK: - Rebuild: Dashboard Items Cache

    /// Called by the view when layout or visibility settings change.
    func rebuildDashboardItemsCache(
        settingsStore: AppSettingsStore,
        dashboardColumns: Int,
        shouldRenderModule: (HomeModuleKind) -> Bool
    ) {
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

    // MARK: - Photo Store State

    /// Refreshes saved-photos availability flags and rebuilds visible tiles cache.
    func refreshPhotoStoreState(
        modelContext: ModelContext,
        recentPhotosForTiles: [PhotoEntry],
        pendingItems: [PendingPhotoSaveItem],
        maxVisiblePhotos: Int
    ) {
        var descriptor = FetchDescriptor<PhotoEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        let newestPhotos = (try? modelContext.fetch(descriptor)) ?? []
        hasAnySavedPhotosInStore = !newestPhotos.isEmpty
        hasEnoughSavedPhotosForCompareInStore = newestPhotos.count >= 2
        rebuildVisiblePhotoTilesCache(
            recentPhotos: recentPhotosForTiles,
            pendingItems: pendingItems,
            maxVisiblePhotos: maxVisiblePhotos
        )
    }

    // MARK: - Photo Metric Sync

    func syncMode(force: Bool, cursor: HomePhotoSyncCursorAccess) -> PhotoSyncMode {
        if force || cursor.getDate() <= 0 {
            return .full
        }
        return .incremental
    }

    func photoCursorID(for photo: PhotoEntry) -> String {
        String(describing: photo.persistentModelID)
    }

    func isPhotoAfterSyncCursor(
        _ photo: PhotoEntry,
        cursor: HomePhotoSyncCursorAccess
    ) -> Bool {
        let photoTime = photo.date.timeIntervalSince1970
        let cursorDate = cursor.getDate()
        let cursorID = cursor.getID()
        if photoTime > cursorDate { return true }
        if photoTime < cursorDate { return false }
        return photoCursorID(for: photo) > cursorID
    }

    func updatePhotoSyncCursor(using photos: [PhotoEntry], cursor: HomePhotoSyncCursorAccess) {
        let candidates = photos.map { (date: $0.date, id: photoCursorID(for: $0)) }
        guard let newest = candidates.max(by: { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }) else { return }
        cursor.setDate(newest.date.timeIntervalSince1970)
        cursor.setID(newest.id)
    }

    func fetchSyncCandidatePhotos(
        mode: PhotoSyncMode,
        modelContext: ModelContext,
        cursor: HomePhotoSyncCursorAccess
    ) throws -> [PhotoEntry] {
        let descriptor: FetchDescriptor<PhotoEntry>
        switch mode {
        case .full:
            descriptor = FetchDescriptor<PhotoEntry>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        case .incremental:
            let cursorDate = Date(timeIntervalSince1970: cursor.getDate())
            descriptor = FetchDescriptor<PhotoEntry>(
                predicate: #Predicate<PhotoEntry> { photo in
                    photo.date >= cursorDate
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        }
        return try modelContext.fetch(descriptor)
    }

    nonisolated static func latestPhotoSyncSnapshotByKey(
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

    /// Synchronises Measurement samples with snapshots stored on photos.
    /// Upserts only — never deletes existing samples on photo removal.
    func syncMeasurementsFromPhotosIfNeeded(
        force: Bool = false,
        modelContext: ModelContext,
        cursor: HomePhotoSyncCursorAccess
    ) async {
        guard !isPhotoMetricSyncInFlight else { return }
        let mode = syncMode(force: force, cursor: cursor)
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
            candidatePhotos = try fetchSyncCandidatePhotos(mode: mode, modelContext: modelContext, cursor: cursor)
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
                !photo.linkedMetrics.isEmpty && isPhotoAfterSyncCursor(photo, cursor: cursor)
            }
        }
        guard !photosWithMetrics.isEmpty else {
            updatePhotoSyncCursor(using: candidatePhotos, cursor: cursor)
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
            HomeViewModel.latestPhotoSyncSnapshotByKey(from: syncCandidates)
        }.value

        guard !latestSnapshotByKey.isEmpty else {
            updatePhotoSyncCursor(using: candidatePhotos, cursor: cursor)
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

        updatePhotoSyncCursor(using: candidatePhotos, cursor: cursor)
    }

    // MARK: - Startup Phases

    func emitHomeInitialRenderIfNeeded() {
        guard !didEmitHomeInitialRender else { return }
        didEmitHomeInitialRender = true
        StartupInstrumentation.event("HomeInitialRender")
    }

    /// Run critical phase A — minimal sync work to render an initial Home frame.
    func runCriticalStartupPhaseA() {
        hasAnyMeasurements = !recentSamples.isEmpty
        isLastPhotosSectionMounted = true
        isHealthSectionMounted = true
    }

    /// Schedule deferred phase B — refreshes caches, fetches health, records streak.
    func scheduleDeferredStartupPhaseB(_ work: @escaping @MainActor () -> Void) {
        deferredPhaseBTask?.cancel()
        deferredPhaseBTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            work()
        }
    }

    /// Schedule deferred phase C — photo→metric sync.
    func scheduleDeferredStartupPhaseC(
        delayMilliseconds: Int = 1500,
        _ work: @escaping @MainActor () async -> Void
    ) {
        deferredPhaseCTask?.cancel()
        deferredPhaseCTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            let deferredSyncState = StartupInstrumentation.begin("HomeDeferredSync")
            StartupInstrumentation.event("HomeDeferredSyncStart")
            await work()
            StartupInstrumentation.event("HomeDeferredSyncEnd")
            StartupInstrumentation.end("HomeDeferredSync", state: deferredSyncState)
        }
    }

    /// Schedule deferred section mounts (last photos, health).
    func scheduleDeferredSectionMounts() {
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

    /// Aggregate startup phases entry point — runs once per ViewModel lifetime.
    func runStartupPhasesIfNeeded(
        phaseB: @escaping @MainActor () -> Void,
        phaseC: @escaping @MainActor () async -> Void
    ) {
        guard !didRunStartupPhases else { return }
        didRunStartupPhases = true
        runCriticalStartupPhaseA()
        scheduleDeferredStartupPhaseB(phaseB)
        scheduleDeferredStartupPhaseC(phaseC)
        scheduleDeferredSectionMounts()
    }

    // MARK: - HealthKit

    /// Fetches latest body composition values from HealthKit (cached) into VM state.
    func fetchHealthKitData(isSyncEnabled: Bool, effects: HomeEffects) {
        guard isSyncEnabled else {
            latestBodyFat = nil
            latestLeanMass = nil
            return
        }
        Task { [weak self] in
            do {
                let composition = try await effects.fetchLatestBodyCompositionCached()
                await MainActor.run { [weak self] in
                    self?.latestBodyFat = composition.bodyFat
                    self?.latestLeanMass = composition.leanMass
                }
            } catch {
                AppLog.debug("⚠️ Error fetching HealthKit data: \(error.localizedDescription)")
                await MainActor.run { [weak self] in
                    self?.latestBodyFat = nil
                    self?.latestLeanMass = nil
                }
            }
        }
    }
}
