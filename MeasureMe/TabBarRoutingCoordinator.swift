import Foundation

enum TabBarInitialRoute {
    case tab(AppTab)
    case settingsPaywall
}

enum TabBarRoutingCoordinator {
    static func initialRoute(didApplyAuditRoute: Bool) -> TabBarInitialRoute? {
        if UITestArgument.isPresent(.openSettingsTab) {
            return .tab(.settings)
        }

        guard AuditConfig.current.isEnabled else { return nil }
        guard !didApplyAuditRoute else { return nil }

        guard let route = AuditConfig.current.route else { return nil }
        switch route {
        case .dashboard:
            return .tab(.home)
        case .measurements:
            return .tab(.measurements)
        case .photos:
            return .tab(.photos)
        case .settings:
            return .tab(.settings)
        case .paywall:
            return .settingsPaywall
        }
    }

    static func pendingEntryAction(
        didConsumeUITestFallback: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> (action: AppEntryAction, consumedUITestFallback: Bool)? {
        if let action = AppEntryActionDispatcher.consumePendingAction() {
            return (action, didConsumeUITestFallback)
        }

        #if DEBUG
        guard !didConsumeUITestFallback else { return nil }
        guard let value = UITestArgument.value(for: .pendingAppEntryAction, in: arguments) else { return nil }
        guard let action = AppEntryAction(rawValue: value) else { return nil }
        return (action, true)
        #else
        return nil
        #endif
    }
}
