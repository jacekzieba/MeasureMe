import Foundation

enum AppLog {
    nonisolated static func debug(_ message: @autoclosure () -> String) {
        let text = message()
        #if DEBUG
        print(text)
        #endif
        Task { @MainActor in
            CrashReporter.shared.appendLog(text)
        }
    }

    nonisolated static func debug(_ items: Any...) {
        let text = items.map { String(describing: $0) }.joined(separator: " ")
        #if DEBUG
        print(text)
        #endif
        Task { @MainActor in
            CrashReporter.shared.appendLog(text)
        }
    }
}
