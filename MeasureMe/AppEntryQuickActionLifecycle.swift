// AppEntryQuickActionLifecycle.swift
//
// **AppEntryQuickActionLifecycle**
// `UIApplicationDelegate` + `UIWindowSceneDelegate` glue that converts
// home-screen quick actions and notification taps into typed `AppEntryAction`s.
//
// **Responsibilities:**
// - Installing the app delegate on launch
// - Registering the scene delegate class for incoming scene connections
// - Forwarding notification responses to `NotificationManager`
// - Translating `UIApplicationShortcutItem` taps into `AppEntryActionDispatcher.enqueue`
//
// **Why this lives outside `AppLifecycleCoordinator`:**
// The lifecycle coordinator handles post-launch orchestration; this file
// owns the UIKit-only pieces that must run *before* SwiftUI is even alive
// (delegate install, scene configuration, shortcut routing).
//
import UIKit
import UserNotifications

/// `UIApplicationDelegate` adapter that owns notification-center delegate
/// setup and routes the per-scene configuration to `MeasureMeSceneDelegate`.
final class MeasureMeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Standard launch entry point. Runs before SwiftUI is up; keep it cheap
    /// and side-effect-free apart from the two setup calls below.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Become the notification center delegate so we receive foreground
        // taps and action responses while the app is running.
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            // Register the AI notification action categories (e.g. "Snooze", "Open")
            // so the system can show the right buttons in the notification UI.
            NotificationManager.shared.configureAINotificationCategories()
        }
        return true
    }

    /// Returns the per-scene configuration. Wires the custom scene delegate
    /// class so that home-screen quick actions get routed to `AppEntryActionDispatcher`.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MeasureMeSceneDelegate.self
        return configuration
    }

    /// Forward notification taps to `NotificationManager` and call the system
    /// completion handler when handling is finished.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleNotificationResponse(
                actionIdentifier: response.actionIdentifier,
                requestIdentifier: response.notification.request.identifier,
                userInfo: response.notification.request.content.userInfo
            )
            completionHandler()
        }
    }
}

/// `UIWindowSceneDelegate` adapter that converts a home-screen quick action
/// (`UIApplicationShortcutItem`) into a typed `AppEntryAction`.
final class MeasureMeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// Invoked when a scene is being connected (cold-launch path).
    /// The system may have queued a quick-action tap during the previous
    /// app run; pick it up here so the user lands on the right screen.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        _ = enqueueShortcutIfNeeded(connectionOptions.shortcutItem)
    }

    /// Invoked when a user taps a quick action while the app is in the
    /// background (warm-launch path). Completion handler is called with
    /// `true` when the shortcut was recognized and enqueued.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(enqueueShortcutIfNeeded(shortcutItem))
    }

    /// Shared shortcut→action conversion used by both the cold- and warm-launch paths.
    /// - Parameter shortcutItem: The shortcut item tapped by the user, or `nil` if the
    ///   scene was launched normally.
    /// - Returns: `true` if the shortcut type matched a known action and was enqueued.
    @discardableResult
    private func enqueueShortcutIfNeeded(_ shortcutItem: UIApplicationShortcutItem?) -> Bool {
        guard
            let shortcutItem,
            let action = AppEntryAction(shortcutItemType: shortcutItem.type)
        else {
            return false
        }

        // Enqueue on the main actor — `AppEntryActionDispatcher` writes to the
        // shared settings store, which is `@MainActor`-isolated.
        Task { @MainActor in
            AppEntryActionDispatcher.enqueue(action, source: .quickAction)
        }
        return true
    }
}
