import Foundation

protocol HomeNotificationManaging: AnyObject {
    var notificationsEnabled: Bool { get }
    var smartEnabled: Bool { get }
    func loadReminders() -> [MeasurementReminder]
}

extension NotificationManager: HomeNotificationManaging {}

protocol HomeHealthKitManaging: AnyObject {
    func requestAuthorization() async throws
    func fetchLatestBodyCompositionCached(forceRefresh: Bool) async throws -> (bodyFat: Double?, leanMass: Double?)
}

extension HealthKitManager: HomeHealthKitManaging {}

struct HomeEffects {
    static let live = HomeEffects()

    private let notifications: HomeNotificationManaging
    private let healthKit: HomeHealthKitManaging

    init(
        notifications: HomeNotificationManaging? = nil,
        healthKit: HomeHealthKitManaging? = nil
    ) {
        self.notifications = notifications ?? NotificationManager.shared
        self.healthKit = healthKit ?? HealthKitManager.shared
    }

    func reminderChecklistCompleted() -> Bool {
        if UITestArgument.isPresent(.checklistNeedsReminders) {
            return false
        }
        let reminders = notifications.loadReminders()
        let hasAnyReminder = notifications.smartEnabled || !reminders.isEmpty
        return notifications.notificationsEnabled && hasAnyReminder
    }

    func requestHealthKitAuthorization() async throws {
        try await healthKit.requestAuthorization()
    }

    func fetchLatestBodyCompositionCached() async throws -> (bodyFat: Double?, leanMass: Double?) {
        try await healthKit.fetchLatestBodyCompositionCached(forceRefresh: false)
    }
}
