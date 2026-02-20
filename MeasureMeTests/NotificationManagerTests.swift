/// Cel testow: Weryfikuje konfiguracje i zachowanie managera powiadomien (harmonogram i flagi).
/// Dlaczego to wazne: Zle powiadomienia obnizaja zaufanie i lamia oczekiwania uzytkownika.
/// Kryteria zaliczenia: Dodawanie/aktualizacja/odczyt ustawien dzialaja zgodnie z kontraktem.

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
    var pendingIdentifiers: [String] = []

    func requestAuthorization() async throws -> Bool {
        if let requestAuthorizationError {
            throw requestAuthorizationError
        }
        return requestAuthorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func pendingRequestIdentifiers() async -> [String] {
        pendingIdentifiers
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
            "measurement_smart_days",
            "measurement_smart_time",
            "measurement_last_log_date",
            "photo_last_log_date",
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

    /// Co sprawdza: Sprawdza scenariusz: ScheduleReminderReportsAddError.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
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

    /// Co sprawdza: Sprawdza scenariusz: ScheduleReminderClearsErrorOnSuccess.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
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

    /// Co sprawdza: Sprawdza scenariusz: CancelAllRemindersRemovesAllSavedIdentifiers.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
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

    /// Co sprawdza: Sprawdza scenariusz: ResetAllDataRemovesOwnedPendingRequestsAndDefaults.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testResetAllDataRemovesOwnedPendingRequestsAndDefaults() async {
        let center = MockNotificationCenterClient()
        center.pendingIdentifiers = [
            "measurement_reminder_a",
            "measurement_smart_reminder",
            "goal_achieved_weight_123_notification",
            "some_other_app_notification"
        ]
        let manager = makeManager(center: center)
        manager.notificationsEnabled = true
        manager.smartEnabled = true
        manager.smartDays = 9
        manager.saveReminders([MeasurementReminder(id: "a", date: .now.addingTimeInterval(3600), repeatRule: .once)])

        await manager.resetAllData()

        XCTAssertTrue(center.removedIdentifiers.contains("measurement_reminder_a"))
        XCTAssertTrue(center.removedIdentifiers.contains("measurement_smart_reminder"))
        XCTAssertTrue(center.removedIdentifiers.contains("goal_achieved_weight_123_notification"))
        XCTAssertFalse(center.removedIdentifiers.contains("some_other_app_notification"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "measurement_notifications_enabled"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "measurement_smart_enabled"))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "measurement_smart_days"), 0)
        XCTAssertNil(UserDefaults.standard.data(forKey: "measurement_reminders"))
    }
}
