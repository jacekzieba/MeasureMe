/// Goal: Protect HomeView against visual regressions introduced during Phase 1 refactor.
/// Why it matters: HomeView is the main landing screen and surfaces metrics, photos, streak, and health data.
/// Pass criteria: Snapshot matches the reference for both light and dark color schemes.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

// NOTE: record is controlled by the RECORD_SNAPSHOTS env var rather than a hard-coded flag.
// Set RECORD_SNAPSHOTS=1 in the scheme environment variables to record new reference snapshots.

@MainActor
final class HomeViewSnapshotTests: XCTestCase {

    // MARK: - Environment guard

    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    // MARK: - Managed UserDefaults keys

    private static let managedKeys: [String] = [
        "appLanguage",
        "userName",
        "userAge",
        "userGender",
        "manualHeight",
        "unitsSystem",
        "hasCompletedOnboarding",
        "animationsEnabled",
        "showLastPhotosOnHome",
        "showMeasurementsOnHome",
        "showHealthMetricsOnHome",
        "showStreakOnHome",
        "apple_intelligence_enabled",
        "premium_entitlement",
    ]

    /// Fixed reference instant so seeded sample dates and any
    /// `AppClock.now`-based rendering stay deterministic across runs.
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    // Force AI insights off deterministically, independent of global
    // `MetricInsightService.shared` state leaked by other test classes.
    override func setUp() async throws {
        try await super.setUp()
        await MetricInsightService.shared.setTestAvailabilityOverride(false)
    }

    override func tearDown() async throws {
        await MetricInsightService.shared.setTestAvailabilityOverride(nil)
        try await super.tearDown()
    }

    // MARK: - Setup / teardown helpers

    private func backupDefaults() -> [String: Any?] {
        let d = UserDefaults.standard
        return Dictionary(uniqueKeysWithValues: Self.managedKeys.map { ($0, d.object(forKey: $0)) })
    }

    private func restoreDefaults(_ baseline: [String: Any?]) {
        AppClock.overrideNowForTesting = nil
        let d = UserDefaults.standard
        for (key, value) in baseline {
            if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = .shared
        AppLocalization.reloadLanguage()
    }

    private func configureDefaults() {
        AppClock.overrideNowForTesting = Self.fixedNow
        let d = UserDefaults.standard
        d.set("en", forKey: "appLanguage")
        d.set("Test User", forKey: "userName")
        d.set(32, forKey: "userAge")
        d.set("male", forKey: "userGender")
        d.set(180.0, forKey: "manualHeight")
        d.set("metric", forKey: "unitsSystem")
        d.set(true, forKey: "hasCompletedOnboarding")
        d.set(false, forKey: "animationsEnabled")
        d.set(true, forKey: "showLastPhotosOnHome")
        d.set(true, forKey: "showMeasurementsOnHome")
        d.set(true, forKey: "showHealthMetricsOnHome")
        d.set(true, forKey: "showStreakOnHome")
        d.set(false, forKey: "apple_intelligence_enabled")
        d.set(false, forKey: "premium_entitlement")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: d)
        AppLocalization.reloadLanguage()
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )
    }

    private func makeHostingController(
        colorScheme: ColorScheme,
        container: ModelContainer
    ) -> UIHostingController<some View> {
        let metricsStore = ActiveMetricsStore()
        let premiumStore = PremiumStore(startListener: false)
        let pendingPhotoStore = PendingPhotoSaveStore(autoStartProcessing: false)
        let router = AppRouter()

        let view = HomeView()
            .modelContainer(container)
            .environmentObject(metricsStore)
            .environmentObject(premiumStore)
            .environmentObject(pendingPhotoStore)
            .environmentObject(router)
            .preferredColorScheme(colorScheme)

        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Tests

    func testHomeView_emptyState_dark() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let container = try makeContainer()
        let vc = makeHostingController(colorScheme: .dark, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1800))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image(precision: 0.99, perceptualPrecision: 0.98), record: shouldRecord)
    }

    func testHomeView_emptyState_light() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let container = try makeContainer()
        let vc = makeHostingController(colorScheme: .light, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1800))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image(precision: 0.99, perceptualPrecision: 0.98), record: shouldRecord)
    }

    func testHomeView_withSamples_dark() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let container = try makeContainer()
        let context = ModelContext(container)

        // Seed some samples so the home screen has data to display
        let today = AppClock.now
        let cal = Calendar.current
        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let weight = MetricSample(kind: .weight, value: 82.0 - Double(offset) * 0.1, date: date)
            context.insert(weight)
        }
        try context.save()

        let vc = makeHostingController(colorScheme: .dark, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1800))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image(precision: 0.99, perceptualPrecision: 0.98), record: shouldRecord)
    }
}
