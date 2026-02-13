import Foundation
import UserNotifications
import Combine

protocol NotificationCenterClient {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

struct RealNotificationCenterClient: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        center.add(request) { error in
            completion(error)
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .once: return AppLocalization.string("Once")
        case .daily: return AppLocalization.string("Daily")
        case .weekly: return AppLocalization.string("Weekly")
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
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private let center: NotificationCenterClient
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
    private let importNotificationsEnabledKey = "measurement_import_notifications_enabled"
    private let goalAchievementPrefix = "goal_achieved_"
    private let importSummaryNotificationId = "measurement_import_summary"
    private let importNotificationBufferSeconds: TimeInterval = 15
    private let trialEndingReminderId = "premium_trial_ending_reminder"
    private var pendingImportKinds: [MetricKind] = []
    private var pendingImportKindsSet: Set<MetricKind> = []
    private var pendingImportTask: Task<Void, Never>?
    @Published private(set) var lastSchedulingError: String?
    
    init(center: NotificationCenterClient? = nil) {
        if let center {
            self.center = center
        } else {
            self.center = RealNotificationCenterClient()
        }
    }
    
    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey)
            if !newValue {
                cancelImportNotifications()
            }
        }
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

    var importNotificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: importNotificationsEnabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: importNotificationsEnabledKey)
            if !newValue {
                cancelImportNotifications()
            }
        }
    }

    private var lastPhotoDate: Date? {
        let time = UserDefaults.standard.double(forKey: lastPhotoDateKey)
        return time > 0 ? Date(timeIntervalSince1970: time) : nil
    }
    
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization()
        } catch {
            recordSchedulingError(error)
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
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

        center.add(request) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.recordSchedulingError(error)
                } else {
                    self.clearLastSchedulingError()
                }
            }
        }
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
        guard notificationsEnabled else {
            cancelSmartNotification()
            cancelPhotoReminder()
            return
        }

        guard smartEnabled else {
            cancelSmartNotification()
            schedulePhotoReminderIfNeeded()
            return
        }
        
        let days = max(smartDays, 1)
        let now = Date()
        if let last = lastLogDate {
            let since = now.timeIntervalSince(last)
            if since < TimeInterval(days) * 86400 {
                cancelSmartNotification()
                schedulePhotoReminderIfNeeded()
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

        center.add(request) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.recordSchedulingError(error)
                } else {
                    self.clearLastSchedulingError()
                }
            }
        }

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
        guard notificationsEnabled else {
            cancelPhotoReminder()
            return
        }
        guard photoRemindersEnabled else {
            cancelPhotoReminder()
            return
        }
        guard let last = lastPhotoDate else {
            cancelPhotoReminder()
            return
        }

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
        center.add(request) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.recordSchedulingError(error)
                } else {
                    self.clearLastSchedulingError()
                }
            }
        }
    }

    func cancelPhotoReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [photoReminderId])
    }

    func scheduleTrialEndingReminder(daysFromNow: Int = 12) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.string("notification.trial.ends.soon.title")
        content.body = AppLocalization.string("notification.trial.ends.soon.body")
        content.sound = .default

        let seconds = max(TimeInterval(daysFromNow * 24 * 60 * 60), 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)

        center.removePendingNotificationRequests(withIdentifiers: [trialEndingReminderId])
        let request = UNNotificationRequest(
            identifier: trialEndingReminderId,
            content: content,
            trigger: trigger
        )
        center.add(request) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.recordSchedulingError(error)
                } else {
                    self.clearLastSchedulingError()
                }
            }
        }
    }

    func queueImportNotification(kind: MetricKind) {
        guard notificationsEnabled else { return }
        guard importNotificationsEnabled else { return }

        if pendingImportKindsSet.insert(kind).inserted {
            pendingImportKinds.append(kind)
        }

        guard pendingImportTask == nil else { return }
        let bufferSeconds = importNotificationBufferSeconds
        pendingImportTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(bufferSeconds))
            await self?.flushQueuedImportNotification()
        }
    }

    func cancelImportNotifications() {
        pendingImportTask?.cancel()
        pendingImportTask = nil
        clearPendingImportBuffer()
        center.removePendingNotificationRequests(withIdentifiers: [importSummaryNotificationId])
    }

    private func flushQueuedImportNotification() async {
        defer { pendingImportTask = nil }

        let kinds = pendingImportKinds
        clearPendingImportBuffer()

        guard notificationsEnabled else { return }
        guard importNotificationsEnabled else { return }
        guard !kinds.isEmpty else { return }

        let status = await center.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.string("notification.import.summary.title")
        content.body = importSummaryBody(for: kinds)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: importSummaryNotificationId,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            clearLastSchedulingError()
        } catch {
            recordSchedulingError(error)
        }
    }

    private func clearPendingImportBuffer() {
        pendingImportKinds.removeAll(keepingCapacity: true)
        pendingImportKindsSet.removeAll(keepingCapacity: true)
    }

    private func importSummaryBody(for kinds: [MetricKind]) -> String {
        let titles = kinds.map(\.title)
        guard let first = titles.first else {
            return AppLocalization.string("notification.import.body")
        }

        if titles.count == 1 {
            return AppLocalization.string("notification.import.summary.body.single", first)
        }

        let second = titles[1]
        if titles.count == 2 {
            return AppLocalization.string("notification.import.summary.body.double", first, second)
        }

        return AppLocalization.string("notification.import.summary.body.multiple", first, second)
    }

    func sendGoalAchievedNotification(kind: MetricKind, goalCreatedDate: Date, goalValue: Double) {
        Task {
            let status = await center.authorizationStatus()
            guard status == .authorized || status == .provisional else {
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

            do {
                try await center.add(request)
                clearLastSchedulingError()
            } catch {
                recordSchedulingError(error)
                return
            }
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    func clearLastSchedulingError() {
        lastSchedulingError = nil
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
        comps.hour = 7
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }

    private func recordSchedulingError(_ error: Error) {
        let fallback = AppLocalization.string("Could not schedule notifications. Please check notification permissions and try again.")
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            lastSchedulingError = fallback
        } else {
            lastSchedulingError = AppLocalization.string("%@ (%@)", fallback, detail)
        }
        AppLog.debug("⚠️ Notification scheduling failed: \(error.localizedDescription)")
    }
}
