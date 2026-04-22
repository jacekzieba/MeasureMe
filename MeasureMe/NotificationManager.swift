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
    private let trialEndingReminderId = "premium_trial_ending_reminder"
    private let smartMetricStalePrefix = "smart_metric_stale_"
    private let smartMetricPatternPrefix = "smart_metric_pattern_"
    private let aiNotificationPrefix = AppSettingsKeys.Notifications.aiNotificationPrefix
    private let aiMuteActionIdentifier = "ai_notification_mute_type"
    private let aiCategoryPrefix = "ai.notification.category."
    private lazy var importBatcher = ImportNotificationBatcher(center: center, settings: settings)
    private lazy var goalSender = GoalNotificationSender(center: center, settings: settings)
    @Published private(set) var lastSchedulingError: String?
    
    init(center: NotificationCenterClient? = nil, settings: AppSettingsStore) {
        self.settings = settings
        if let center {
            self.center = center
        } else {
            self.center = RealNotificationCenterClient()
        }
        importBatcher.onSchedulingError = { [weak self] error in self?.recordSchedulingError(error) }
        importBatcher.onSchedulingSuccess = { [weak self] in self?.clearLastSchedulingError() }
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
                cancelAllAINotifications()
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

    var aiNotificationsEnabled: Bool {
        get { settings.snapshot.notifications.aiNotificationsEnabled }
        set { settings.set(\.notifications.aiNotificationsEnabled, newValue) }
    }

    var aiWeeklyDigestEnabled: Bool {
        get { settings.snapshot.notifications.aiWeeklyDigestEnabled }
        set { settings.set(\.notifications.aiWeeklyDigestEnabled, newValue) }
    }

    var aiTrendShiftEnabled: Bool {
        get { settings.snapshot.notifications.aiTrendShiftEnabled }
        set { settings.set(\.notifications.aiTrendShiftEnabled, newValue) }
    }

    var aiGoalMilestonesEnabled: Bool {
        get { settings.snapshot.notifications.aiGoalMilestonesEnabled }
        set { settings.set(\.notifications.aiGoalMilestonesEnabled, newValue) }
    }

    var aiRoundNumbersEnabled: Bool {
        get { settings.snapshot.notifications.aiRoundNumbersEnabled }
        set { settings.set(\.notifications.aiRoundNumbersEnabled, newValue) }
    }

    var aiConsistencyEnabled: Bool {
        get { settings.snapshot.notifications.aiConsistencyEnabled }
        set { settings.set(\.notifications.aiConsistencyEnabled, newValue) }
    }

    var aiDigestWeekday: Int {
        get { min(max(settings.snapshot.notifications.aiDigestWeekday, 1), 7) }
        set { settings.set(\.notifications.aiDigestWeekday, min(max(newValue, 1), 7)) }
    }

    var aiDigestTime: Date {
        get {
            let time = settings.snapshot.notifications.aiDigestTime
            if time > 0 {
                return Date(timeIntervalSince1970: time)
            }
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: AppClock.now)
            comps.hour = 19
            comps.minute = 0
            return cal.date(from: comps) ?? AppClock.now
        }
        set {
            settings.set(\.notifications.aiDigestTime, newValue.timeIntervalSince1970)
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

        addNotificationRequest(request)
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
            let lastNotifTS = settings.double(forKey: AppSettingsKeys.Notifications.smartLastNotificationDate)
            let lastNotifDate = lastNotifTS > 0 ? Date(timeIntervalSince1970: lastNotifTS) : nil
            let lastNotifMetric = settings.string(forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)
            if let candidate = scheduler.bestCandidate(
                smartDays: max(smartDays, 1),
                smartTime: smartTime,
                lastNotificationDate: lastNotifDate,
                lastNotifiedMetric: lastNotifMetric
            ) {
                cancelSmartNotification() // cancel generic one
                scheduleSmartMetricNotification(candidate: candidate)
                // Record that we scheduled — previously done inside the scheduler
                settings.set(AppClock.now.timeIntervalSince1970, forKey: AppSettingsKeys.Notifications.smartLastNotificationDate)
                settings.set(candidate.kindRaw, forKey: AppSettingsKeys.Notifications.smartLastNotifiedMetric)
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

        addNotificationRequest(request)

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

        addNotificationRequest(request)
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
        addNotificationRequest(request)
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
        addNotificationRequest(request)
    }

    func queueImportNotification(kind: MetricKind) {
        importBatcher.queue(kind: kind)
    }

    func cancelImportNotifications() {
        importBatcher.cancel()
    }

    func sendGoalAchievedNotification(kind: MetricKind, goalCreatedDate: Date, goalValue: Double) {
        goalSender.send(
            kind: kind,
            goalCreatedDate: goalCreatedDate,
            goalValue: goalValue,
            onError: { [weak self] error in self?.recordSchedulingError(error) },
            onSuccess: { [weak self] in self?.clearLastSchedulingError() }
        )
    }

    func clearLastSchedulingError() {
        lastSchedulingError = nil
    }

    func configureAINotificationCategories() {
        let categories = Set(AINotificationKind.allCases.map { kind in
            UNNotificationCategory(
                identifier: aiCategoryIdentifier(for: kind),
                actions: [
                    UNNotificationAction(
                        identifier: aiMuteActionIdentifier,
                        title: AppLocalization.systemString("notification.ai.mute.action"),
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        })
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func scheduleAINotificationsIfNeeded(
        context: ModelContext,
        trigger: AINotificationTrigger = .startup
    ) {
        guard notificationsEnabled else {
            cancelAllAINotifications()
            return
        }
        guard aiNotificationsEnabled else {
            cancelAllAINotifications()
            return
        }
        guard AppleIntelligenceSupport.isAvailable(), AINotificationLanguage.isSupported else {
            cancelAllAINotifications()
            return
        }

        Task { @MainActor in
            let builder = AINotificationCandidateBuilder(
                context: context,
                settings: settings,
                trigger: trigger
            )
            guard let candidate = builder.bestCandidate(),
                  let decision = await AINotificationGenerator.shared.generateDecision(for: candidate) else {
                return
            }
            self.cancelAllAINotifications()
            self.scheduleAINotification(candidate: candidate, decision: decision)
        }
    }

    func cancelAllAINotifications() {
        Task {
            let pending = await center.pendingRequestIdentifiers()
            let aiIdentifiers = pending.filter { $0.hasPrefix(aiNotificationPrefix) }
            if !aiIdentifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: aiIdentifiers)
            }
        }
    }

    func handleAINotificationResponse(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        handleNotificationResponse(
            actionIdentifier: actionIdentifier,
            requestIdentifier: "",
            userInfo: userInfo
        )
    }

    func handleNotificationResponse(
        actionIdentifier: String,
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        guard let kindRaw = userInfo["aiNotificationKind"] as? String,
              let kind = AINotificationKind(rawValue: kindRaw) else {
            handleStandardNotificationResponse(requestIdentifier: requestIdentifier)
            return
        }

        if actionIdentifier == aiMuteActionIdentifier {
            muteAINotificationKind(kind)
            cancelAllAINotifications()
            return
        }

        if let action = appEntryAction(from: userInfo, requestIdentifier: requestIdentifier) {
            AppEntryActionDispatcher.enqueue(action, source: .notification)
        } else if let route = route(from: userInfo, requestIdentifier: requestIdentifier) {
            AppNavigationRouteDispatcher.enqueue(route)
        }
    }

    func resetAllData() async {
        importBatcher.cancel()

        let goalPrefix = goalSender.ownedPrefix
        let importIds = Set(importBatcher.ownedIdentifiers)
        let appOwnedPendingIdentifiers = await center.pendingRequestIdentifiers().filter { identifier in
            identifier == smartNotificationId
            || identifier == photoReminderId
            || identifier == trialEndingReminderId
            || importIds.contains(identifier)
            || identifier.hasPrefix(reminderPrefix)
            || identifier.hasPrefix(goalPrefix)
            || identifier.hasPrefix(smartMetricStalePrefix)
            || identifier.hasPrefix(smartMetricPatternPrefix)
            || identifier.hasPrefix(aiNotificationPrefix)
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

    private func addNotificationRequest(_ request: UNNotificationRequest) {
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

    private func scheduleAINotification(candidate: AINotificationCandidate, decision: AINotificationDecision) {
        let content = UNMutableNotificationContent()
        content.title = decision.title
        content.body = decision.body
        content.sound = .default
        content.categoryIdentifier = aiCategoryIdentifier(for: candidate.kind)
        content.threadIdentifier = candidate.threadIdentifier
        content.interruptionLevel = decision.priority.interruptionLevel
        content.relevanceScore = decision.priority.relevanceScore
        content.userInfo = candidate.userInfo

        let triggerDate = max(candidate.fireDate.timeIntervalSinceNow, 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: candidate.identifier, content: content, trigger: trigger)

        addNotificationRequest(request)
        recordAISent(candidate.dedupeKeys)
    }

    private func recordAISent(_ keys: [String]) {
        var timestamps = loadAILastSentTimestamps()
        let nowTimestamp = AppClock.now.timeIntervalSince1970
        for key in keys {
            timestamps[key] = nowTimestamp
        }
        persistAILastSentTimestamps(timestamps)
    }

    private func loadAILastSentTimestamps() -> [String: TimeInterval] {
        guard let data = settings.snapshot.notifications.aiLastSentTimestamps else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }

    private func persistAILastSentTimestamps(_ timestamps: [String: TimeInterval]) {
        guard let data = try? JSONEncoder().encode(timestamps) else { return }
        settings.set(\.notifications.aiLastSentTimestamps, data)
    }

    private func muteAINotificationKind(_ kind: AINotificationKind) {
        var mutedKinds = loadMutedAINotificationKinds()
        mutedKinds.insert(kind.rawValue)
        guard let data = try? JSONEncoder().encode(Array(mutedKinds).sorted()) else { return }
        settings.set(\.notifications.aiMutedTypes, data)
    }

    private func loadMutedAINotificationKinds() -> Set<String> {
        guard let data = settings.snapshot.notifications.aiMutedTypes,
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(values)
    }

    private func handleStandardNotificationResponse(requestIdentifier: String) {
        if let action = appEntryAction(from: [:], requestIdentifier: requestIdentifier) {
            AppEntryActionDispatcher.enqueue(action, source: .notification)
        } else if let route = route(from: [:], requestIdentifier: requestIdentifier) {
            AppNavigationRouteDispatcher.enqueue(route)
        }
    }

    private func appEntryAction(
        from userInfo: [AnyHashable: Any],
        requestIdentifier: String
    ) -> AppEntryAction? {
        if let actionRaw = userInfo["appEntryAction"] as? String,
           let action = AppEntryAction(rawValue: actionRaw) {
            return action
        }

        if requestIdentifier == photoReminderId {
            return .openAddPhoto
        }

        return nil
    }

    private func route(
        from userInfo: [AnyHashable: Any],
        requestIdentifier: String
    ) -> AppNavigationRoute? {
        if let routeRaw = userInfo["appRoute"] as? String {
            switch routeRaw {
            case "home":
                return .home
            case "measurements":
                return .measurements
            case "settings":
                return .settings
            case "metricDetail":
                guard let kindRaw = userInfo["appRouteMetricKindRaw"] as? String else { return nil }
                return .metricDetail(kindRaw: kindRaw)
            case "quickAdd":
                return .quickAdd(kindRaw: userInfo["appRouteMetricKindRaw"] as? String)
            default:
                break
            }
        }

        guard let routeRaw = userInfo["aiRoute"] as? String else {
            return route(for: requestIdentifier)
        }
        switch routeRaw {
        case "home":
            return .home
        case "measurements":
            return .measurements
        case "settings":
            return .settings
        case "metricDetail":
            guard let kindRaw = userInfo["aiRouteMetricKindRaw"] as? String else { return nil }
            return .metricDetail(kindRaw: kindRaw)
        case "quickAdd":
            return .quickAdd(kindRaw: userInfo["aiRouteMetricKindRaw"] as? String)
        default:
            return route(for: requestIdentifier)
        }
    }

    private func route(for requestIdentifier: String) -> AppNavigationRoute? {
        if requestIdentifier == smartNotificationId || requestIdentifier.hasPrefix(reminderPrefix) {
            return .quickAdd(kindRaw: nil)
        }

        if requestIdentifier == "measurement_import_summary" {
            return .measurements
        }

        if requestIdentifier == trialEndingReminderId {
            return .settings
        }

        if let kindRaw = requestIdentifier.removingPrefix(smartMetricStalePrefix) {
            return MetricKind(rawValue: kindRaw).map { _ in .quickAdd(kindRaw: kindRaw) }
        }

        if let kindRaw = requestIdentifier.removingPrefix(smartMetricPatternPrefix) {
            return MetricKind(rawValue: kindRaw).map { _ in .quickAdd(kindRaw: kindRaw) }
        }

        guard let prefixed = requestIdentifier.removingPrefix(goalSender.ownedPrefix) else { return nil }
        let trimmed = prefixed.removingSuffix("_notification")
        guard let kindRaw = trimmed.split(separator: "_").first.map(String.init),
              MetricKind(rawValue: kindRaw) != nil else {
            return nil
        }
        return .metricDetail(kindRaw: kindRaw)
    }

    private func aiCategoryIdentifier(for kind: AINotificationKind) -> String {
        aiCategoryPrefix + kind.rawValue
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}
