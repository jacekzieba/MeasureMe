import XCTest
@testable import MeasureMe

private final class HomeNotificationManagerMock: HomeNotificationManaging {
    var notificationsEnabled: Bool = false
    var smartEnabled: Bool = false
    var reminders: [MeasurementReminder] = []

    func loadReminders() -> [MeasurementReminder] {
        reminders
    }
}

private final class HomeHealthKitManagerMock: HomeHealthKitManaging {
    private(set) var requestAuthorizationCallCount = 0
    var latestComposition: (bodyFat: Double?, leanMass: Double?) = (nil, nil)

    func requestAuthorization() async throws {
        requestAuthorizationCallCount += 1
    }

    func fetchLatestBodyCompositionCached(forceRefresh: Bool) async throws -> (bodyFat: Double?, leanMass: Double?) {
        latestComposition
    }
}

@MainActor
final class HomeEffectsTests: XCTestCase {
    func testReminderChecklistCompleted_UsesNotificationState() {
        let notifications = HomeNotificationManagerMock()
        notifications.notificationsEnabled = true
        notifications.smartEnabled = false
        notifications.reminders = [
            MeasurementReminder(
                id: "weekly",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                repeatRule: .weekly
            )
        ]
        let effects = HomeEffects(
            notifications: notifications,
            healthKit: HomeHealthKitManagerMock()
        )

        XCTAssertTrue(effects.reminderChecklistCompleted())
    }

    func testReminderChecklistCompleted_ReturnsFalseWhenNotificationsOff() {
        let notifications = HomeNotificationManagerMock()
        notifications.notificationsEnabled = false
        notifications.smartEnabled = true
        let effects = HomeEffects(
            notifications: notifications,
            healthKit: HomeHealthKitManagerMock()
        )

        XCTAssertFalse(effects.reminderChecklistCompleted())
    }

    func testHealthKitEffects_ForwardToInjectedManager() async throws {
        let healthKit = HomeHealthKitManagerMock()
        healthKit.latestComposition = (bodyFat: 18.5, leanMass: 61.2)
        let effects = HomeEffects(
            notifications: HomeNotificationManagerMock(),
            healthKit: healthKit
        )

        try await effects.requestHealthKitAuthorization()
        let composition = try await effects.fetchLatestBodyCompositionCached()

        XCTAssertEqual(healthKit.requestAuthorizationCallCount, 1)
        XCTAssertEqual(composition.bodyFat, 18.5)
        XCTAssertEqual(composition.leanMass, 61.2)
    }
}
