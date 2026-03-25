import Foundation
import UserNotifications

/// Buffers metric import events and fires a single summary notification after a cooldown.
@MainActor
final class ImportNotificationBatcher {

    private let center: NotificationCenterClient
    private let settings: AppSettingsStore
    private let notificationId = "measurement_import_summary"
    private let bufferSeconds: TimeInterval = 15
    private var pendingKinds: [MetricKind] = []
    private var pendingTask: Task<Void, Never>?

    /// Called when an error or success should be surfaced to the manager.
    var onSchedulingError: ((Error) -> Void)?
    var onSchedulingSuccess: (() -> Void)?

    init(center: NotificationCenterClient, settings: AppSettingsStore) {
        self.center = center
        self.settings = settings
    }

    // MARK: - Public API

    func queue(kind: MetricKind) {
        guard settings.snapshot.notifications.notificationsEnabled else { return }
        guard settings.snapshot.notifications.importNotificationsEnabled else { return }

        if !pendingKinds.contains(kind) {
            pendingKinds.append(kind)
        }

        guard pendingTask == nil else { return }
        let delay = bufferSeconds
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.flush()
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        clearBuffer()
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
    }

    /// Identifiers owned by this batcher (for `resetAllData`).
    var ownedIdentifiers: [String] { [notificationId] }

    // MARK: - Private

    private func flush() async {
        defer { pendingTask = nil }

        let kinds = pendingKinds
        clearBuffer()

        guard settings.snapshot.notifications.notificationsEnabled else { return }
        guard settings.snapshot.notifications.importNotificationsEnabled else { return }
        guard !kinds.isEmpty else { return }

        let status = await center.authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = AppLocalization.string("notification.import.summary.title")
        content.body = Self.summaryBody(for: kinds)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)

        do {
            try await center.add(request)
            onSchedulingSuccess?()
        } catch {
            onSchedulingError?(error)
        }
    }

    private func clearBuffer() {
        pendingKinds.removeAll(keepingCapacity: true)
    }

    // MARK: - Body Formatting

    static func summaryBody(for kinds: [MetricKind]) -> String {
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
}
