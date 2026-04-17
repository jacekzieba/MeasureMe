import XCTest
@testable import MeasureMe

private final class HomeNotificationManagerMock: HomeNotificationManaging {
    var notificationsEnabled: Bool = false
    var smartEnabled: Bool = false
    var smartTime: Date = Date(timeIntervalSince1970: 1_700_024_400)
    var requestAuthorizationResult: Bool = true
    var reminders: [MeasurementReminder] = []
    private(set) var requestAuthorizationCallCount = 0
    private(set) var scheduledBatches: [[MeasurementReminder]] = []

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func loadReminders() -> [MeasurementReminder] {
        reminders
    }

    func saveReminders(_ reminders: [MeasurementReminder]) {
        self.reminders = reminders
    }

    func scheduleAllReminders(_ reminders: [MeasurementReminder]) {
        scheduledBatches.append(reminders)
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

    func testSeedTomorrowReminder_UsesNotificationSmartTimeAndSchedulesOnce() {
        let notifications = HomeNotificationManagerMock()
        notifications.notificationsEnabled = true
        let calendar = Calendar(identifier: .gregorian)
        notifications.smartTime = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 7, minute: 30))!
        let effects = HomeEffects(
            notifications: notifications,
            healthKit: HomeHealthKitManagerMock()
        )
        let now = calendar.date(from: DateComponents(year: 2024, month: 2, day: 10, hour: 20, minute: 15))!

        effects.seedTomorrowReminder(now: now, calendar: calendar)

        XCTAssertEqual(notifications.reminders.count, 1)
        XCTAssertEqual(notifications.reminders[0].repeatRule, .once)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notifications.reminders[0].date)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 11)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(notifications.scheduledBatches.count, 1)
    }
}
