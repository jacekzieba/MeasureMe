import Foundation
import os

enum StartupInstrumentation {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jacek.measureme",
        category: "Startup"
    )

    struct IntervalState {
        let signpostID: OSSignpostID
        let start: ContinuousClock.Instant
    }

    static func begin(_ name: StaticString) -> IntervalState {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        return IntervalState(signpostID: signpostID, start: ContinuousClock().now)
    }

    static func end(_ name: StaticString, state: IntervalState) {
        os_signpost(.end, log: log, name: name, signpostID: state.signpostID)
        let elapsed = state.start.duration(to: ContinuousClock().now)
        let milliseconds = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        AppLog.debug("⏱️ \(name): \(milliseconds) ms")
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
