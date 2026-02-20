import Foundation

enum AuditRoute: String, Equatable {
    case dashboard
    case measurements
    case photos
    case settings
    case paywall
}

struct AuditConfig: Equatable {
    let isEnabled: Bool
    let useMockData: Bool
    let disableAnalytics: Bool
    let disablePaywallNetwork: Bool
    let fixedDate: Date?
    let route: AuditRoute?

    static let current: AuditConfig = from(
        args: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    static func from(args: [String], environment: [String: String]) -> AuditConfig {
        let fixedDate = parseFixedDate(args: args, environment: environment)
        let route = args.value(after: "-auditRoute")
            .map { $0.lowercased() }
            .flatMap(AuditRoute.init(rawValue:))

        let isEnabled = args.contains("-auditCapture") || environment.boolFlag("AUDIT_CAPTURE")
        let useMockData = args.contains("-useMockData")
            || environment.boolFlag("MOCK_DATA")
            || environment.boolFlag("NETWORK_STUB")
        let disableAnalytics = args.contains("-disableAnalytics")
            || environment.boolFlag("DISABLE_ANALYTICS")
        let disablePaywallNetwork = args.contains("-disablePaywallNetwork")
            || environment.boolFlag("NETWORK_STUB")
            || environment.boolFlag("DISABLE_PAYWALL_NETWORK")

        return AuditConfig(
            isEnabled: isEnabled,
            useMockData: useMockData,
            disableAnalytics: disableAnalytics,
            disablePaywallNetwork: disablePaywallNetwork,
            fixedDate: fixedDate,
            route: route
        )
    }

    private static func parseFixedDate(args: [String], environment: [String: String]) -> Date? {
        let parser = ISO8601DateFormatter()
        if let argDate = args.value(after: "-fixedDate"), let parsed = parser.date(from: argDate) {
            return parsed
        }
        if let envDate = environment["FIXED_DATE"], let parsed = parser.date(from: envDate) {
            return parsed
        }
        return nil
    }
}

enum AppClock {
    static var now: Date {
        AuditConfig.current.fixedDate ?? Date()
    }
}

private extension Array where Element == String {
    func value(after flag: String) -> String? {
        guard let index = firstIndex(of: flag) else { return nil }
        let next = self.index(after: index)
        guard next < endIndex else { return nil }
        return self[next]
    }
}

private extension Dictionary where Key == String, Value == String {
    func boolFlag(_ key: String) -> Bool {
        guard let raw = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return raw == "1" || raw == "true" || raw == "yes"
    }
}
