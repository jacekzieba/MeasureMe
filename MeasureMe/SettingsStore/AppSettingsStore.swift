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
    private let snapshotRefreshDelay: DispatchTimeInterval = .milliseconds(10)

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
                DispatchQueue.main.async { [weak self] in
                    self?.set(keyPath, newValue)
                }
            }
        )
    }

    func set<Value>(_ keyPath: WritableKeyPath<AppSettingsSnapshot, Value>, _ value: Value) {
        var updatedSnapshot = snapshot
        updatedSnapshot[keyPath: keyPath] = value
        persistSnapshot(updatedSnapshot)
        scheduleSnapshotRefresh()
    }

    func reload() {
        scheduleSnapshotRefresh()
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
            defaults.set(home.homeTabScrollOffset, forKey: AppSettingsKeys.Home.homeTabScrollOffset)
            defaults.set(home.homePhotoMetricSyncLastDate, forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastDate)
            defaults.set(home.homePhotoMetricSyncLastID, forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastID)
            defaults.set(home.settingsOpenTrackedMeasurements, forKey: AppSettingsKeys.Home.settingsOpenTrackedMeasurements)
            defaults.set(home.settingsOpenReminders, forKey: AppSettingsKeys.Home.settingsOpenReminders)

            let onboarding = snapshot.onboarding
            defaults.set(onboarding.hasCompletedOnboarding, forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding)
            defaults.set(onboarding.onboardingSkippedHealthKit, forKey: AppSettingsKeys.Onboarding.onboardingSkippedHealthKit)
            defaults.set(onboarding.onboardingSkippedReminders, forKey: AppSettingsKeys.Onboarding.onboardingSkippedReminders)
            defaults.set(onboarding.onboardingChecklistShow, forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow)
            defaults.set(onboarding.onboardingChecklistCollapsed, forKey: AppSettingsKeys.Onboarding.onboardingChecklistCollapsed)
            defaults.set(onboarding.onboardingChecklistHideCompleted, forKey: AppSettingsKeys.Onboarding.onboardingChecklistHideCompleted)
            defaults.set(onboarding.onboardingChecklistMetricsCompleted, forKey: AppSettingsKeys.Onboarding.onboardingChecklistMetricsCompleted)
            defaults.set(onboarding.onboardingChecklistPremiumExplored, forKey: AppSettingsKeys.Onboarding.onboardingChecklistPremiumExplored)
            defaults.set(onboarding.onboardingPrimaryGoal, forKey: AppSettingsKeys.Onboarding.onboardingPrimaryGoal)

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
            defaults.set(experience.animationsEnabled, forKey: AppSettingsKeys.Experience.animationsEnabled)
            defaults.set(experience.hapticsEnabled, forKey: AppSettingsKeys.Experience.hapticsEnabled)
            defaults.set(experience.appLanguage, forKey: AppSettingsKeys.Experience.appLanguage)
            defaults.set(experience.quickAddHintDismissed, forKey: AppSettingsKeys.Experience.quickAddHintDismissed)
            defaults.set(experience.photosFilterTag, forKey: AppSettingsKeys.Experience.photosFilterTag)
            defaults.set(experience.saveUnchangedQuickAdd, forKey: AppSettingsKeys.Experience.saveUnchangedQuickAdd)

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

            let analytics = snapshot.analytics
            defaults.set(analytics.analyticsEnabled, forKey: AppSettingsKeys.Analytics.analyticsEnabled)
            defaults.set(analytics.firstMetricAddedTracked, forKey: AppSettingsKeys.Analytics.firstMetricAddedTracked)
            defaults.set(analytics.firstPhotoAddedTracked, forKey: AppSettingsKeys.Analytics.firstPhotoAddedTracked)
            defaults.set(analytics.appleIntelligenceEnabled, forKey: AppSettingsKeys.Analytics.appleIntelligenceEnabled)

            defaults.set(snapshot.internalState.settingsSchemaVersion, forKey: AppSettingsKeys.settingsSchemaVersion)
        }
    }

    private func shouldHandleDefaultsDidChange() -> Bool {
        defaultsWriteDepth == 0 && !suppressObserverUntilNextRunLoop
    }

    private func scheduleSnapshotRefresh() {
        guard !isSnapshotRefreshScheduled else { return }
        isSnapshotRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + snapshotRefreshDelay) { [weak self] in
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
            DispatchQueue.main.async { [weak self] in
                self?.suppressObserverUntilNextRunLoop = false
            }
        }

        if scheduleSnapshotRefreshAfterWrite {
            scheduleSnapshotRefresh()
        }
    }
}
