import Foundation

enum AppNavigationRoute: Codable, Equatable, Sendable {
    case home
    case measurements
    case settings
    case metricDetail(kindRaw: String)
    case quickAdd(kindRaw: String?)
}

enum AppNavigationRouteDispatcher {
    static let didEnqueueNotification = Notification.Name("appNavigationRouteDidEnqueue")
    private static let appGroupID = "group.com.jacek.measureme"
    private static let widgetPendingQuickAddKindKey = "widget_pending_quick_add_kind"

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
            return consumePendingRouteFromAppGroup()
        }
        settings.removeObject(forKey: AppSettingsKeys.Entry.pendingNavigationRoute)
        return route
    }

    @MainActor
    private static func consumePendingRouteFromAppGroup() -> AppNavigationRoute? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        guard let kindRaw = defaults.string(forKey: widgetPendingQuickAddKindKey) else { return nil }
        defaults.removeObject(forKey: widgetPendingQuickAddKindKey)
        if kindRaw == "__NONE__" {
            return .quickAdd(kindRaw: nil)
        }
        return .quickAdd(kindRaw: kindRaw)
    }
}
