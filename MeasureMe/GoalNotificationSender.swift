import Foundation
import UserNotifications

/// Sends a one-time notification when a user achieves a metric goal.
@MainActor
struct GoalNotificationSender {

    private let center: NotificationCenterClient
    private let settings: AppSettingsStore
    private let prefix = AppSettingsKeys.Notifications.goalAchievementPrefix

    init(center: NotificationCenterClient, settings: AppSettingsStore) {
        self.center = center
        self.settings = settings
    }

    // MARK: - Public API

    func send(kind: MetricKind, goalCreatedDate: Date, goalValue: Double, onError: ((Error) -> Void)?, onSuccess: (() -> Void)?) {
        Task {
            let status = await center.authorizationStatus()
            guard status == .authorized || status == .provisional else { return }
            guard settings.snapshot.notifications.goalAchievedEnabled else { return }

            let goalID = "\(kind.rawValue)_\(goalCreatedDate.timeIntervalSince1970)"
            let notificationKey = "\(prefix)\(goalID)"

            if settings.goalAchievedFlag(for: goalID) { return }

            let name = settings.snapshot.profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = name.isEmpty ? "" : ", \(name)"
            let content = UNMutableNotificationContent()
            content.title = AppLocalization.string("notification.goal.title", suffix)
            content.body = AppLocalization.string("notification.goal.body", kind.title)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "\(notificationKey)_notification", content: content, trigger: trigger)

            do {
                try await center.add(request)
                onSuccess?()
            } catch {
                onError?(error)
                return
            }
            settings.setGoalAchievedFlag(true, for: goalID)
        }
    }

    /// Identifier prefix owned by this sender (for `resetAllData`).
    var ownedPrefix: String { prefix }
}
