import SwiftUI
import SwiftData

/// Lightweight @Observable ViewModel for HomeView.
/// Holds query results and cached computed properties.
/// The view syncs @Query results here and reads data through the ViewModel.
@Observable @MainActor final class HomeViewModel {

    // MARK: - Query Results

    var recentSamples: [MetricSample] = []
    var goals: [MetricGoal] = []
    var recentPhotos: [PhotoEntry] = []
    var customDefinitions: [CustomMetricDefinition] = []

    // MARK: - Cached Properties (previously @State in HomeView)

    var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    var cachedGoalsByKind: [MetricKind: MetricGoal] = [:]
    var cachedCustomSamplesByIdentifier: [String: [MetricSample]] = [:]
    var cachedCustomLatestByIdentifier: [String: MetricSample] = [:]
    var cachedCustomGoalsByIdentifier: [String: MetricGoal] = [:]
    var cachedDashboardItems: [HomeModuleLayoutItem] = []
    var cachedVisiblePhotoTiles: [HomeView.HomePhotoTile] = []
    var cachedNextFocusInsight: HomeView.HomeNextFocusInsight?

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
        totalMetricSampleCountOut: inout Int,
        hasAnyMeasurementsOut: inout Bool,
        nextFocusComputer: () -> HomeView.HomeNextFocusInsight?
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
        totalMetricSampleCountOut = fetchedMetricCount
        hasAnyMeasurementsOut = fetchedMetricCount > 0

        cachedNextFocusInsight = nextFocusComputer()
    }

    // MARK: - Rebuild: Goals Cache

    /// Called by the view when goals change.
    func rebuildGoalsCache(
        goals: [MetricGoal],
        nextFocusComputer: () -> HomeView.HomeNextFocusInsight?
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
        let persistedTiles = recentPhotos.prefix(persistedCandidateLimit).map { HomeView.HomePhotoTile.persisted($0) }
        let pendingTiles = pendingItems.map { HomeView.HomePhotoTile.pending($0) }
        cachedVisiblePhotoTiles = Array(
            (persistedTiles + pendingTiles)
                .sorted { lhs, rhs in lhs.date > rhs.date }
                .prefix(maxVisiblePhotos)
        )
    }

    // MARK: - Rebuild: Next Focus Insight Cache

    func rebuildNextFocusInsightCache(
        nextFocusComputer: () -> HomeView.HomeNextFocusInsight?
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
}
