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
    private var defaults: UserDefaults!
    private var settings: AppSettingsStore!

    private func resetNotificationDefaults() {
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
        let suiteName = "NotificationManagerTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettingsStore(defaults: defaults)
        resetNotificationDefaults()
    }

    override func tearDown() {
        resetNotificationDefaults()
        defaults.removePersistentDomain(forName: "NotificationManagerTests.\(name)")
        settings = nil
        super.tearDown()
    }

    private func makeManager(center: NotificationCenterClient) -> NotificationManager {
        let manager = NotificationManager(center: center, settings: settings)
        Self.retainedManagers.append(manager)
        return manager
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        _ condition: @autoclosure () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    /// Co sprawdza: Sprawdza scenariusz: ScheduleReminderReportsAddError.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testScheduleReminderReportsAddError() async {
        let center = MockNotificationCenterClient()
        center.completionAddError = NSError(domain: "test", code: 1)
        let manager = makeManager(center: center)
        manager.notificationsEnabled = true
        await waitUntil(manager.notificationsEnabled)

        manager.scheduleReminder(MeasurementReminder(date: .now.addingTimeInterval(3600), repeatRule: .once))
        await waitUntil(center.addedIdentifiers.count == 1)
        await waitUntil(manager.lastSchedulingError != nil)

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
        await waitUntil(manager.notificationsEnabled)

        center.completionAddError = NSError(domain: "test", code: 2)
        manager.scheduleReminder(MeasurementReminder(date: .now.addingTimeInterval(3600), repeatRule: .once))
        await waitUntil(manager.lastSchedulingError != nil)
        XCTAssertNotNil(manager.lastSchedulingError)

        center.completionAddError = nil
        manager.scheduleReminder(MeasurementReminder(date: .now.addingTimeInterval(7200), repeatRule: .once))
        await waitUntil(manager.lastSchedulingError == nil)
        XCTAssertNil(manager.lastSchedulingError)
    }

    /// Co sprawdza: Sprawdza scenariusz: CancelAllRemindersRemovesAllSavedIdentifiers.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testCancelAllRemindersRemovesAllSavedIdentifiers() async {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)
        manager.notificationsEnabled = true
        await waitUntil(manager.notificationsEnabled)

        let reminders = [
            MeasurementReminder(id: "r1", date: .now.addingTimeInterval(3600), repeatRule: .once),
            MeasurementReminder(id: "r2", date: .now.addingTimeInterval(7200), repeatRule: .daily)
        ]
        manager.saveReminders(reminders)
        await waitUntil(manager.loadReminders().count == reminders.count)
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
        await waitUntil(!settings.snapshot.notifications.notificationsEnabled)
        XCTAssertFalse(settings.snapshot.notifications.notificationsEnabled)
        XCTAssertFalse(settings.snapshot.notifications.smartEnabled)
        XCTAssertEqual(settings.snapshot.notifications.smartDays, 0)
        XCTAssertNil(settings.snapshot.notifications.measurementRemindersData)
    }

    // MARK: - Per-Metric recordMeasurement

    func testRecordMeasurementWithKinds_UpdatesLastLogDate() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        manager.recordMeasurement(kinds: [.weight, .waist], date: testDate)

        XCTAssertEqual(manager.lastLogDate, testDate)
    }

    func testRecordMeasurementWithKinds_PersistsPerMetricDates() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        manager.recordMeasurement(kinds: [.weight, .waist], date: testDate)

        // Read back per-metric dates from settings
        guard let data = settings.data(forKey: AppSettingsKeys.Notifications.perMetricLastDates),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            XCTFail("Per-metric last dates not persisted")
            return
        }

        XCTAssertEqual(dict["weight"], testDate.timeIntervalSince1970)
        XCTAssertEqual(dict["waist"], testDate.timeIntervalSince1970)
        XCTAssertNil(dict["bodyFat"])
    }

    func testRecordMeasurementWithKinds_DoesNotOverwriteNewerDate() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        let newerDate = Date(timeIntervalSince1970: 1_700_100_000)
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)

        manager.recordMeasurement(kinds: [.weight], date: newerDate)
        manager.recordMeasurement(kinds: [.weight], date: olderDate)

        guard let data = settings.data(forKey: AppSettingsKeys.Notifications.perMetricLastDates),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            XCTFail("Per-metric last dates not persisted")
            return
        }

        XCTAssertEqual(dict["weight"], newerDate.timeIntervalSince1970)
    }

    func testRecordMeasurementWithKinds_CancelsSmartNotification() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        manager.recordMeasurement(kinds: [.weight], date: .now)

        XCTAssertTrue(center.removedIdentifiers.contains("measurement_smart_reminder"))
    }

    // MARK: - perMetricSmartEnabled

    func testPerMetricSmartEnabled_DefaultsToTrue() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        XCTAssertTrue(manager.perMetricSmartEnabled)
    }

    func testPerMetricSmartEnabled_PersistsToggle() {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        manager.perMetricSmartEnabled = false
        XCTAssertFalse(manager.perMetricSmartEnabled)
        XCTAssertFalse(settings.snapshot.notifications.perMetricSmartEnabled)
    }

    // MARK: - resetAllData: Smart Metric Notifications

    func testResetAllData_RemovesSmartMetricNotifications() async {
        let center = MockNotificationCenterClient()
        center.pendingIdentifiers = [
            "smart_metric_stale_weight",
            "smart_metric_pattern_waist",
            "measurement_smart_reminder",
            "some_other_notification"
        ]
        let manager = makeManager(center: center)

        await manager.resetAllData()

        XCTAssertTrue(center.removedIdentifiers.contains("smart_metric_stale_weight"))
        XCTAssertTrue(center.removedIdentifiers.contains("smart_metric_pattern_waist"))
        XCTAssertTrue(center.removedIdentifiers.contains("measurement_smart_reminder"))
        XCTAssertFalse(center.removedIdentifiers.contains("some_other_notification"))
    }

    func testResetAllData_ClearsPerMetricSettingsKeys() async {
        let center = MockNotificationCenterClient()
        let manager = makeManager(center: center)

        // Set some per-metric state
        manager.recordMeasurement(kinds: [.weight], date: .now)
        settings.set("weight", forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)
        settings.set(Date.now.timeIntervalSince1970, forKey: AppSettingsKeys.Notifications.smartLastNotificationDate)

        await manager.resetAllData()

        XCTAssertNil(settings.data(forKey: AppSettingsKeys.Notifications.perMetricLastDates))
        XCTAssertNil(settings.string(forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric))
        XCTAssertEqual(settings.double(forKey: AppSettingsKeys.Notifications.smartLastNotificationDate), 0)
    }
}
