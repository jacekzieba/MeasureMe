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
        XCTAssertTrue(store.snapshot.experience.animationsEnabled)
        XCTAssertTrue(store.snapshot.notifications.photoRemindersEnabled)
        XCTAssertTrue(store.snapshot.health.healthkitSyncWeight)
    }

    func testSetAndReloadUpdatesSnapshot() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.set("imperial", forKey: AppSettingsKeys.Profile.unitsSystem)
        store.reload()

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

    func testFallbackBoolSemanticsForFeatureFlags() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        defaults.removeObject(forKey: AppSettingsKeys.Notifications.photoRemindersEnabled)
        defaults.removeObject(forKey: AppSettingsKeys.Notifications.goalAchievedEnabled)
        defaults.removeObject(forKey: AppSettingsKeys.Notifications.importNotificationsEnabled)
        store.reload()

        XCTAssertTrue(store.snapshot.notifications.photoRemindersEnabled)
        XCTAssertTrue(store.snapshot.notifications.goalAchievedEnabled)
        XCTAssertTrue(store.snapshot.notifications.importNotificationsEnabled)
    }
}
