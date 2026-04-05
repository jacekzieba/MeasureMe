import Foundation
import SwiftData

protocol OnboardingHealthKitAuthorizing {
    func requestAuthorization() async throws
    func fetchDateOfBirth() throws -> Date?
    func fetchLatestHeightInCentimeters() async throws -> (value: Double, date: Date)?
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

    private let healthKit: OnboardingHealthKitAuthorizing
    private let notifications: OnboardingNotificationManaging
    private let analytics: OnboardingAnalyticsTracking
    private let settings: AppSettingsStore

    init(
        healthKit: OnboardingHealthKitAuthorizing? = nil,
        notifications: OnboardingNotificationManaging? = nil,
        analytics: OnboardingAnalyticsTracking? = nil,
        settings: AppSettingsStore? = nil
    ) {
        self.healthKit = healthKit ?? HealthKitManager.shared
        self.notifications = notifications ?? NotificationManager.shared
        self.analytics = analytics ?? OnboardingAnalyticsAdapter()
        self.settings = settings ?? .shared
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

    func importProfileFromHealthIfAvailable() async -> (age: Int?, height: Double?) {
        // Fetch birth date (synchronous) and latest height (asynchronous) without wrapping in Result
        let birthDate: Date? = try? healthKit.fetchDateOfBirth()
        let latestHeight = try? await healthKit.fetchLatestHeightInCentimeters()

        let age = birthDate.flatMap(HealthKitManager.calculateAge(from:))
        let height = latestHeight?.value
        return (age: age, height: height)
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

    // MARK: - First measurement (onboarding v3)

    /// Saves first measurement entries during onboarding using QuickAddSaveService.
    func saveFirstMeasurement(entries: [QuickAddSaveService.Entry], date: Date, unitsSystem: String, context: ModelContext) throws {
        let service = QuickAddSaveService(context: context)
        try service.save(entries: entries, date: date, unitsSystem: unitsSystem)
        analytics.track(.onboardingFirstMeasurementSaved)
    }

    func incrementWelcomeGoalSelectionStat(goalRawValue: String) {
        settings.incrementOnboardingGoalSelectionStat(for: goalRawValue)
    }

    // MARK: - Goal metric pack

    /// Returns true if the user has already manually customized their metrics selection.
    func hasCustomizedMetrics() -> Bool {
        settings.bool(forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)
    }

    /// Enables the recommended metrics for the given kinds and sets the home key metrics.
    /// Does NOT mark metrics as "customized by user" — this is an automated default.
    func applyMetricPack(_ kinds: [MetricKind]) {
        guard !kinds.isEmpty else { return }
        for kind in kinds {
            settings.set(true, forKey: enabledKey(for: kind))
        }
        let keyMetrics = Array(kinds.prefix(3)).map(\.rawValue)
        settings.set(keyMetrics, forKey: "home_key_metrics")
    }

    private func enabledKey(for kind: MetricKind) -> String {
        switch kind {
        case .weight:       return "metric_weight_enabled"
        case .bodyFat:      return "metric_bodyFat_enabled"
        case .height:       return "metric_height_enabled"
        case .leanBodyMass: return "metric_nonFatMass_enabled"
        case .waist:        return "metric_waist_enabled"
        case .neck:         return "metric_neck_enabled"
        case .shoulders:    return "metric_shoulders_enabled"
        case .bust:         return "metric_bust_enabled"
        case .chest:        return "metric_chest_enabled"
        case .leftBicep:    return "metric_leftBicep_enabled"
        case .rightBicep:   return "metric_rightBicep_enabled"
        case .leftForearm:  return "metric_leftForearm_enabled"
        case .rightForearm: return "metric_rightForearm_enabled"
        case .hips:         return "metric_hips_enabled"
        case .leftThigh:    return "metric_leftThigh_enabled"
        case .rightThigh:   return "metric_rightThigh_enabled"
        case .leftCalf:     return "metric_leftCalf_enabled"
        case .rightCalf:    return "metric_rightCalf_enabled"
        }
    }

    private func isReminderScheduled(reminders: [MeasurementReminder]) -> Bool {
        let hasAnyReminder = notifications.smartEnabled || !reminders.isEmpty
        return notifications.notificationsEnabled && hasAnyReminder
    }
}
