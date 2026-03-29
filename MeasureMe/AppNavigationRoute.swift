import Foundation

enum AppNavigationRoute: Codable, Equatable, Sendable {
    case home
    case metricDetail(kindRaw: String)
    case quickAdd(kindRaw: String?)
}

enum AppNavigationRouteDispatcher {
    static let didEnqueueNotification = Notification.Name("appNavigationRouteDidEnqueue")

    @MainActor
    static func enqueue(_ route: AppNavigationRoute) {
        let settings = AppSettingsStore.shared
        guard let data = try? JSONEncoder().encode(route) else { return }
        settings.set(data, forKey: AppSettingsKeys.Entry.pendingNavigationRoute)
        NotificationCenter.default.post(name: didEnqueueNotification, object: route)
    }

    @MainActor
    static func consumePendingRoute() -> AppNavigationRoute? {
        let settings = AppSettingsStore.shared
        guard
            let data = settings.data(forKey: AppSettingsKeys.Entry.pendingNavigationRoute),
            let route = try? JSONDecoder().decode(AppNavigationRoute.self, from: data)
        else {
            return nil
        }
        settings.removeObject(forKey: AppSettingsKeys.Entry.pendingNavigationRoute)
        return route
    }
}
