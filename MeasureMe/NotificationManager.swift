import Foundation
import UserNotifications
import Combine
import SwiftData

protocol NotificationCenterClient {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingRequestIdentifiers() async -> [String]
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

    func pendingRequestIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
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
    
    static let notificationsDidChange = Notification.Name("measurement_notifications_did_change")
    
    private let center: NotificationCenterClient
    private let settings: AppSettingsStore
    private let smartNotificationId = "measurement_smart_reminder"
    private let reminderPrefix = "measurement_reminder_"
    private let photoReminderId = "photo_smart_reminder"
    private let goalAchievementPrefix = AppSettingsKeys.Notifications.goalAchievementPrefix
    private let importSummaryNotificationId = "measurement_import_summary"
    private let importNotificationBufferSeconds: TimeInterval = 15
    private let trialEndingReminderId = "premium_trial_ending_reminder"
    private let smartMetricStalePrefix = "smart_metric_stale_"
    private let smartMetricPatternPrefix = "smart_metric_pattern_"
    private var pendingImportKinds: [MetricKind] = []
    private var pendingImportKindsSet: Set<MetricKind> = []
    private var pendingImportTask: Task<Void, Never>?
    @Published private(set) var lastSchedulingError: String?
    
    init(center: NotificationCenterClient? = nil, settings: AppSettingsStore) {
        self.settings = settings
        if let center {
            self.center = center
        } else {
            self.center = RealNotificationCenterClient()
        }
    }

    convenience init(center: NotificationCenterClient? = nil) {
        self.init(center: center, settings: .shared)
    }
    
    var notificationsEnabled: Bool {
        get { settings.snapshot.notifications.notificationsEnabled }
        set {
            settings.set(\.notifications.notificationsEnabled, newValue)
            if !newValue {
                cancelImportNotifications()
            }
            notifyStateChanged()
        }
    }
    
    var smartEnabled: Bool {
        get { settings.snapshot.notifications.smartEnabled }
        set {
            settings.set(\.notifications.smartEnabled, newValue)
            notifyStateChanged()
        }
    }
    
    var smartDays: Int {
        get { max(settings.snapshot.notifications.smartDays, 0) }
        set { settings.set(\.notifications.smartDays, newValue) }
    }
    
    var smartTime: Date {
        get {
            let time = settings.snapshot.notifications.smartTime
            return time > 0 ? Date(timeIntervalSince1970: time) : defaultSmartTime()
        }
        set {
            settings.set(\.notifications.smartTime, newValue.timeIntervalSince1970)
        }
    }
    
    var lastLogDate: Date? {
        get {
            let time = settings.snapshot.notifications.lastLogDate
            return time > 0 ? Date(timeIntervalSince1970: time) : nil
        }
        set {
            if let newValue {
                settings.set(\.notifications.lastLogDate, newValue.timeIntervalSince1970)
            } else {
                settings.set(\.notifications.lastLogDate, 0)
            }
        }
    }

    var photoRemindersEnabled: Bool {
        get { settings.snapshot.notifications.photoRemindersEnabled }
        set { settings.set(\.notifications.photoRemindersEnabled, newValue) }
    }

    var goalAchievedEnabled: Bool {
        get { settings.snapshot.notifications.goalAchievedEnabled }
        set { settings.set(\.notifications.goalAchievedEnabled, newValue) }
    }

    var perMetricSmartEnabled: Bool {
        get { settings.snapshot.notifications.perMetricSmartEnabled }
        set {
            settings.set(\.notifications.perMetricSmartEnabled, newValue)
            notifyStateChanged()
        }
    }

    var importNotificationsEnabled: Bool {
        get { settings.snapshot.notifications.importNotificationsEnabled }
        set {
            settings.set(\.notifications.importNotificationsEnabled, newValue)
            if !newValue {
                cancelImportNotifications()
            }
        }
    }

    private var lastPhotoDate: Date? {
        let time = settings.snapshot.notifications.lastPhotoDate
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
        guard let data = settings.snapshot.notifications.measurementRemindersData else {
            return []
        }
        do {
            return try JSONDecoder().decode([MeasurementReminder].self, from: data)
        } catch {
            recordSchedulingError(error)
            AppLog.debug("⚠️ Failed to decode reminders: \(error.localizedDescription)")
            return []
        }
    }
    
