import XCTest
import Combine
@testable import MeasureMe

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    private func makeDefaults(suffix: String = UUID().uuidString) -> UserDefaults {
        let suite = "AppSettingsStoreTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testRegisteredDefaultsAreAvailableInSnapshot() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.snapshot.profile.unitsSystem, "metric")
        XCTAssertEqual(store.snapshot.experience.appLanguage, "system")
        XCTAssertEqual(store.snapshot.experience.appAppearance, AppAppearance.dark.rawValue)
        XCTAssertTrue(store.snapshot.experience.animationsEnabled)
        XCTAssertTrue(store.snapshot.notifications.photoRemindersEnabled)
        XCTAssertTrue(store.snapshot.health.healthkitSyncWeight)
        XCTAssertFalse(store.snapshot.iCloudBackup.isEnabled)
        XCTAssertFalse(store.snapshot.iCloudBackup.autoRestoreCompleted)
        XCTAssertFalse(store.snapshot.onboarding.onboardingViewedICloudBackupOffer)
        XCTAssertFalse(store.snapshot.onboarding.onboardingSkippedICloudBackup)
        XCTAssertTrue(store.snapshot.notifications.aiNotificationsEnabled)
        XCTAssertTrue(store.snapshot.notifications.aiWeeklyDigestEnabled)
        XCTAssertTrue(store.snapshot.notifications.aiTrendShiftEnabled)
        XCTAssertTrue(store.snapshot.notifications.aiGoalMilestonesEnabled)
        XCTAssertTrue(store.snapshot.notifications.aiRoundNumbersEnabled)
        XCTAssertTrue(store.snapshot.notifications.aiConsistencyEnabled)
        XCTAssertEqual(store.snapshot.notifications.aiDigestWeekday, 1)
    }

    func testSetAndReloadUpdatesSnapshot() async {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.set("imperial", forKey: AppSettingsKeys.Profile.unitsSystem)
        store.reload()

        for _ in 0..<50 where store.snapshot.profile.unitsSystem != "imperial" {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(store.snapshot.profile.unitsSystem, "imperial")
    }

    func testPublishesOnChange() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let expectation = expectation(description: "objectWillChange")
        expectation.assertForOverFulfill = false

        store.objectWillChange
            .prefix(1)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        store.set(true, forKey: AppSettingsKeys.Health.isSyncEnabled)

        wait(for: [expectation], timeout: 1.0)
    }

    func testMigratesLegacyUnitsSystemKey() {
        let defaults = makeDefaults()
        defaults.set("imperial", forKey: AppSettingsKeys.Profile.legacyUnitsSystem)
        defaults.removeObject(forKey: AppSettingsKeys.Profile.unitsSystem)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.string(forKey: AppSettingsKeys.Profile.unitsSystem), "imperial")
        XCTAssertNil(store.object(forKey: AppSettingsKeys.Profile.legacyUnitsSystem))
        XCTAssertEqual(store.snapshot.profile.unitsSystem, "imperial")
    }

    func testDynamicHealthKitKeys() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        let anchor = Data([1, 2, 3])
        store.setHealthKitAnchor(anchor, for: .weight)
        XCTAssertEqual(store.healthKitAnchor(for: .weight), anchor)

        let date = Date(timeIntervalSince1970: 1234)
        store.setLastProcessedHealthDate(date, for: .weight)
        XCTAssertEqual(store.lastProcessedHealthDate(for: .weight)?.timeIntervalSince1970 ?? 0, 1234, accuracy: 0.001)

        store.setLastProcessedHealthDate(nil, for: .weight)
        XCTAssertNil(store.lastProcessedHealthDate(for: .weight))
    }

    func testGoalAchievementPrefixFlags() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertFalse(store.goalAchievedFlag(for: "goal-1"))
        store.setGoalAchievedFlag(true, for: "goal-1")
        XCTAssertTrue(store.goalAchievedFlag(for: "goal-1"))
    }

    func testHomeLayoutIsMigratedFromLegacyFlags() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: AppSettingsKeys.Home.showMeasurementsOnHome)
        defaults.set(true, forKey: AppSettingsKeys.Home.showLastPhotosOnHome)
        defaults.set(false, forKey: AppSettingsKeys.Home.showHealthMetricsOnHome)
        defaults.set(false, forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow)

        let store = AppSettingsStore(defaults: defaults)
        let layout = store.homeLayoutSnapshot()

        XCTAssertEqual(layout.schemaVersion, HomeLayoutSnapshot.currentSchemaVersion)
        XCTAssertEqual(layout.item(for: .keyMetrics)?.isVisible, false)
        XCTAssertEqual(layout.item(for: .recentPhotos)?.isVisible, true)
        XCTAssertEqual(layout.item(for: .healthSummary)?.isVisible, false)
        XCTAssertEqual(layout.item(for: .activationHub)?.isVisible, false)
        XCTAssertNotNil(store.data(forKey: AppSettingsKeys.Home.homeLayoutData))
    }

    func testSetHomeModuleVisibilitySynchronizesLegacyFlags() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.setHomeModuleVisibility(false, for: .recentPhotos)
        store.setHomeModuleVisibility(false, for: .activationHub)

        XCTAssertFalse(store.snapshot.home.showLastPhotosOnHome)
        XCTAssertFalse(store.snapshot.onboarding.onboardingChecklistShow)
        XCTAssertEqual(store.homeLayoutSnapshot().item(for: .recentPhotos)?.isVisible, false)
        XCTAssertEqual(store.homeLayoutSnapshot().item(for: .activationHub)?.isVisible, false)
    }

    func testPinnedHomeActionPersistsAndReloads() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.setHomePinnedAction(.comparePhotos)

        XCTAssertEqual(store.homePinnedAction(), .comparePhotos)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.Home.homePinnedAction), HomePinnedAction.comparePhotos.rawValue)
    }

    func testHomePinnedActionFallsBackToMeasurementWhenLegacyChecklistWasVisible() {
        let defaults = makeDefaults()
        defaults.removeObject(forKey: AppSettingsKeys.Home.homePinnedAction)
        defaults.set(true, forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow)

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.homePinnedAction(default: .addMeasurement), .addMeasurement)
    }

    func testFallbackBoolSemanticsForFeatureFlags() async {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoRemindersEnabled)
        defaults.removeObject(forKey: AppSettingsKeys.Notifications.goalAchievedEnabled)
        defaults.removeObject(forKey: AppSettingsKeys.Notifications.importNotificationsEnabled)
        store.reload()

        for _ in 0..<50 where !store.snapshot.notifications.photoRemindersEnabled {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(store.snapshot.notifications.photoRemindersEnabled)
        XCTAssertTrue(store.snapshot.notifications.goalAchievedEnabled)
        XCTAssertTrue(store.snapshot.notifications.importNotificationsEnabled)
    }

    func testClearHealthKitSyncMetadataClearsSyncStateAndDynamicKeys() async {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.set(\.health.isSyncEnabled, true)
        store.set(\.health.healthkitLastImport, 1234)
        store.set(\.health.healthkitInitialHistoricalImport, true)
        store.setHealthKitAnchor(Data([7, 8, 9]), for: .weight)
        store.setLastProcessedHealthDate(Date(timeIntervalSince1970: 4567), for: .weight)

        store.clearHealthKitSyncMetadata()

        for _ in 0..<50 where store.snapshot.health.isSyncEnabled {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(store.snapshot.health.isSyncEnabled)
        XCTAssertEqual(store.snapshot.health.healthkitLastImport, 0)
        XCTAssertFalse(store.snapshot.health.healthkitInitialHistoricalImport)
        XCTAssertNil(store.healthKitAnchor(for: .weight))
        XCTAssertNil(store.lastProcessedHealthDate(for: .weight))
    }

    func testResetNotificationSettingsToDefaultsClearsAIState() throws {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let timestamps = try JSONEncoder().encode(["weeklyDigest": 123.0])
        let mutedKinds = try JSONEncoder().encode([AINotificationKind.weeklyDigest.rawValue])

        store.set(\.notifications.aiNotificationsEnabled, false)
        store.set(\.notifications.aiDigestWeekday, 5)
        store.set(\.notifications.aiDigestTime, 456)
        store.set(\.notifications.aiLastSentTimestamps, timestamps)
        store.set(\.notifications.aiMutedTypes, mutedKinds)

        store.resetNotificationSettingsToDefaults()
        store.forceReloadSnapshot()

        XCTAssertTrue(store.snapshot.notifications.aiNotificationsEnabled)
        XCTAssertEqual(store.snapshot.notifications.aiDigestWeekday, 1)
        XCTAssertEqual(store.snapshot.notifications.aiDigestTime, 0)
        XCTAssertNil(store.snapshot.notifications.aiLastSentTimestamps)
        XCTAssertNil(store.snapshot.notifications.aiMutedTypes)
    }

    func testSyncIntentSettingsMirrorsUnitsAndMetricFlagsToAppGroup() async {
        let appGroupSuite = "group.com.jacek.measureme"
        let appGroupDefaults = UserDefaults(suiteName: appGroupSuite)!
        // Clean slate for App Group keys
        appGroupDefaults.removeObject(forKey: AppSettingsKeys.Profile.unitsSystem)
        for key in AppSettingsKeys.Metrics.allEnabledKeys {
            appGroupDefaults.removeObject(forKey: key)
        }
        defer {
            appGroupDefaults.removeObject(forKey: AppSettingsKeys.Profile.unitsSystem)
            for key in AppSettingsKeys.Metrics.allEnabledKeys {
                appGroupDefaults.removeObject(forKey: key)
            }
        }

        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        // Act: change units and enable a metric
        store.set(\.profile.unitsSystem, "imperial")
        defaults.set(true, forKey: AppSettingsKeys.Metrics.weightEnabled)
        defaults.set(true, forKey: AppSettingsKeys.Metrics.waistEnabled)
        store.set(\.experience.appAppearance, AppAppearance.light.rawValue)
        // Trigger persist which calls syncIntentSettings
        store.set(\.profile.unitsSystem, "imperial")

        // Assert: App Group suite should mirror the values
        XCTAssertEqual(appGroupDefaults.string(forKey: AppSettingsKeys.Profile.unitsSystem), "imperial")
        XCTAssertEqual(appGroupDefaults.string(forKey: AppSettingsKeys.Experience.appAppearance), AppAppearance.light.rawValue)
        XCTAssertTrue(appGroupDefaults.bool(forKey: AppSettingsKeys.Metrics.weightEnabled))
        XCTAssertTrue(appGroupDefaults.bool(forKey: AppSettingsKeys.Metrics.waistEnabled))
        XCTAssertFalse(appGroupDefaults.bool(forKey: AppSettingsKeys.Metrics.neckEnabled))
    }

    func testAppearanceSettingPersistsAndReloads() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.set(\.experience.appAppearance, AppAppearance.dark.rawValue)
        store.reload()

        XCTAssertEqual(store.snapshot.experience.appAppearance, AppAppearance.dark.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.Experience.appAppearance), AppAppearance.dark.rawValue)
    }

    func testClearUserDataDefaultsClearsProfileAndNotificationState() async {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.set(\.profile.userName, "Alice")
        store.set(\.profile.userAge, 37)
        store.set(\.profile.userGender, "female")
        store.set(\.profile.manualHeight, 170)
        store.set(\.notifications.measurementRemindersData, Data([1, 2, 3]))
        store.set(\.notifications.lastLogDate, 111)
        store.set(\.notifications.lastPhotoDate, 222)
        store.set(\.diagnostics.diagnosticsLoggingEnabled, false)

        store.clearUserDataDefaults()

        for _ in 0..<50 where store.snapshot.profile.userName != "" {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(store.snapshot.profile.userName, "")
        XCTAssertEqual(store.snapshot.profile.userAge, 0)
        XCTAssertEqual(store.snapshot.profile.userGender, "notSpecified")
        XCTAssertEqual(store.snapshot.profile.manualHeight, 0)
        XCTAssertNil(store.snapshot.notifications.measurementRemindersData)
        XCTAssertEqual(store.snapshot.notifications.lastLogDate, 0)
        XCTAssertEqual(store.snapshot.notifications.lastPhotoDate, 0)
        XCTAssertTrue(store.snapshot.diagnostics.diagnosticsLoggingEnabled)
    }
}
