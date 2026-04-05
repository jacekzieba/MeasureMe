import Foundation
import SwiftData
import WidgetKit

/// Writes metric data to the App Group shared container so the widget can read it.
/// Call after saving any MetricSample to keep the widget up to date.
enum WidgetDataWriter {
    static let appGroupID = "group.com.jacek.measureme"
    static let widgetKind = "MetricWidget"
    static let smartWidgetKind = "SmartMetricWidget"
    static let streakWidgetKind = "StreakWidget"

    private struct PendingWriteSnapshot {
        let kinds: Set<MetricKind>
        let unitsSystem: String
        let container: ModelContainer
    }

    private static let debounceInterval: Duration = .milliseconds(700)
    private static let stateLock = NSLock()
    private static var pendingKinds: Set<MetricKind> = []
    private static var pendingUnitsSystem: String = "metric"
    private static var pendingModelContainer: ModelContainer?
    private static var flushTask: Task<Void, Never>?

    private static var testDefaultsProviderOverride: ((String) -> UserDefaults?)?
    private static var testReloadHandlerOverride: ((String) -> Void)?

    // MARK: - Payload (matches WidgetMetricData in widget target)

    private struct SamplePayload: Encodable {
        let value: Double
        let date: Date
    }

    private struct GoalPayload: Encodable {
        let targetValue: Double
        let startValue: Double?
        let direction: String
    }

    private struct MetricPayload: Encodable {
        let kind: String
        let samples: [SamplePayload]
        let goal: GoalPayload?
        let unitsSystem: String
    }

    private struct StreakPayload: Encodable {
        let currentStreak: Int
        let maxStreak: Int
        let loggedToday: Bool
    }

    // MARK: - Public API

