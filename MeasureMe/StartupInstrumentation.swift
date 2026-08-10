import Foundation
import os

enum StartupInstrumentation {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jacek.measureme",
        category: "Startup"
    )
    private static let appLaunchStart = ContinuousClock().now
    private static var launchToInteractive: IntervalState?

    /// Milliseconds from `markLaunchStart()` to `endLaunchToInteractive()`.
    /// `nil` until Home has rendered its first frame.
    private(set) static var launchToInteractiveMs: Int?

    struct IntervalState {
        let signpostID: OSSignpostID
        let start: ContinuousClock.Instant
    }

    /// Anchors the launch clock and opens the `LaunchToInteractive` interval.
    ///
    /// `appLaunchStart` is a lazy `static let`, so it is only anchored the first
    /// time it is touched. Without this call that first touch is whichever
    /// `event(_:)` fires soonest, which made every offset relative to that event
    /// instead of to launch — `FirstFrameReady` always reported `+0 ms`.
    static func markLaunchStart() {
        _ = appLaunchStart
        launchToInteractive = begin("LaunchToInteractive")
    }

    /// Closes the interval sampled by `XCTOSSignpostMetric` in the launch performance test.
    static func endLaunchToInteractive() {
        guard let state = launchToInteractive else { return }
        end("LaunchToInteractive", state: state)
        launchToInteractive = nil
        let elapsed = appLaunchStart.duration(to: ContinuousClock().now)
        launchToInteractiveMs = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
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
        let elapsed = appLaunchStart.duration(to: ContinuousClock().now)
        let milliseconds = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        AppLog.debug("🚀 \(name): +\(milliseconds) ms")
    }
}
