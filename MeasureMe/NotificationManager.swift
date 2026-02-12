import Foundation
import UserNotifications

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

struct MeasurementReminder: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let repeatRule: ReminderRepeat
    
    init(id: String = UUID().uuidString, date: Date, repeatRule: ReminderRepeat = .once) {
        self.id = id
        self.date = date
        self.repeatRule = repeatRule
    }
}

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    
    private let center = UNUserNotificationCenter.current()
    private let remindersKey = "measurement_reminders"
    private let notificationsEnabledKey = "measurement_notifications_enabled"
    private let smartEnabledKey = "measurement_smart_enabled"
    private let smartDaysKey = "measurement_smart_days"
    private let smartTimeKey = "measurement_smart_time"
    private let lastLogDateKey = "measurement_last_log_date"
    private let smartNotificationId = "measurement_smart_reminder"
    private let reminderPrefix = "measurement_reminder_"
    private let lastPhotoDateKey = "photo_last_log_date"
    private let photoReminderId = "photo_smart_reminder"
    private let photoRemindersEnabledKey = "measurement_photo_reminders_enabled"
    private let goalAchievedEnabledKey = "measurement_goal_achieved_enabled"
    private let goalAchievementPrefix = "goal_achieved_"
    
    private init() {}
    
    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }
    
    var smartEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: smartEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: smartEnabledKey) }
    }
    
    var smartDays: Int {
        get { max(UserDefaults.standard.integer(forKey: smartDaysKey), 0) }
        set { UserDefaults.standard.set(newValue, forKey: smartDaysKey) }
    }
    
    var smartTime: Date {
        get {
            let time = UserDefaults.standard.double(forKey: smartTimeKey)
            return time > 0 ? Date(timeIntervalSince1970: time) : defaultSmartTime()
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: smartTimeKey)
        }
    }
    
    var lastLogDate: Date? {
        get {
            let time = UserDefaults.standard.double(forKey: lastLogDateKey)
            return time > 0 ? Date(timeIntervalSince1970: time) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastLogDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastLogDateKey)
            }
        }
    }

    var photoRemindersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: photoRemindersEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: photoRemindersEnabledKey) }
    }

    var goalAchievedEnabled: Bool {
        get { UserDefaults.standard.object(forKey: goalAchievedEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: goalAchievedEnabledKey) }
    }

    private var lastPhotoDate: Date? {
        let time = UserDefaults.standard.double(forKey: lastPhotoDateKey)
        return time > 0 ? Date(timeIntervalSince1970: time) : nil
    }
    
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }
    
    func loadReminders() -> [MeasurementReminder] {
        guard let data = UserDefaults.standard.data(forKey: remindersKey) else {
            return []
        }
        return (try? JSONDecoder().decode([MeasurementReminder].self, from: data)) ?? []
    }
    
    func saveReminders(_ reminders: [MeasurementReminder]) {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: remindersKey)
        }
    }
    
    func scheduleAllReminders(_ reminders: [MeasurementReminder]) {
        guard notificationsEnabled else { return }
        cancelAllReminders()
        for reminder in reminders {
            scheduleReminder(reminder)
        }
    }
    
    func scheduleReminder(_ reminder: MeasurementReminder) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = name.isEmpty ? "" : "\(name), "
        content.title = AppLocalization.string("notification.log.title", prefix)
        content.body = AppLocalization.string("notification.log.body")
        content.sound = .default
        
        let calendar = Calendar.current
        let trigger: UNCalendarNotificationTrigger
        switch reminder.repeatRule {
        case .once:
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .daily:
            let components = calendar.dateComponents([.hour, .minute], from: reminder.date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .weekly:
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: reminder.date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
        
        let request = UNNotificationRequest(
            identifier: reminderPrefix + reminder.id,
            content: content,
            trigger: trigger
        )
        
        center.add(request)
    }
    
    func removeReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderPrefix + id])
    }
    
    func cancelAllReminders() {
        let reminders = loadReminders()
        let ids = reminders.map { reminderPrefix + $0.id }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
    
    func recordMeasurement(date: Date = .now) {
        lastLogDate = date
        cancelSmartNotification()
    }
    
    func scheduleSmartIfNeeded() {
        guard notificationsEnabled, smartEnabled else {
            cancelSmartNotification()
            cancelPhotoReminder()
            return
        }
        
        let days = max(smartDays, 1)
        let now = Date()
        if let last = lastLogDate {
            let since = now.timeIntervalSince(last)
            if since < TimeInterval(days) * 86400 {
                cancelSmartNotification()
                return
            }
        }
        
        let nextFire = nextSmartFireDate(from: now)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextFire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let content = UNMutableNotificationContent()
        let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = name.isEmpty ? "" : "\(name), "
        content.title = AppLocalization.string("notification.smart.title", prefix)
        let daysSince = lastLogDate.map { max(1, Int(ceil(now.timeIntervalSince($0) / 86400.0))) } ?? days
        content.body = AppLocalization.plural("notification.smart.body", daysSince)
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: smartNotificationId,
            content: content,
            trigger: trigger
        )
        
        center.add(request)

        schedulePhotoReminderIfNeeded()
    }
    
    func cancelSmartNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [smartNotificationId])
    }

    func recordPhotoAdded(date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastPhotoDateKey)
        cancelPhotoReminder()
    }

    func schedulePhotoReminderIfNeeded(days: Int = 7) {
        guard notificationsEnabled else { return }
        guard photoRemindersEnabled else {
            cancelPhotoReminder()
            return
        }
        guard let last = lastPhotoDate else { return }

        let now = Date()
        let since = now.timeIntervalSince(last)
        guard since >= TimeInterval(days) * 86400 else {
            cancelPhotoReminder()
            return
        }

        let content = UNMutableNotificationContent()
        let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = name.isEmpty ? "" : "\(name), "
        content.title = AppLocalization.string("notification.photo.title", prefix)
        let daysSince = max(1, Int(ceil(since / 86400.0)))
        content.body = AppLocalization.plural("notification.photo.body", daysSince)
        content.sound = .default

        let nextFire = nextSmartFireDate(from: now)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextFire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: photoReminderId,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelPhotoReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [photoReminderId])
    }

    func sendImportNotification(kind: MetricKind, date: Date) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = AppLocalization.string("notification.import.title", kind.title)
            content.body = AppLocalization.string("notification.import.body")
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "measurement_import_\(kind.rawValue)_\(date.timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            
            try? await center.add(request)
        }
    }

    func sendGoalAchievedNotification(kind: MetricKind, goalCreatedDate: Date, goalValue: Double) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            guard goalAchievedEnabled else { return }

            let key = "\(goalAchievementPrefix)\(kind.rawValue)_\(goalCreatedDate.timeIntervalSince1970)"
            if UserDefaults.standard.bool(forKey: key) {
                return
            }

            let name = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suffix = name.isEmpty ? "" : ", \(name)"
            let content = UNMutableNotificationContent()
            content.title = AppLocalization.string("notification.goal.title", suffix)
            content.body = AppLocalization.string("notification.goal.body", kind.title)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(key)_notification",
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
            UserDefaults.standard.set(true, forKey: key)
        }
    }
    
    private func nextSmartFireDate(from now: Date) -> Date {
        let cal = Calendar.current
        let time = smartTime
        let timeComponents = cal.dateComponents([.hour, .minute], from: time)
        var todayComponents = cal.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = timeComponents.hour
        todayComponents.minute = timeComponents.minute
        
        let todayTarget = cal.date(from: todayComponents) ?? now
        if todayTarget > now {
            return todayTarget
        }
        return cal.date(byAdding: .day, value: 1, to: todayTarget) ?? todayTarget
    }
    
    private func defaultSmartTime() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 19
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }
}
