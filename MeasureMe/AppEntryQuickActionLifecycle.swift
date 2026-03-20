import UIKit

final class MeasureMeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MeasureMeSceneDelegate.self
        return configuration
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
