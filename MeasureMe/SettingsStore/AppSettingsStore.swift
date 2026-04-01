import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published private(set) var snapshot: AppSettingsSnapshot

    private let defaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?
    private var defaultsWriteDepth = 0
    private var suppressObserverUntilNextRunLoop = false
    private var isSnapshotRefreshScheduled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        AppSettingsMigration.applyIfNeeded(defaults: defaults)
        defaults.register(defaults: AppSettingsSnapshot.registeredDefaults)
        self.snapshot = AppSettingsSnapshot.load(from: defaults)

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.shouldHandleDefaultsDidChange() else { return }
                self.scheduleSnapshotRefresh()
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettingsSnapshot, Value>) -> Binding<Value> {
        Binding(
            get: { self.snapshot[keyPath: keyPath] },
            set: { newValue in
                self.set(keyPath, newValue)
            }
        )
    }

    func set<Value>(_ keyPath: WritableKeyPath<AppSettingsSnapshot, Value>, _ value: Value) {
        snapshot[keyPath: keyPath] = value
        persistSnapshot(snapshot)
    }

    func reload() {
        snapshot = AppSettingsSnapshot.load(from: defaults)
    }

    func healthKitAnchor(for kind: MetricKind) -> Data? {
        data(forKey: AppSettingsKeys.Health.healthkitAnchorPrefix + kind.rawValue)
    }

    func setHealthKitAnchor(_ data: Data?, for kind: MetricKind) {
        set(data, forKey: AppSettingsKeys.Health.healthkitAnchorPrefix + kind.rawValue)
    }

    func lastProcessedHealthDate(for kind: MetricKind) -> Date? {
        let value = double(forKey: AppSettingsKeys.Health.healthkitLastProcessedPrefix + kind.rawValue)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    func setLastProcessedHealthDate(_ date: Date?, for kind: MetricKind) {
        let key = AppSettingsKeys.Health.healthkitLastProcessedPrefix + kind.rawValue
        if let date {
            set(date.timeIntervalSince1970, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }

    func goalAchievedFlag(for goalID: String) -> Bool {
        bool(forKey: AppSettingsKeys.Notifications.goalAchievementPrefix + goalID)
    }

    func setGoalAchievedFlag(_ value: Bool, for goalID: String) {
        set(value, forKey: AppSettingsKeys.Notifications.goalAchievementPrefix + goalID)
    }

    func isHealthKitSyncEnabled(for kind: MetricKind) -> Bool {
        switch kind {
        case .weight:
            snapshot.health.healthkitSyncWeight
        case .bodyFat:
            snapshot.health.healthkitSyncBodyFat
        case .height:
            snapshot.health.healthkitSyncHeight
        case .leanBodyMass:
            snapshot.health.healthkitSyncLeanBodyMass
        case .waist:
            snapshot.health.healthkitSyncWaist
        default:
            false
        }
    }

    func setHealthKitSyncEnabled(_ enabled: Bool, for kind: MetricKind) {
        switch kind {
        case .weight:
            set(\.health.healthkitSyncWeight, enabled)
        case .bodyFat:
            set(\.health.healthkitSyncBodyFat, enabled)
        case .height:
            set(\.health.healthkitSyncHeight, enabled)
        case .leanBodyMass:
            set(\.health.healthkitSyncLeanBodyMass, enabled)
        case .waist:
            set(\.health.healthkitSyncWaist, enabled)
        default:
            break
        }
    }

    func incrementOnboardingGoalSelectionStat(for goalRawValue: String) {
        let key = AppSettingsKeys.Analytics.onboardingGoalSelectionStatPrefix + goalRawValue
        set(integer(forKey: key) + 1, forKey: key)
    }

    func homeLayoutSnapshot() -> HomeLayoutSnapshot {
        guard let data = snapshot.homeLayout.layoutData,
              let decoded = try? JSONDecoder().decode(HomeLayoutSnapshot.self, from: data) else {
            return HomeLayoutSnapshot.defaultV1(using: snapshot)
        }
        return HomeLayoutNormalizer.normalize(decoded, using: snapshot)
    }

    func setHomeLayoutSnapshot(_ layout: HomeLayoutSnapshot, syncLegacyHomeFlags: Bool = true) {
        let normalized = HomeLayoutNormalizer.normalize(layout, using: snapshot)
        guard let data = try? JSONEncoder().encode(normalized) else { return }

        set(\.homeLayout.layoutSchemaVersion, normalized.schemaVersion)
        set(\.homeLayout.layoutData, data)

        guard syncLegacyHomeFlags else { return }
        set(\.home.showMeasurementsOnHome, normalized.item(for: .keyMetrics)?.isVisible ?? true)
        set(\.home.showLastPhotosOnHome, normalized.item(for: .recentPhotos)?.isVisible ?? true)
        set(\.home.showHealthMetricsOnHome, normalized.item(for: .healthSummary)?.isVisible ?? true)
        set(\.onboarding.onboardingChecklistShow, normalized.item(for: .setupChecklist)?.isVisible ?? true)
    }

    func setHomeModuleVisibility(_ isVisible: Bool, for kind: HomeModuleKind) {
        var layout = homeLayoutSnapshot()
        layout.setVisibility(isVisible, for: kind)
        setHomeLayoutSnapshot(layout)
    }

    func resetHomeLayout() {
        let current = homeLayoutSnapshot()
        let reset = current.resettingToDefaultGeometry(using: snapshot)
        setHomeLayoutSnapshot(reset)
    }

    func homePinnedAction(default defaultAction: HomePinnedAction = .addMeasurement) -> HomePinnedAction {
        HomePinnedAction(rawValue: snapshot.home.homePinnedActionRaw) ?? defaultAction
    }

    func setHomePinnedAction(_ action: HomePinnedAction) {
        set(\.home.homePinnedActionRaw, action.rawValue)
    }

    func resetNotificationSettingsToDefaults() {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: true) {
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.reminders)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.notificationsEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.smartEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.smartDays)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.smartTime)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.lastLogDate)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.lastPhotoDate)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoRemindersEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.goalAchievedEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.importNotificationsEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.perMetricSmartEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.perMetricLastDates)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.detectedPatterns)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.smartLastNotificationDate)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiNotificationsEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiWeeklyDigestEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiTrendShiftEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiGoalMilestonesEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiRoundNumbersEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiConsistencyEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiDigestWeekday)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiDigestTime)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiLastSentTimestamps)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.aiMutedTypes)
        }
    }

    func clearHealthKitSyncMetadata() {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: true) {
            defaults.set(false, forKey: AppSettingsKeys.Health.isSyncEnabled)
            defaults.removeObject(forKey: AppSettingsKeys.Health.healthkitLastImport)
            defaults.removeObject(forKey: AppSettingsKeys.Health.healthkitInitialHistoricalImport)

            for key in defaults.dictionaryRepresentation().keys {
                if key.hasPrefix(AppSettingsKeys.Health.healthkitAnchorPrefix)
                    || key.hasPrefix(AppSettingsKeys.Health.healthkitLastProcessedPrefix) {
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }

    func clearUserDataDefaults() {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: true) {
            defaults.removeObject(forKey: AppSettingsKeys.Profile.userName)
            defaults.removeObject(forKey: AppSettingsKeys.Profile.userAge)
            defaults.removeObject(forKey: AppSettingsKeys.Profile.userGender)
            defaults.removeObject(forKey: AppSettingsKeys.Profile.manualHeight)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.reminders)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.lastLogDate)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.lastPhotoDate)
            defaults.removeObject(forKey: AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled)
        }
    }

    func value<Value>(forKey key: String, default defaultValue: Value) -> Value {
        if let value = object(forKey: key) as? Value {
            return value
        }
        return defaultValue
    }

    // MARK: - UserDefaults-compatible API

    func register(defaults registrationDictionary: [String: Any]) {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: true) {
            defaults.register(defaults: registrationDictionary)
        }
    }

    func object(forKey defaultName: String) -> Any? {
        defaults.object(forKey: defaultName)
    }

    func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    func array(forKey defaultName: String) -> [Any]? {
        defaults.array(forKey: defaultName)
    }

    func dictionary(forKey defaultName: String) -> [String: Any]? {
        defaults.dictionary(forKey: defaultName)
    }

    func data(forKey defaultName: String) -> Data? {
        defaults.data(forKey: defaultName)
    }

    func stringArray(forKey defaultName: String) -> [String]? {
        defaults.stringArray(forKey: defaultName)
    }

    func integer(forKey defaultName: String) -> Int {
        defaults.integer(forKey: defaultName)
    }

    func float(forKey defaultName: String) -> Float {
        defaults.float(forKey: defaultName)
    }

    func double(forKey defaultName: String) -> Double {
        defaults.double(forKey: defaultName)
    }

    func bool(forKey defaultName: String) -> Bool {
        defaults.bool(forKey: defaultName)
    }

    func url(forKey defaultName: String) -> URL? {
        defaults.url(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: true) {
            defaults.set(value, forKey: defaultName)
        }
    }

    func removeObject(forKey defaultName: String) {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: true) {
            defaults.removeObject(forKey: defaultName)
        }
    }

    func dictionaryRepresentation() -> [String: Any] {
        defaults.dictionaryRepresentation()
    }

    private func persistSnapshot(_ snapshot: AppSettingsSnapshot) {
        performDefaultsWrite(scheduleSnapshotRefreshAfterWrite: false) {
            let profile = snapshot.profile
            defaults.set(profile.userName, forKey: AppSettingsKeys.Profile.userName)
            defaults.set(profile.userAge, forKey: AppSettingsKeys.Profile.userAge)
            defaults.set(profile.userGender, forKey: AppSettingsKeys.Profile.userGender)
            defaults.set(profile.manualHeight, forKey: AppSettingsKeys.Profile.manualHeight)
            defaults.set(profile.unitsSystem, forKey: AppSettingsKeys.Profile.unitsSystem)

            let home = snapshot.home
            defaults.set(home.showLastPhotosOnHome, forKey: AppSettingsKeys.Home.showLastPhotosOnHome)
            defaults.set(home.showMeasurementsOnHome, forKey: AppSettingsKeys.Home.showMeasurementsOnHome)
            defaults.set(home.showHealthMetricsOnHome, forKey: AppSettingsKeys.Home.showHealthMetricsOnHome)
            defaults.set(home.showStreakOnHome, forKey: AppSettingsKeys.Home.showStreakOnHome)
            defaults.set(home.homePinnedActionRaw, forKey: AppSettingsKeys.Home.homePinnedAction)
            defaults.set(home.homeTabScrollOffset, forKey: AppSettingsKeys.Home.homeTabScrollOffset)
            defaults.set(home.homePhotoMetricSyncLastDate, forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastDate)
            defaults.set(home.homePhotoMetricSyncLastID, forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastID)
            defaults.set(home.settingsOpenTrackedMeasurements, forKey: AppSettingsKeys.Home.settingsOpenTrackedMeasurements)
            defaults.set(home.settingsOpenReminders, forKey: AppSettingsKeys.Home.settingsOpenReminders)
            defaults.set(home.settingsOpenHomeSettings, forKey: AppSettingsKeys.Home.settingsOpenHomeSettings)

            let homeLayout = snapshot.homeLayout
            defaults.set(homeLayout.layoutSchemaVersion, forKey: AppSettingsKeys.Home.homeLayoutSchemaVersion)
            defaults.set(homeLayout.layoutData, forKey: AppSettingsKeys.Home.homeLayoutData)

            let onboarding = snapshot.onboarding
            defaults.set(onboarding.hasCompletedOnboarding, forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding)
            defaults.set(onboarding.onboardingSkippedHealthKit, forKey: AppSettingsKeys.Onboarding.onboardingSkippedHealthKit)
            defaults.set(onboarding.onboardingSkippedReminders, forKey: AppSettingsKeys.Onboarding.onboardingSkippedReminders)
            defaults.set(onboarding.onboardingViewedICloudBackupOffer, forKey: AppSettingsKeys.Onboarding.onboardingViewedICloudBackupOffer)
            defaults.set(onboarding.onboardingSkippedICloudBackup, forKey: AppSettingsKeys.Onboarding.onboardingSkippedICloudBackup)
            defaults.set(onboarding.onboardingChecklistShow, forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow)
            defaults.set(onboarding.onboardingChecklistCollapsed, forKey: AppSettingsKeys.Onboarding.onboardingChecklistCollapsed)
            defaults.set(onboarding.onboardingChecklistHideCompleted, forKey: AppSettingsKeys.Onboarding.onboardingChecklistHideCompleted)
            defaults.set(onboarding.onboardingChecklistMetricsCompleted, forKey: AppSettingsKeys.Onboarding.onboardingChecklistMetricsCompleted)
            defaults.set(onboarding.onboardingChecklistPremiumExplored, forKey: AppSettingsKeys.Onboarding.onboardingChecklistPremiumExplored)
            defaults.set(onboarding.onboardingPrimaryGoal, forKey: AppSettingsKeys.Onboarding.onboardingPrimaryGoal)
            defaults.set(onboarding.onboardingActivationCompleted, forKey: AppSettingsKeys.Onboarding.onboardingActivationCompleted)
            defaults.set(onboarding.activationTriggerQuickAdd, forKey: AppSettingsKeys.Onboarding.activationTriggerQuickAdd)

            let health = snapshot.health
            defaults.set(health.isSyncEnabled, forKey: AppSettingsKeys.Health.isSyncEnabled)
            defaults.set(health.healthkitLastImport, forKey: AppSettingsKeys.Health.healthkitLastImport)
            defaults.set(health.healthkitSyncWeight, forKey: AppSettingsKeys.Health.healthkitSyncWeight)
            defaults.set(health.healthkitSyncBodyFat, forKey: AppSettingsKeys.Health.healthkitSyncBodyFat)
            defaults.set(health.healthkitSyncHeight, forKey: AppSettingsKeys.Health.healthkitSyncHeight)
            defaults.set(health.healthkitSyncLeanBodyMass, forKey: AppSettingsKeys.Health.healthkitSyncLeanBodyMass)
            defaults.set(health.healthkitSyncWaist, forKey: AppSettingsKeys.Health.healthkitSyncWaist)
            defaults.set(health.healthkitInitialHistoricalImport, forKey: AppSettingsKeys.Health.healthkitInitialHistoricalImport)
            defaults.set(health.healthIndicatorsV2Migrated, forKey: AppSettingsKeys.Health.healthIndicatorsV2Migrated)

            let indicators = snapshot.indicators
            defaults.set(indicators.showWHtROnHome, forKey: AppSettingsKeys.Indicators.showWHtROnHome)
            defaults.set(indicators.showRFMOnHome, forKey: AppSettingsKeys.Indicators.showRFMOnHome)
            defaults.set(indicators.showBMIOnHome, forKey: AppSettingsKeys.Indicators.showBMIOnHome)
            defaults.set(indicators.showBodyFatOnHome, forKey: AppSettingsKeys.Indicators.showBodyFatOnHome)
            defaults.set(indicators.showLeanMassOnHome, forKey: AppSettingsKeys.Indicators.showLeanMassOnHome)
            defaults.set(indicators.showWHROnHome, forKey: AppSettingsKeys.Indicators.showWHROnHome)
            defaults.set(indicators.showWaistRiskOnHome, forKey: AppSettingsKeys.Indicators.showWaistRiskOnHome)
            defaults.set(indicators.showABSIOnHome, forKey: AppSettingsKeys.Indicators.showABSIOnHome)
            defaults.set(indicators.showBodyShapeScoreOnHome, forKey: AppSettingsKeys.Indicators.showBodyShapeScoreOnHome)
            defaults.set(indicators.showCentralFatRiskOnHome, forKey: AppSettingsKeys.Indicators.showCentralFatRiskOnHome)
            defaults.set(indicators.showConicityOnHome, forKey: AppSettingsKeys.Indicators.showConicityOnHome)
            defaults.set(indicators.showPhysiqueSWR, forKey: AppSettingsKeys.Indicators.showPhysiqueSWR)
            defaults.set(indicators.showPhysiqueCWR, forKey: AppSettingsKeys.Indicators.showPhysiqueCWR)
            defaults.set(indicators.showPhysiqueSHR, forKey: AppSettingsKeys.Indicators.showPhysiqueSHR)
            defaults.set(indicators.showPhysiqueHWR, forKey: AppSettingsKeys.Indicators.showPhysiqueHWR)
            defaults.set(indicators.showPhysiqueBWR, forKey: AppSettingsKeys.Indicators.showPhysiqueBWR)
            defaults.set(indicators.showPhysiqueWHtR, forKey: AppSettingsKeys.Indicators.showPhysiqueWHtR)
            defaults.set(indicators.showPhysiqueBodyFat, forKey: AppSettingsKeys.Indicators.showPhysiqueBodyFat)
            defaults.set(indicators.showPhysiqueRFM, forKey: AppSettingsKeys.Indicators.showPhysiqueRFM)

            let experience = snapshot.experience
            defaults.set(experience.appAppearance, forKey: AppSettingsKeys.Experience.appAppearance)
            defaults.set(experience.animationsEnabled, forKey: AppSettingsKeys.Experience.animationsEnabled)
            defaults.set(experience.hapticsEnabled, forKey: AppSettingsKeys.Experience.hapticsEnabled)
            defaults.set(experience.appLanguage, forKey: AppSettingsKeys.Experience.appLanguage)
            defaults.set(experience.quickAddHintDismissed, forKey: AppSettingsKeys.Experience.quickAddHintDismissed)
            defaults.set(experience.photosFilterTag, forKey: AppSettingsKeys.Experience.photosFilterTag)
            defaults.set(experience.saveUnchangedQuickAdd, forKey: AppSettingsKeys.Experience.saveUnchangedQuickAdd)
            defaults.set(experience.hasCustomizedMetrics, forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)

            let premium = snapshot.premium
            defaults.set(premium.premiumEntitlement, forKey: AppSettingsKeys.Premium.entitlement)
            defaults.set(premium.premiumFirstLaunchDate, forKey: AppSettingsKeys.Premium.firstLaunchDate)
            defaults.set(premium.premiumLastNagDate, forKey: AppSettingsKeys.Premium.lastNagDate)

            let diagnostics = snapshot.diagnostics
            defaults.set(diagnostics.diagnosticsLoggingEnabled, forKey: AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled)
            defaults.set(diagnostics.crashReporterHasUnreported, forKey: AppSettingsKeys.Diagnostics.crashReporterHasUnreported)
            defaults.set(diagnostics.databaseEncryptionProtectionVersion, forKey: AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion)

            let notifications = snapshot.notifications
            defaults.set(notifications.measurementRemindersData, forKey: AppSettingsKeys.Notifications.reminders)
            defaults.set(notifications.notificationsEnabled, forKey: AppSettingsKeys.Notifications.notificationsEnabled)
            defaults.set(notifications.smartEnabled, forKey: AppSettingsKeys.Notifications.smartEnabled)
            defaults.set(notifications.smartDays, forKey: AppSettingsKeys.Notifications.smartDays)
            defaults.set(notifications.smartTime, forKey: AppSettingsKeys.Notifications.smartTime)
            defaults.set(notifications.lastLogDate, forKey: AppSettingsKeys.Notifications.lastLogDate)
            defaults.set(notifications.lastPhotoDate, forKey: AppSettingsKeys.Notifications.lastPhotoDate)
            defaults.set(notifications.photoRemindersEnabled, forKey: AppSettingsKeys.Notifications.photoRemindersEnabled)
            defaults.set(notifications.goalAchievedEnabled, forKey: AppSettingsKeys.Notifications.goalAchievedEnabled)
            defaults.set(notifications.importNotificationsEnabled, forKey: AppSettingsKeys.Notifications.importNotificationsEnabled)
            defaults.set(notifications.perMetricSmartEnabled, forKey: AppSettingsKeys.Notifications.perMetricSmartEnabled)
            defaults.set(notifications.aiNotificationsEnabled, forKey: AppSettingsKeys.Notifications.aiNotificationsEnabled)
            defaults.set(notifications.aiWeeklyDigestEnabled, forKey: AppSettingsKeys.Notifications.aiWeeklyDigestEnabled)
            defaults.set(notifications.aiTrendShiftEnabled, forKey: AppSettingsKeys.Notifications.aiTrendShiftEnabled)
            defaults.set(notifications.aiGoalMilestonesEnabled, forKey: AppSettingsKeys.Notifications.aiGoalMilestonesEnabled)
            defaults.set(notifications.aiRoundNumbersEnabled, forKey: AppSettingsKeys.Notifications.aiRoundNumbersEnabled)
            defaults.set(notifications.aiConsistencyEnabled, forKey: AppSettingsKeys.Notifications.aiConsistencyEnabled)
            defaults.set(notifications.aiDigestWeekday, forKey: AppSettingsKeys.Notifications.aiDigestWeekday)
            defaults.set(notifications.aiDigestTime, forKey: AppSettingsKeys.Notifications.aiDigestTime)
            defaults.set(notifications.aiLastSentTimestamps, forKey: AppSettingsKeys.Notifications.aiLastSentTimestamps)
            defaults.set(notifications.aiMutedTypes, forKey: AppSettingsKeys.Notifications.aiMutedTypes)

            let analytics = snapshot.analytics
            defaults.set(analytics.analyticsEnabled, forKey: AppSettingsKeys.Analytics.analyticsEnabled)
            defaults.set(analytics.firstMetricAddedTracked, forKey: AppSettingsKeys.Analytics.firstMetricAddedTracked)
            defaults.set(analytics.firstPhotoAddedTracked, forKey: AppSettingsKeys.Analytics.firstPhotoAddedTracked)
            defaults.set(analytics.appleIntelligenceEnabled, forKey: AppSettingsKeys.Analytics.appleIntelligenceEnabled)

            let iCloudBackup = snapshot.iCloudBackup
            defaults.set(iCloudBackup.isEnabled, forKey: AppSettingsKeys.ICloudBackup.isEnabled)
            defaults.set(iCloudBackup.lastSuccessTimestamp, forKey: AppSettingsKeys.ICloudBackup.lastSuccessTimestamp)
            defaults.set(iCloudBackup.lastErrorMessage, forKey: AppSettingsKeys.ICloudBackup.lastErrorMessage)
            defaults.set(iCloudBackup.autoRestoreCompleted, forKey: AppSettingsKeys.ICloudBackup.autoRestoreCompleted)
            defaults.set(Int(iCloudBackup.lastBackupSizeBytes), forKey: AppSettingsKeys.ICloudBackup.lastBackupSizeBytes)

            defaults.set(snapshot.internalState.settingsSchemaVersion, forKey: AppSettingsKeys.settingsSchemaVersion)

            // Mirror intent-relevant keys to App Group suite for out-of-process access
            Self.syncIntentSettings(snapshot, defaults: defaults)
        }
    }

    private static let appGroupDefaults = UserDefaults(suiteName: "group.com.jacek.measureme")

    #if DEBUG
    /// Forces an immediate synchronous reload of the snapshot from the underlying UserDefaults.
    /// Use only in tests to avoid the normal async 10 ms debounce refresh.
    func forceReloadSnapshot() {
        snapshot = AppSettingsSnapshot.load(from: defaults)
    }
    #endif

    private static func syncIntentSettings(_ snapshot: AppSettingsSnapshot, defaults: UserDefaults) {
        guard let shared = appGroupDefaults, shared !== defaults else { return }
        shared.set(snapshot.profile.unitsSystem, forKey: AppSettingsKeys.Profile.unitsSystem)
        shared.set(snapshot.experience.appAppearance, forKey: AppSettingsKeys.Experience.appAppearance)
        for key in AppSettingsKeys.Metrics.allEnabledKeys {
            shared.set(defaults.bool(forKey: key), forKey: key)
        }
    }

    private func shouldHandleDefaultsDidChange() -> Bool {
        defaultsWriteDepth == 0 && !suppressObserverUntilNextRunLoop
    }

    private func scheduleSnapshotRefresh() {
        guard !isSnapshotRefreshScheduled else { return }
        isSnapshotRefreshScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(10))
            guard let self else { return }
            self.isSnapshotRefreshScheduled = false
            self.snapshot = AppSettingsSnapshot.load(from: self.defaults)
        }
    }

    private func performDefaultsWrite(
        scheduleSnapshotRefreshAfterWrite: Bool,
        _ operation: () -> Void
    ) {
        defaultsWriteDepth += 1
        operation()
        defaultsWriteDepth = max(0, defaultsWriteDepth - 1)

        if defaultsWriteDepth == 0 {
            suppressObserverUntilNextRunLoop = true
            Task { @MainActor [weak self] in
                self?.suppressObserverUntilNextRunLoop = false
            }
        }

        if scheduleSnapshotRefreshAfterWrite {
            scheduleSnapshotRefresh()
        }
    }
}
