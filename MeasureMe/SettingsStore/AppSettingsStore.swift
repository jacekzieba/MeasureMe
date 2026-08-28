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
        let activationVisibility = normalized.item(for: .activationHub)?.isVisible
            ?? true
        set(\.onboarding.onboardingChecklistShow, activationVisibility)
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
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoReminderStreak)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoReminderNextFireDate)
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
            defaults.removeObject(forKey: AppSettingsKeys.Profile.profilePhotoData)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.reminders)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.lastLogDate)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.lastPhotoDate)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoReminderStreak)
            defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoReminderNextFireDate)
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
            write(profile.userName, forKey: AppSettingsKeys.Profile.userName)
            write(profile.userAge, forKey: AppSettingsKeys.Profile.userAge)
            write(profile.userGender, forKey: AppSettingsKeys.Profile.userGender)
            write(profile.manualHeight, forKey: AppSettingsKeys.Profile.manualHeight)
            write(profile.unitsSystem, forKey: AppSettingsKeys.Profile.unitsSystem)
            writeOptional(profile.profilePhotoData, forKey: AppSettingsKeys.Profile.profilePhotoData)

            let home = snapshot.home
            write(home.showLastPhotosOnHome, forKey: AppSettingsKeys.Home.showLastPhotosOnHome)
            write(home.showMeasurementsOnHome, forKey: AppSettingsKeys.Home.showMeasurementsOnHome)
            write(home.showHealthMetricsOnHome, forKey: AppSettingsKeys.Home.showHealthMetricsOnHome)
            write(home.showStreakOnHome, forKey: AppSettingsKeys.Home.showStreakOnHome)
            write(home.homePinnedActionRaw, forKey: AppSettingsKeys.Home.homePinnedAction)
            write(home.homeTabScrollOffset, forKey: AppSettingsKeys.Home.homeTabScrollOffset)
            write(home.homePhotoMetricSyncLastDate, forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastDate)
            write(home.homePhotoMetricSyncLastID, forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastID)
            write(home.hasReviewedTrackedMetrics, forKey: AppSettingsKeys.Home.hasReviewedTrackedMetrics)
            write(home.settingsOpenTrackedMeasurements, forKey: AppSettingsKeys.Home.settingsOpenTrackedMeasurements)
            write(home.settingsOpenReminders, forKey: AppSettingsKeys.Home.settingsOpenReminders)
            write(home.settingsOpenHomeSettings, forKey: AppSettingsKeys.Home.settingsOpenHomeSettings)
            write(home.settingsOpenProfile, forKey: AppSettingsKeys.Home.settingsOpenProfile)
            write(home.settingsOpenHealth, forKey: AppSettingsKeys.Home.settingsOpenHealth)

            let homeLayout = snapshot.homeLayout
            write(homeLayout.layoutSchemaVersion, forKey: AppSettingsKeys.Home.homeLayoutSchemaVersion)
            writeOptional(homeLayout.layoutData, forKey: AppSettingsKeys.Home.homeLayoutData)

            let onboarding = snapshot.onboarding
            write(onboarding.hasCompletedOnboarding, forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding)
            write(onboarding.onboardingFlowVersion, forKey: AppSettingsKeys.Onboarding.onboardingFlowVersion)
            write(onboarding.onboardingSkippedHealthKit, forKey: AppSettingsKeys.Onboarding.onboardingSkippedHealthKit)
            write(onboarding.onboardingSkippedReminders, forKey: AppSettingsKeys.Onboarding.onboardingSkippedReminders)
            write(onboarding.onboardingViewedICloudBackupOffer, forKey: AppSettingsKeys.Onboarding.onboardingViewedICloudBackupOffer)
            write(onboarding.onboardingSkippedICloudBackup, forKey: AppSettingsKeys.Onboarding.onboardingSkippedICloudBackup)
            write(onboarding.onboardingChecklistShow, forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow)
            write(onboarding.onboardingChecklistCollapsed, forKey: AppSettingsKeys.Onboarding.onboardingChecklistCollapsed)
            write(onboarding.onboardingChecklistHideCompleted, forKey: AppSettingsKeys.Onboarding.onboardingChecklistHideCompleted)
            write(onboarding.onboardingChecklistMetricsCompleted, forKey: AppSettingsKeys.Onboarding.onboardingChecklistMetricsCompleted)
            write(onboarding.onboardingChecklistMetricsExplored, forKey: AppSettingsKeys.Onboarding.onboardingChecklistMetricsExplored)
            write(onboarding.onboardingChecklistPremiumExplored, forKey: AppSettingsKeys.Onboarding.onboardingChecklistPremiumExplored)
            write(onboarding.onboardingPrimaryGoal, forKey: AppSettingsKeys.Onboarding.onboardingPrimaryGoal)
            write(onboarding.onboardingActivationCompleted, forKey: AppSettingsKeys.Onboarding.onboardingActivationCompleted)
            write(onboarding.activationTriggerQuickAdd, forKey: AppSettingsKeys.Onboarding.activationTriggerQuickAdd)
            write(onboarding.activationCurrentTaskID, forKey: AppSettingsKeys.Onboarding.activationCurrentTaskID)
            write(onboarding.activationCompletedTaskIDs, forKey: AppSettingsKeys.Onboarding.activationCompletedTaskIDs)
            write(onboarding.activationSkippedTaskIDs, forKey: AppSettingsKeys.Onboarding.activationSkippedTaskIDs)
            write(onboarding.activationIsDismissed, forKey: AppSettingsKeys.Onboarding.activationIsDismissed)

            let health = snapshot.health
            write(health.isSyncEnabled, forKey: AppSettingsKeys.Health.isSyncEnabled)
            write(health.healthkitLastImport, forKey: AppSettingsKeys.Health.healthkitLastImport)
            write(health.healthkitSyncWeight, forKey: AppSettingsKeys.Health.healthkitSyncWeight)
            write(health.healthkitSyncBodyFat, forKey: AppSettingsKeys.Health.healthkitSyncBodyFat)
            write(health.healthkitSyncHeight, forKey: AppSettingsKeys.Health.healthkitSyncHeight)
            write(health.healthkitSyncLeanBodyMass, forKey: AppSettingsKeys.Health.healthkitSyncLeanBodyMass)
            write(health.healthkitSyncWaist, forKey: AppSettingsKeys.Health.healthkitSyncWaist)
            write(health.healthkitInitialHistoricalImport, forKey: AppSettingsKeys.Health.healthkitInitialHistoricalImport)
            write(health.healthIndicatorsV2Migrated, forKey: AppSettingsKeys.Health.healthIndicatorsV2Migrated)

            let indicators = snapshot.indicators
            write(indicators.showWHtROnHome, forKey: AppSettingsKeys.Indicators.showWHtROnHome)
            write(indicators.showRFMOnHome, forKey: AppSettingsKeys.Indicators.showRFMOnHome)
            write(indicators.showBMIOnHome, forKey: AppSettingsKeys.Indicators.showBMIOnHome)
            write(indicators.showBodyFatOnHome, forKey: AppSettingsKeys.Indicators.showBodyFatOnHome)
            write(indicators.showLeanMassOnHome, forKey: AppSettingsKeys.Indicators.showLeanMassOnHome)
            write(indicators.showWHROnHome, forKey: AppSettingsKeys.Indicators.showWHROnHome)
            write(indicators.showWaistRiskOnHome, forKey: AppSettingsKeys.Indicators.showWaistRiskOnHome)
            write(indicators.showABSIOnHome, forKey: AppSettingsKeys.Indicators.showABSIOnHome)
            write(indicators.showBodyShapeScoreOnHome, forKey: AppSettingsKeys.Indicators.showBodyShapeScoreOnHome)
            write(indicators.showCentralFatRiskOnHome, forKey: AppSettingsKeys.Indicators.showCentralFatRiskOnHome)
            write(indicators.showConicityOnHome, forKey: AppSettingsKeys.Indicators.showConicityOnHome)
            write(indicators.showPhysiqueSWR, forKey: AppSettingsKeys.Indicators.showPhysiqueSWR)
            write(indicators.showPhysiqueCWR, forKey: AppSettingsKeys.Indicators.showPhysiqueCWR)
            write(indicators.showPhysiqueSHR, forKey: AppSettingsKeys.Indicators.showPhysiqueSHR)
            write(indicators.showPhysiqueHWR, forKey: AppSettingsKeys.Indicators.showPhysiqueHWR)
            write(indicators.showPhysiqueBWR, forKey: AppSettingsKeys.Indicators.showPhysiqueBWR)
            write(indicators.showPhysiqueWHtR, forKey: AppSettingsKeys.Indicators.showPhysiqueWHtR)
            write(indicators.showPhysiqueBodyFat, forKey: AppSettingsKeys.Indicators.showPhysiqueBodyFat)
            write(indicators.showPhysiqueRFM, forKey: AppSettingsKeys.Indicators.showPhysiqueRFM)

            let experience = snapshot.experience
            write(experience.appAppearance, forKey: AppSettingsKeys.Experience.appAppearance)
            write(experience.animationsEnabled, forKey: AppSettingsKeys.Experience.animationsEnabled)
            write(experience.hapticsEnabled, forKey: AppSettingsKeys.Experience.hapticsEnabled)
            write(experience.appLanguage, forKey: AppSettingsKeys.Experience.appLanguage)
            write(experience.quickAddHintDismissed, forKey: AppSettingsKeys.Experience.quickAddHintDismissed)
            write(experience.photosFilterTag, forKey: AppSettingsKeys.Experience.photosFilterTag)
            write(experience.saveUnchangedQuickAdd, forKey: AppSettingsKeys.Experience.saveUnchangedQuickAdd)
            write(experience.hasCustomizedMetrics, forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)
            write(experience.lastSeenWhatsNewVersion, forKey: AppSettingsKeys.Experience.lastSeenWhatsNewVersion)

            let premium = snapshot.premium
            write(premium.premiumEntitlement, forKey: AppSettingsKeys.Premium.entitlement)
            write(premium.premiumFirstLaunchDate, forKey: AppSettingsKeys.Premium.firstLaunchDate)
            write(premium.premiumLastNagDate, forKey: AppSettingsKeys.Premium.lastNagDate)
            write(premium.lastAutomaticPromptDate, forKey: AppSettingsKeys.Premium.lastAutomaticPromptDate)
            write(premium.lastAutomaticPromptKind, forKey: AppSettingsKeys.Premium.lastAutomaticPromptKind)

            let privacy = snapshot.privacy
            write(privacy.requireBiometricForPhotos, forKey: AppSettingsKeys.Privacy.requireBiometricForPhotos)

            let diagnostics = snapshot.diagnostics
            write(diagnostics.diagnosticsLoggingEnabled, forKey: AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled)
            write(diagnostics.crashReporterHasUnreported, forKey: AppSettingsKeys.Diagnostics.crashReporterHasUnreported)
            writeOptional(diagnostics.databaseEncryptionProtectionVersion, forKey: AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion)

            let notifications = snapshot.notifications
            writeOptional(notifications.measurementRemindersData, forKey: AppSettingsKeys.Notifications.reminders)
            write(notifications.notificationsEnabled, forKey: AppSettingsKeys.Notifications.notificationsEnabled)
            write(notifications.smartEnabled, forKey: AppSettingsKeys.Notifications.smartEnabled)
            write(notifications.smartDays, forKey: AppSettingsKeys.Notifications.smartDays)
            write(notifications.smartTime, forKey: AppSettingsKeys.Notifications.smartTime)
            write(notifications.lastLogDate, forKey: AppSettingsKeys.Notifications.lastLogDate)
            write(notifications.lastPhotoDate, forKey: AppSettingsKeys.Notifications.lastPhotoDate)
            write(notifications.photoRemindersEnabled, forKey: AppSettingsKeys.Notifications.photoRemindersEnabled)
            write(notifications.photoReminderStreak, forKey: AppSettingsKeys.Notifications.photoReminderStreak)
            write(notifications.photoReminderNextFireDate, forKey: AppSettingsKeys.Notifications.photoReminderNextFireDate)
            write(notifications.goalAchievedEnabled, forKey: AppSettingsKeys.Notifications.goalAchievedEnabled)
            write(notifications.importNotificationsEnabled, forKey: AppSettingsKeys.Notifications.importNotificationsEnabled)
            write(notifications.perMetricSmartEnabled, forKey: AppSettingsKeys.Notifications.perMetricSmartEnabled)
            write(notifications.aiNotificationsEnabled, forKey: AppSettingsKeys.Notifications.aiNotificationsEnabled)
            write(notifications.aiWeeklyDigestEnabled, forKey: AppSettingsKeys.Notifications.aiWeeklyDigestEnabled)
            write(notifications.aiTrendShiftEnabled, forKey: AppSettingsKeys.Notifications.aiTrendShiftEnabled)
            write(notifications.aiGoalMilestonesEnabled, forKey: AppSettingsKeys.Notifications.aiGoalMilestonesEnabled)
            write(notifications.aiRoundNumbersEnabled, forKey: AppSettingsKeys.Notifications.aiRoundNumbersEnabled)
            write(notifications.aiConsistencyEnabled, forKey: AppSettingsKeys.Notifications.aiConsistencyEnabled)
            write(notifications.aiDigestWeekday, forKey: AppSettingsKeys.Notifications.aiDigestWeekday)
            write(notifications.aiDigestTime, forKey: AppSettingsKeys.Notifications.aiDigestTime)
            writeOptional(notifications.aiLastSentTimestamps, forKey: AppSettingsKeys.Notifications.aiLastSentTimestamps)
            writeOptional(notifications.aiMutedTypes, forKey: AppSettingsKeys.Notifications.aiMutedTypes)

            let analytics = snapshot.analytics
            write(analytics.analyticsEnabled, forKey: AppSettingsKeys.Analytics.analyticsEnabled)
            write(analytics.analyticsConsentDecided, forKey: AppSettingsKeys.Analytics.analyticsConsentDecided)
            write(analytics.firstMetricAddedTracked, forKey: AppSettingsKeys.Analytics.firstMetricAddedTracked)
            write(analytics.firstPhotoAddedTracked, forKey: AppSettingsKeys.Analytics.firstPhotoAddedTracked)
            write(analytics.secondMetricAddedTracked, forKey: AppSettingsKeys.Analytics.secondMetricAddedTracked)
            write(analytics.secondPhotoAddedTracked, forKey: AppSettingsKeys.Analytics.secondPhotoAddedTracked)
            write(analytics.firstCompareSessionTracked, forKey: AppSettingsKeys.Analytics.firstCompareSessionTracked)
            write(analytics.appleIntelligenceEnabled, forKey: AppSettingsKeys.Analytics.appleIntelligenceEnabled)

            let iCloudBackup = snapshot.iCloudBackup
            write(iCloudBackup.isEnabled, forKey: AppSettingsKeys.ICloudBackup.isEnabled)
            write(iCloudBackup.lastSuccessTimestamp, forKey: AppSettingsKeys.ICloudBackup.lastSuccessTimestamp)
            write(iCloudBackup.lastErrorMessage, forKey: AppSettingsKeys.ICloudBackup.lastErrorMessage)
            write(iCloudBackup.autoRestoreCompleted, forKey: AppSettingsKeys.ICloudBackup.autoRestoreCompleted)
            write(Int(iCloudBackup.lastBackupSizeBytes), forKey: AppSettingsKeys.ICloudBackup.lastBackupSizeBytes)

            write(snapshot.internalState.settingsSchemaVersion, forKey: AppSettingsKeys.settingsSchemaVersion)

            // Mirror intent-relevant keys to App Group suite for out-of-process access
            Self.syncIntentSettings(snapshot, defaults: defaults)
        }
    }

    /// Writes only when the value differs from what `defaults` already holds.
    ///
    /// Persisting the whole snapshot on every change meant ~120 writes — and ~120
    /// `didChange` notifications' worth of churn — behind a single toggle. Comparing against
    /// `defaults` rather than a cached copy keeps this correct even when something writes a
    /// key directly, without going through the store.
    private func write<Value: Equatable>(_ value: Value, forKey key: String) {
        if let existing = defaults.object(forKey: key) as? Value, existing == value { return }
        defaults.set(value, forKey: key)
    }

    private func writeOptional<Value: Equatable>(_ value: Value?, forKey key: String) {
        let existing = defaults.object(forKey: key) as? Value
        guard existing != value else { return }
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
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
