/// Goal: Protect OnboardingView against visual regressions introduced during Phase 1 refactor.
/// Why it matters: Onboarding is the first experience new users see; layout or color regressions
///   directly impact conversion and user trust.
/// Pass criteria: Snapshot of the welcome step matches the reference in both color schemes.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting

// NOTE: record is controlled by the RECORD_SNAPSHOTS env var rather than a hard-coded flag.
// Set RECORD_SNAPSHOTS=1 in the scheme environment variables to record new reference snapshots.

// MARK: - No-op stubs for OnboardingEffects dependencies

private final class StubOnboardingHealthKit: OnboardingHealthKitAuthorizing {
    func prepareAuthorizationRequest() async {}
    func requestAuthorization() async throws {}
    func fetchDateOfBirth() throws -> Date? { nil }
    func fetchLatestHeightInCentimeters() async throws -> (value: Double, date: Date)? { nil }
}

private final class StubOnboardingNotifications: OnboardingNotificationManaging {
    var notificationsEnabled: Bool = false
    var smartEnabled: Bool = false
    var smartTime: Date = .distantPast
    func requestAuthorization() async -> Bool { false }
    func loadReminders() -> [MeasurementReminder] { [] }
    func saveReminders(_ reminders: [MeasurementReminder]) {}
    func scheduleAllReminders(_ reminders: [MeasurementReminder]) {}
}

private final class StubOnboardingAnalytics: OnboardingAnalyticsTracking {
    func track(_ signal: AnalyticsSignal) {}
}

// MARK: -

@MainActor
final class OnboardingSnapshotTests: XCTestCase {

    // MARK: - Environment guard

    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    // MARK: - Managed UserDefaults keys

    private static let managedKeys: [String] = [
        "appLanguage",
        "hasCompletedOnboarding",
        "animationsEnabled",
        "unitsSystem",
    ]

    // MARK: - Helpers

    private func backupDefaults() -> [String: Any?] {
        let d = UserDefaults.standard
        return Dictionary(uniqueKeysWithValues: Self.managedKeys.map { ($0, d.object(forKey: $0)) })
    }

    private func restoreDefaults(_ baseline: [String: Any?]) {
        let d = UserDefaults.standard
        for (key, value) in baseline {
            if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = .shared
        AppLocalization.reloadLanguage()
    }

    private func configureDefaults() {
        let d = UserDefaults.standard
        d.set("en", forKey: "appLanguage")
        d.set(false, forKey: "hasCompletedOnboarding")
        d.set(false, forKey: "animationsEnabled")
        d.set("metric", forKey: "unitsSystem")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: d)
        AppLocalization.reloadLanguage()
    }

    private func makeEffects() -> OnboardingEffects {
        OnboardingEffects(
            healthKit: StubOnboardingHealthKit(),
            notifications: StubOnboardingNotifications(),
            analytics: StubOnboardingAnalytics()
        )
    }

    private func makeHostingController(colorScheme: ColorScheme) -> UIHostingController<some View> {
        let view = OnboardingView(effects: makeEffects())
            .preferredColorScheme(colorScheme)

        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Tests

    /// Welcome step — the very first screen shown to a new user.
    func testOnboarding_welcomeStep_dark() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(colorScheme: .dark)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image(precision: 0.99, perceptualPrecision: 0.98), record: shouldRecord)
    }

    func testOnboarding_welcomeStep_light() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(colorScheme: .light)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image(precision: 0.99, perceptualPrecision: 0.98), record: shouldRecord)
    }
}
