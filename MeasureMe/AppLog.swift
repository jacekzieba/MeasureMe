import Foundation

enum AppLog {
    private static let diagnosticsLoggingEnabledKey = "diagnostics_logging_enabled"

    private nonisolated static var shouldPersistLogs: Bool {
        #if DEBUG
        return true
        #else
        let defaults = UserDefaults.standard
        if defaults.object(forKey: diagnosticsLoggingEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: diagnosticsLoggingEnabledKey)
        #endif
    }

    nonisolated static func debug(_ message: @autoclosure () -> String) {
        let text = message()
        #if DEBUG
        print(text)
        #endif
        guard shouldPersistLogs else { return }
        Task { @MainActor in
            CrashReporter.shared.appendLog(text)
        }
    }

    nonisolated static func debug(_ items: Any...) {
        let text = items.map { String(describing: $0) }.joined(separator: " ")
        #if DEBUG
        print(text)
        #endif
        guard shouldPersistLogs else { return }
        Task { @MainActor in
            CrashReporter.shared.appendLog(text)
        }
    }
}
