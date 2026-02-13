import XCTest
import UserNotifications
@testable import MeasureMe

private final class MockNotificationCenterClient: NotificationCenterClient {
    var requestAuthorizationResult = true
    var requestAuthorizationError: Error?
    var authorizationStatusValue: UNAuthorizationStatus = .authorized
    var completionAddError: Error?
    var asyncAddError: Error?
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedIdentifiers: [String] = []

    func requestAuthorization() async throws -> Bool {
        if let requestAuthorizationError {
            throw requestAuthorizationError
        }
        return requestAuthorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        addedIdentifiers.append(request.identifier)
        completion(completionAddError)
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedIdentifiers.append(request.identifier)
        if let asyncAddError {
            throw asyncAddError
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

@MainActor
final class NotificationManagerTests: XCTestCase {
    private static var retainedManagers: [NotificationManager] = []

    private func resetNotificationDefaults() {
        let defaults = UserDefaults.standard
        [
            "measurement_reminders",
            "measurement_notifications_enabled",
            "measurement_smart_enabled",
            "measurement_photo_reminders_enabled",
            "measurement_import_notifications_enabled",
            "measurement_goal_achieved_enabled"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    override func setUp() {
        super.setUp()
        resetNotificationDefaults()
    }

    override func tearDown() {
        resetNotificationDefaults()
        super.tearDown()
    }

    private func makeManager(center: NotificationCenterClient) -> NotificationManager {
        let manager = NotificationManager(center: center)
        Self.retainedManagers.append(manager)
        return manager
    }

    func testScheduleReminderReportsAddError() async {
        let center = MockNotificationCenterClient()
        center.completionAddError = NSError(domain: "test", code: 1)
        let manager = makeManager(center: center)
        manager.notificationsEnabled = true

        manager.scheduleReminder(MeasurementReminder(date: .now.addingTimeInterval(3600), repeatRule: .once))
        await Task.yield()

        XCTAssertNotNil(manager.lastSchedulingError)
        XCTAssertEqual(center.addedIdentifiers.count, 1)
    }

    func testScheduleReminderClearsErrorOnSuccess() async {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)
        manager.notificationsEnabled = true

        center.completionAddError = NSError(domain: "test", code: 2)
        manager.scheduleReminder(MeasurementReminder(date: .now.addingTimeInterval(3600), repeatRule: .once))
        await Task.yield()
        XCTAssertNotNil(manager.lastSchedulingError)

        center.completionAddError = nil
        manager.scheduleReminder(MeasurementReminder(date: .now.addingTimeInterval(7200), repeatRule: .once))
        await Task.yield()
        XCTAssertNil(manager.lastSchedulingError)
    }

    func testCancelAllRemindersRemovesAllSavedIdentifiers() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)
        manager.notificationsEnabled = true

        let reminders = [
            MeasurementReminder(id: "r1", date: .now.addingTimeInterval(3600), repeatRule: .once),
            MeasurementReminder(id: "r2", date: .now.addingTimeInterval(7200), repeatRule: .daily)
        ]
        manager.saveReminders(reminders)
        manager.cancelAllReminders()

        XCTAssertTrue(center.removedIdentifiers.contains("measurement_reminder_r1"))
        XCTAssertTrue(center.removedIdentifiers.contains("measurement_reminder_r2"))
    }
}
