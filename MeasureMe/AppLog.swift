import Foundation

enum AppLog {
    nonisolated static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    nonisolated static func debug(_ items: Any...) {
        #if DEBUG
        let text = items.map { String(describing: $0) }.joined(separator: " ")
        print(text)
        #endif
    }
}
