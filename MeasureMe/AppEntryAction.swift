import Foundation

enum AppEntryAction: String, Codable, Sendable {
    case openQuickAdd
    case openAddPhoto

    static let quickAddShortcutType = "com.jacek.measureme.quickAdd"
    static let addPhotoShortcutType = "com.jacek.measureme.addPhoto"

    init?(shortcutItemType: String) {
        switch shortcutItemType {
        case Self.quickAddShortcutType:
            self = .openQuickAdd
        case Self.addPhotoShortcutType:
            self = .openAddPhoto
        default:
            return nil
        }
    }
}

enum AppEntrySource: String, Sendable {
    case quickAction
    case appIntent
}

enum AppEntryActionDispatcher {
    static let didEnqueueNotification = Notification.Name("appEntryActionDidEnqueue")

    @MainActor
    static func enqueue(_ action: AppEntryAction, source: AppEntrySource) {
        let settings = AppSettingsStore.shared
        settings.set(action.rawValue, forKey: AppSettingsKeys.Entry.pendingAppEntryAction)

        switch source {
        case .quickAction:
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.quick_action_used",
                parameters: ["action": action.rawValue]
            )
        case .appIntent:
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.app_intent_executed",
                parameters: ["action": action.rawValue]
            )
        }

        NotificationCenter.default.post(name: didEnqueueNotification, object: action)
    }

    @MainActor
    static func consumePendingAction() -> AppEntryAction? {
        let settings = AppSettingsStore.shared
        guard
            let raw = settings.string(forKey: AppSettingsKeys.Entry.pendingAppEntryAction),
            let action = AppEntryAction(rawValue: raw)
        else {
            return nil
        }
        settings.removeObject(forKey: AppSettingsKeys.Entry.pendingAppEntryAction)
        return action
    }
}
