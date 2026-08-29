// WhatsNewGate.swift
//
// **WhatsNewGate**
// Decides whether the release-notes sheet should open on this launch.
//
// Pure by design: `@State` written on a View that was never installed silently
// vanishes, so a test driving `RootView` would pass without proving anything.
// The decision lives here, where a test can actually assert on it.
//
import Foundation

/// `nonisolated` on purpose: the target defaults to `@MainActor`, which would give `Decision`
/// a main-actor-isolated `Equatable` conformance — unusable from a nonisolated context and a
/// hard error under the Swift 6 language mode. Nothing here touches the main actor anyway.
nonisolated enum WhatsNewGate {
    enum Decision: Equatable {
        /// Open the sheet for this release, then stamp `version` as seen.
        case present(WhatsNewRelease)
        /// Nothing to show — record `version` so a later release is judged against it.
        case stampOnly(version: String)
        /// Already up to date; leave the stored version alone.
        case none
    }

    /// - Parameters:
    ///   - currentVersion: `CFBundleShortVersionString` of the running build.
    ///   - lastSeenVersion: `""` when the key has never been written.
    ///   - hasCompletedOnboarding: separates a fresh install from an upgrade.
    ///     Both arrive with an empty `lastSeenVersion`, but a user who has just
    ///     been walked through the app does not need to be told what changed in it.
    static func decide(
        currentVersion: String,
        lastSeenVersion: String,
        hasCompletedOnboarding: Bool
    ) -> Decision {
        guard !currentVersion.isEmpty else { return .none }
        guard lastSeenVersion != currentVersion else { return .none }

        if lastSeenVersion.isEmpty && !hasCompletedOnboarding {
            return .stampOnly(version: currentVersion)
        }

        guard let release = WhatsNewRelease.release(for: currentVersion) else {
            return .stampOnly(version: currentVersion)
        }
        return .present(release)
    }

    /// The running build's marketing version, or `""` when the bundle has none
    /// (unit-test hosts do).
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
