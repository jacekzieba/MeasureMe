// AppEntryAction.swift
//
// **AppEntryAction**
// Deep-link and quick-action plumbing that bridges external entry points
// (home screen quick actions, App Intents, notifications) into the running app.
//
// **Responsibilities:**
// - Defining the typed set of entry actions the app supports
// - Mapping UIKit `UIApplicationShortcutItem.type` strings to typed actions
// - Persisting a pending action across cold launches so the dispatcher
//   can pick it up once the UI is ready
// - Forwarding the action to `RootView` via `NotificationCenter`
// - Emitting a per-source analytics signal so we can measure which
//   entry path users prefer
//
// **Lifecycle:**
// 1. iOS or App Intents calls `enqueue(_:source:)` (from `AppDelegate` /
//    `SceneDelegate` / `MeasureMeIntents`).
// 2. The action is written to `AppSettingsStore` under the
//    `pendingAppEntryAction` key, so a cold launch survives the gap between
//    launch and SwiftUI being ready.
// 3. A `NotificationCenter` event fires so an already-running `RootView` can
//    react immediately.
// 4. `RootView` calls `consumePendingAction()` once it is on screen; the
//    stored value is cleared.
//
import Foundation

/// High-level actions the user can invoke from outside the app's main UI.
enum AppEntryAction: String, Codable, Sendable {
    /// Open the Quick Add sheet (e.g. add a measurement).
    case openQuickAdd
    /// Open the Add Photo flow.
    case openAddPhoto

    /// `UIApplicationShortcutItem` identifier that maps to `openQuickAdd`.
    static let quickAddShortcutType = "com.jacek.measureme.quickAdd"
    /// `UIApplicationShortcutItem` identifier that maps to `openAddPhoto`.
    static let addPhotoShortcutType = "com.jacek.measureme.addPhoto"

    /// Maps a `UIApplicationShortcutItem.type` string to a typed action.
    /// - Parameter shortcutItemType: The `type` field of a
    ///   `UIApplicationShortcutItem`. Strings that don't match return `nil`.
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

/// Where a given `AppEntryAction` originated. Used to pick the right
/// analytics signal and (eventually) to adapt UI affordances.
enum AppEntrySource: String, Sendable {
    /// Home screen long-press → quick action.
    case quickAction
    /// Siri / App Shortcuts / App Intents.
    case appIntent
    /// User tapped a system notification.
    case notification
}

/// Stamps a pending action into `AppSettingsStore`, notifies observers, and
/// emits an analytics signal. The actual UI handling lives in `RootView`.
enum AppEntryActionDispatcher {
    /// Posted on `NotificationCenter.default` after a successful `enqueue`.
    /// `object` carries the `AppEntryAction` value.
    static let didEnqueueNotification = Notification.Name("appEntryActionDidEnqueue")

    /// Records an entry action and notifies the running app.
    ///
    /// - Parameters:
    ///   - action: The action to enqueue.
    ///   - source: Where the action originated (drives the analytics signal).
    @MainActor
    static func enqueue(_ action: AppEntryAction, source: AppEntrySource) {
        // Persist under a well-known settings key so a cold launch can pick it up
        // before the SwiftUI tree is alive. RootView consumes it once it mounts.
        let settings = AppSettingsStore.shared
        settings.set(action.rawValue, forKey: AppSettingsKeys.Entry.pendingAppEntryAction)

        // Emit a per-source analytics signal. The raw action value is passed
        // as a parameter so dashboards can break down usage by action.
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
        case .notification:
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.notification_opened",
                parameters: ["action": action.rawValue]
            )
        }

        // Notify any observer that may already be alive (warm-launch path).
        NotificationCenter.default.post(name: didEnqueueNotification, object: action)
    }

    /// Pops the pending action off the settings store.
    ///
    /// Called by `RootView` once it is on screen. The stored key is cleared
    /// so the same action cannot fire twice (e.g. after a backgrounding).
    /// - Returns: The pending action, or `nil` if there is none.
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