    func saveReminders(_ reminders: [MeasurementReminder]) {
        do {
            let data = try JSONEncoder().encode(reminders)
            settings.set(\.notifications.measurementRemindersData, data)
            notifyStateChanged()
        } catch {
            recordSchedulingError(error)
            AppLog.debug("⚠️ Failed to encode reminders: \(error.localizedDescription)")
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
        let name = settings.snapshot.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func recordMeasurement(kinds: [MetricKind], date: Date = .now) {
        lastLogDate = date
        cancelSmartNotification()
        updatePerMetricLastDates(kinds: kinds, date: date)
    }

    private func updatePerMetricLastDates(kinds: [MetricKind], date: Date) {
        var dates = loadPerMetricLastDates()
        for kind in kinds {
            let existing = dates[kind.rawValue]
            if existing == nil || date > existing! {
                dates[kind.rawValue] = date
            }
        }
        savePerMetricLastDates(dates)
    }

    private func loadPerMetricLastDates() -> [String: Date] {
        guard let data = settings.data(forKey: AppSettingsKeys.Notifications.perMetricLastDates),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func savePerMetricLastDates(_ dates: [String: Date]) {
        let dict = dates.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(dict) {
            settings.set(data, forKey: AppSettingsKeys.Notifications.perMetricLastDates)
        }
    }
    
    func scheduleSmartIfNeeded(context: ModelContext? = nil) {
        guard notificationsEnabled else {
            cancelSmartNotification()
            cancelAllSmartMetricNotifications()
            cancelPhotoReminder()
            return
        }

        guard smartEnabled else {
            cancelSmartNotification()
            cancelAllSmartMetricNotifications()
            schedulePhotoReminderIfNeeded()
            return
        }

        // Try per-metric smart notifications first
        if perMetricSmartEnabled, let context {
            let scheduler = SmartNotificationScheduler(context: context, settings: settings)
            if let candidate = scheduler.bestCandidate(
                smartDays: max(smartDays, 1),
                smartTime: smartTime
            ) {
                cancelSmartNotification() // cancel generic one
                scheduleSmartMetricNotification(candidate: candidate)
                scheduler.recordNotificationScheduled(candidate: candidate)
                schedulePhotoReminderIfNeeded()
                return
            }
            // No per-metric candidate — fall through to generic smart reminder
            cancelAllSmartMetricNotifications()
        }

        // Generic smart reminder (existing behavior)
        let days = max(smartDays, 1)
        let now = AppClock.now
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
        let name = settings.snapshot.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func scheduleSmartMetricNotification(candidate: SmartNotificationScheduler.Candidate) {
        let prefix: String
        switch candidate.reason {
        case .missedPattern:
            prefix = smartMetricPatternPrefix
        case .staleness:
            prefix = smartMetricStalePrefix
        }

        // Cancel any existing smart metric notifications
        cancelAllSmartMetricNotifications()

        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: candidate.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: prefix + candidate.kindRaw,
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

    func cancelAllSmartMetricNotifications() {
        Task {
            let pending = await center.pendingRequestIdentifiers()
            let toRemove = pending.filter {
                $0.hasPrefix(smartMetricStalePrefix) || $0.hasPrefix(smartMetricPatternPrefix)
            }
            if !toRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: toRemove)
            }
        }
    }
    
    func cancelSmartNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [smartNotificationId])
    }

    func recordPhotoAdded(date: Date = .now) {
        settings.set(\.notifications.lastPhotoDate, date.timeIntervalSince1970)
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

        let now = AppClock.now
        let since = now.timeIntervalSince(last)
        guard since >= TimeInterval(days) * 86400 else {
            cancelPhotoReminder()
            return
        }

        let content = UNMutableNotificationContent()
        let name = settings.snapshot.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let goalID = "\(kind.rawValue)_\(goalCreatedDate.timeIntervalSince1970)"
            if settings.goalAchievedFlag(for: goalID) {
                return
            }

            let name = settings.snapshot.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            settings.setGoalAchievedFlag(true, for: goalID)
        }
    }

    func clearLastSchedulingError() {
        lastSchedulingError = nil
    }

    func resetAllData() async {
        pendingImportTask?.cancel()
        pendingImportTask = nil
        clearPendingImportBuffer()

        let appOwnedPendingIdentifiers = await center.pendingRequestIdentifiers().filter { identifier in
            identifier == smartNotificationId
            || identifier == photoReminderId
            || identifier == trialEndingReminderId
            || identifier == importSummaryNotificationId
            || identifier.hasPrefix(reminderPrefix)
            || identifier.hasPrefix(goalAchievementPrefix)
            || identifier.hasPrefix(smartMetricStalePrefix)
            || identifier.hasPrefix(smartMetricPatternPrefix)
        }

        if !appOwnedPendingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: appOwnedPendingIdentifiers)
        }

        settings.resetNotificationSettingsToDefaults()

        clearLastSchedulingError()
        notifyStateChanged()
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
        var comps = cal.dateComponents([.year, .month, .day], from: AppClock.now)
        comps.hour = 7
        comps.minute = 0
        return cal.date(from: comps) ?? AppClock.now
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
    
    private func notifyStateChanged() {
        NotificationCenter.default.post(name: Self.notificationsDidChange, object: nil)
    }
}
