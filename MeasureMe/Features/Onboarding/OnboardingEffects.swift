import Foundation

protocol OnboardingHealthKitAuthorizing {
    func requestAuthorization() async throws
}

extension HealthKitManager: OnboardingHealthKitAuthorizing {}

protocol OnboardingNotificationManaging: AnyObject {
    var notificationsEnabled: Bool { get set }
    var smartEnabled: Bool { get }
    var smartTime: Date { get set }

    func requestAuthorization() async -> Bool
    func loadReminders() -> [MeasurementReminder]
    func saveReminders(_ reminders: [MeasurementReminder])
    func scheduleAllReminders(_ reminders: [MeasurementReminder])
}

extension NotificationManager: OnboardingNotificationManaging {}

protocol OnboardingAnalyticsTracking {
    func track(_ signal: AnalyticsSignal)
}

struct OnboardingAnalyticsAdapter: OnboardingAnalyticsTracking {
    private let client: AnalyticsClient

    init(client: AnalyticsClient = Analytics.shared) {
        self.client = client
    }

    func track(_ signal: AnalyticsSignal) {
        client.track(signal)
    }
}

struct OnboardingReminderSeedState {
    let repeatRule: ReminderRepeat
    let reminderWeekday: Int
    let reminderTime: Date
    let reminderOnceDate: Date
    let isReminderScheduled: Bool
}

struct OnboardingEffects {
    static let live = OnboardingEffects()

    let notificationsDidChangeName: Notification.Name

    private let healthKit: OnboardingHealthKitAuthorizing
    private let notifications: OnboardingNotificationManaging
    private let analytics: OnboardingAnalyticsTracking
    private let settings: AppSettingsStore

    init(
        healthKit: OnboardingHealthKitAuthorizing? = nil,
        notifications: OnboardingNotificationManaging? = nil,
        analytics: OnboardingAnalyticsTracking? = nil,
        settings: AppSettingsStore? = nil,
        notificationsDidChangeName: Notification.Name? = nil
    ) {
        self.healthKit = healthKit ?? HealthKitManager.shared
        self.notifications = notifications ?? NotificationManager.shared
        self.analytics = analytics ?? OnboardingAnalyticsAdapter()
        self.settings = settings ?? .shared
        self.notificationsDidChangeName = notificationsDidChangeName ?? NotificationManager.notificationsDidChange
    }

    func track(_ signal: AnalyticsSignal) {
        analytics.track(signal)
    }

    func requestHealthKitAuthorization() async throws {
        try await healthKit.requestAuthorization()
    }

    func requestNotificationAuthorization() async -> Bool {
        await notifications.requestAuthorization()
    }

    func setNotificationsEnabled(_ value: Bool) {
        notifications.notificationsEnabled = value
    }

    func setSmartTime(_ date: Date) {
        notifications.smartTime = date
    }

    func loadReminderSeed(defaultWeeklyReminderDate: Date, calendar: Calendar = .current) -> OnboardingReminderSeedState {
        let reminders = notifications.loadReminders()
        if let weeklyReminder = reminders.first(where: { $0.repeatRule == .weekly }) {
            return OnboardingReminderSeedState(
                repeatRule: .weekly,
                reminderWeekday: calendar.component(.weekday, from: weeklyReminder.date),
                reminderTime: weeklyReminder.date,
                reminderOnceDate: weeklyReminder.date,
                isReminderScheduled: isReminderScheduled(reminders: reminders)
            )
        }
        if let dailyReminder = reminders.first(where: { $0.repeatRule == .daily }) {
            return OnboardingReminderSeedState(
                repeatRule: .daily,
                reminderWeekday: calendar.component(.weekday, from: dailyReminder.date),
                reminderTime: dailyReminder.date,
                reminderOnceDate: dailyReminder.date,
                isReminderScheduled: isReminderScheduled(reminders: reminders)
            )
        }
        if let onceReminder = reminders.first(where: { $0.repeatRule == .once }) {
            return OnboardingReminderSeedState(
                repeatRule: .once,
                reminderWeekday: calendar.component(.weekday, from: onceReminder.date),
                reminderTime: onceReminder.date,
                reminderOnceDate: onceReminder.date,
                isReminderScheduled: isReminderScheduled(reminders: reminders)
            )
        }
        return OnboardingReminderSeedState(
            repeatRule: .weekly,
            reminderWeekday: calendar.component(.weekday, from: defaultWeeklyReminderDate),
            reminderTime: defaultWeeklyReminderDate,
            reminderOnceDate: defaultWeeklyReminderDate,
            isReminderScheduled: isReminderScheduled(reminders: reminders)
        )
    }

    func isReminderScheduled() -> Bool {
        isReminderScheduled(reminders: notifications.loadReminders())
    }

    func upsertReminder(date: Date, repeatRule: ReminderRepeat) {
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

    func incrementWelcomeGoalSelectionStat(goalRawValue: String) {
        settings.incrementOnboardingGoalSelectionStat(for: goalRawValue)
    }

    private func isReminderScheduled(reminders: [MeasurementReminder]) -> Bool {
        let hasAnyReminder = notifications.smartEnabled || !reminders.isEmpty
        return notifications.notificationsEnabled && hasAnyReminder
    }
}
