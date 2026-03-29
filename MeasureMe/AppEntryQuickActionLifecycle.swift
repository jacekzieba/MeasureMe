import UIKit
import UserNotifications

final class MeasureMeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            NotificationManager.shared.configureAINotificationCategories()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MeasureMeSceneDelegate.self
        return configuration
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleAINotificationResponse(
                actionIdentifier: response.actionIdentifier,
                userInfo: response.notification.request.content.userInfo
            )
            completionHandler()
        }
    }
}

final class MeasureMeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        _ = enqueueShortcutIfNeeded(connectionOptions.shortcutItem)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(enqueueShortcutIfNeeded(shortcutItem))
    }

    @discardableResult
    private func enqueueShortcutIfNeeded(_ shortcutItem: UIApplicationShortcutItem?) -> Bool {
        guard
            let shortcutItem,
            let action = AppEntryAction(shortcutItemType: shortcutItem.type)
        else {
            return false
        }

        Task { @MainActor in
            AppEntryActionDispatcher.enqueue(action, source: .quickAction)
        }
        return true
    }
}
