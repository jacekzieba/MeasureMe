import Foundation

enum AppLog {
    private nonisolated static let diagnosticsLoggingEnabledKey = "diagnostics_logging_enabled"

    private nonisolated static var shouldPersistLogs: Bool {
        #if DEBUG
        return true
        #else
        // Opt-in: the buffer ends up in a file the person can mail out, so an absent
        // preference means "no", not "yes".
        return UserDefaults.standard.bool(forKey: diagnosticsLoggingEnabledKey)
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