    /// Writes data for the given metrics and triggers a debounced widget timeline reload.
    /// Fetches the last 90 days of samples from a context created from the provided container.
    static func writeAndReload(
        kinds: [MetricKind],
        context: ModelContext,
        unitsSystem: String
    ) {
        let kindsSet = Set(kinds)
        guard !kindsSet.isEmpty else { return }

        let kindsDescription = kindsSet.map { $0.rawValue }.sorted().joined(separator: ",")
        AppLog.debug("🧩 WidgetDataWriter: queued write kinds=\(kindsDescription) count=\(kindsSet.count)")

        stateLock.lock()
        pendingKinds.formUnion(kindsSet)
        pendingUnitsSystem = unitsSystem
        pendingModelContainer = context.container
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: debounceInterval)
            flushPendingWrites()
        }
        stateLock.unlock()
    }

    /// Immediately flushes pending debounced writes (if any).
    static func flushPendingWrites() {
        guard let pending = consumePendingSnapshot() else { return }
        let context = ModelContext(pending.container)
        performImmediateWriteAndReload(
            kinds: Array(pending.kinds),
            context: context,
            unitsSystem: pending.unitsSystem
        )
    }

    /// Writes data for all MetricKind cases immediately.
    /// Intended for initial population at app startup.
    static func writeAllAndReload(context: ModelContext, unitsSystem: String) {
        if let pending = consumePendingSnapshot() {
            let pendingContext = ModelContext(pending.container)
            performImmediateWriteAndReload(
                kinds: Array(pending.kinds),
                context: pendingContext,
                unitsSystem: pending.unitsSystem
            )
        }
        performImmediateWriteAndReload(kinds: MetricKind.allCases, context: context, unitsSystem: unitsSystem)
    }

    static func reloadAllTimelines() {
        triggerReload()
    }

    static func syncPremiumAndReload(isPremium: Bool) {
        guard let defaults = resolveDefaults() else { return }
        defaults.set(isPremium, forKey: "widget_premium_enabled")
        triggerReload()
    }

    static func syncSharedPayloadsAndReload() {
        guard let defaults = resolveDefaults() else { return }
        writeSharedWidgetPayloads(defaults: defaults)
        triggerReload()
    }

    // MARK: - Internal test hooks

    static func setTestHooks(
        defaultsProvider: ((String) -> UserDefaults?)? = nil,
        reloadHandler: ((String) -> Void)? = nil
    ) {
        stateLock.lock()
        testDefaultsProviderOverride = defaultsProvider
        testReloadHandlerOverride = reloadHandler
        stateLock.unlock()
    }

    static func resetTestHooks() {
        stateLock.lock()
        flushTask?.cancel()
        flushTask = nil
        pendingKinds.removeAll()
        pendingUnitsSystem = "metric"
        pendingModelContainer = nil
        testDefaultsProviderOverride = nil
        testReloadHandlerOverride = nil
        stateLock.unlock()
    }

    // MARK: - Immediate write path

    private static func performImmediateWriteAndReload(
        kinds: [MetricKind],
        context: ModelContext,
        unitsSystem: String
    ) {
        let kindsSet = Set(kinds)
        guard !kindsSet.isEmpty else { return }
        guard let defaults = resolveDefaults() else { return }
        writeSharedWidgetPayloads(defaults: defaults)

        let cutoff = AppClock.now.addingTimeInterval(-90 * 24 * 3600)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let kindRawValues = Set(kindsSet.map(\.rawValue))

        let samplesDescriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate<MetricSample> { sample in
                sample.date >= cutoff
            },
            sortBy: [SortDescriptor(\.date)]
        )
        let fetchedSamples = (try? context.fetch(samplesDescriptor)) ?? []
        var samplesByKindRaw: [String: [MetricSample]] = [:]
        for sample in fetchedSamples where kindRawValues.contains(sample.kindRaw) {
            samplesByKindRaw[sample.kindRaw, default: []].append(sample)
        }

        let goalsDescriptor = FetchDescriptor<MetricGoal>()
        let fetchedGoals = (try? context.fetch(goalsDescriptor)) ?? []
        var goalsByKindRaw: [String: MetricGoal] = [:]
        for goal in fetchedGoals where kindRawValues.contains(goal.kindRaw) {
            guard goalsByKindRaw[goal.kindRaw] == nil else { continue }
            goalsByKindRaw[goal.kindRaw] = goal
        }

        for kind in kindsSet {
            let kindRawValue = kind.rawValue
            let samples = samplesByKindRaw[kindRawValue] ?? []
            let goal = goalsByKindRaw[kindRawValue]

            let sampleDTOs = samples.map { SamplePayload(value: $0.value, date: $0.date) }
            let goalDTO = goal.map {
                GoalPayload(targetValue: $0.targetValue, startValue: $0.startValue, direction: $0.directionRaw)
            }
            let payload = MetricPayload(kind: kindRawValue, samples: sampleDTOs, goal: goalDTO, unitsSystem: unitsSystem)

            if let data = try? encoder.encode(payload) {
                defaults.set(data, forKey: "widget_data_\(kindRawValue)")
            }
        }

        triggerReload()
        AppLog.debug("🧩 WidgetDataWriter: reloadTimelines(ofKind: \(widgetKind))")
    }

    private static func consumePendingSnapshot() -> PendingWriteSnapshot? {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !pendingKinds.isEmpty, let container = pendingModelContainer else {
            flushTask?.cancel()
            flushTask = nil
            return nil
        }

        let snapshot = PendingWriteSnapshot(
            kinds: pendingKinds,
            unitsSystem: pendingUnitsSystem,
            container: container
        )
        pendingKinds.removeAll()
        pendingModelContainer = nil
        flushTask?.cancel()
        flushTask = nil
        return snapshot
    }

    private static func resolveDefaults() -> UserDefaults? {
        stateLock.lock()
        let override = testDefaultsProviderOverride
        stateLock.unlock()
        return override?(appGroupID) ?? UserDefaults(suiteName: appGroupID)
    }

    private static func writeSharedWidgetPayloads(defaults: UserDefaults) {
        let localDefaults = UserDefaults.standard
        defaults.set(localDefaults.bool(forKey: AppSettingsKeys.Premium.entitlement), forKey: "widget_premium_enabled")

        let streakCurrent = localDefaults.integer(forKey: "streak_current_count")
        let streakMax = localDefaults.integer(forKey: "streak_max_count")
        let currentWeek = AppClock.now.isoWeekIdentifier(calendar: Calendar(identifier: .iso8601))
        let loggedToday = hasActiveWeek(currentWeek, defaults: localDefaults)
        let payload = StreakPayload(currentStreak: streakCurrent, maxStreak: streakMax, loggedToday: loggedToday)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: "widget_streak_payload")
        }
    }

    private static func hasActiveWeek(_ week: String, defaults: UserDefaults) -> Bool {
        guard let data = defaults.data(forKey: "streak_active_weeks"),
              let activeWeeks = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }
        return activeWeeks.contains(week)
    }

    private static func triggerReload() {
        stateLock.lock()
        let override = testReloadHandlerOverride
        stateLock.unlock()
        if let override {
            override(widgetKind)
        } else {
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: smartWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: streakWidgetKind)
        }
    }
}
