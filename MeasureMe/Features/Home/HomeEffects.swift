import Foundation

protocol HomeNotificationManaging: AnyObject {
    var notificationsEnabled: Bool { get set }
    var smartEnabled: Bool { get }
    var smartTime: Date { get }
    func requestAuthorization() async -> Bool
    func loadReminders() -> [MeasurementReminder]
    func saveReminders(_ reminders: [MeasurementReminder])
    func scheduleAllReminders(_ reminders: [MeasurementReminder])
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

    func requestNotificationAuthorization() async -> Bool {
        await notifications.requestAuthorization()
    }

    func setNotificationsEnabled(_ value: Bool) {
        notifications.notificationsEnabled = value
    }

    func seedTomorrowReminder(now: Date = AppClock.now, calendar: Calendar = .current) {
        let date = tomorrowReminderDate(now: now, calendar: calendar)
        upsertReminder(date: date, repeatRule: .once)
    }

    func requestHealthKitAuthorization() async throws {
        try await healthKit.requestAuthorization()
    }

    func fetchLatestBodyCompositionCached() async throws -> (bodyFat: Double?, leanMass: Double?) {
        try await healthKit.fetchLatestBodyCompositionCached(forceRefresh: false)
    }

    private func upsertReminder(date: Date, repeatRule: ReminderRepeat) {
        var reminders = notifications.loadReminders()
        if let index = reminders.firstIndex(where: { $0.repeatRule == repeatRule }) {
            let existing = reminders[index]
            reminders[index] = MeasurementReminder(id: existing.id, date: date, repeatRule: repeatRule)
        } else {
            reminders.append(MeasurementReminder(date: date, repeatRule: repeatRule))
        }
        notifications.saveReminders(reminders)
        notifications.scheduleAllReminders(reminders)
    }

    private func tomorrowReminderDate(now: Date, calendar: Calendar) -> Date {
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notifications.smartTime)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components) ?? tomorrow
    }
}
