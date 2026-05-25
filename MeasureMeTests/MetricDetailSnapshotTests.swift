/// Goal: Protect MetricDetailView against visual regressions introduced during Phase 1 refactor.
/// Why it matters: MetricDetailView renders a chart, goal line, history list, and AI insights
///   — any layout breakage affects the core measurement-tracking experience.
/// Pass criteria: Snapshot matches the reference for weight metric in both color schemes.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

// NOTE: record is controlled by the RECORD_SNAPSHOTS env var rather than a hard-coded flag.
// Set RECORD_SNAPSHOTS=1 in the scheme environment variables to record new reference snapshots.

@MainActor
final class MetricDetailSnapshotTests: XCTestCase {

    // MARK: - Environment guard

    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    // MARK: - Managed UserDefaults keys

    private static let managedKeys: [String] = [
        "appLanguage",
        "unitsSystem",
        "userGender",
        "animationsEnabled",
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
        d.set("metric", forKey: "unitsSystem")
        d.set("male", forKey: "userGender")
        d.set(false, forKey: "animationsEnabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: d)
        AppLocalization.reloadLanguage()
    }

    private func makeContainer(seedSamples: Bool) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )

        if seedSamples {
            let context = ModelContext(container)
            let today = Date()
            let cal = Calendar.current
            // 30 days of weight samples descending from 90 kg
            for offset in 0..<30 {
                let date = cal.date(byAdding: .day, value: -offset, to: today)!
                let sample = MetricSample(kind: .weight, value: 90.0 - Double(offset) * 0.15, date: date)
                context.insert(sample)
            }
            // One goal
            let goal = MetricGoal(kind: .weight, targetValue: 80.0)
            context.insert(goal)
            try context.save()
        }

        return container
    }

    private func makeHostingController(
        kind: MetricKind = .weight,
        colorScheme: ColorScheme,
        container: ModelContainer
    ) -> UIHostingController<some View> {
        let premiumStore = PremiumStore(startListener: false)
        let router = AppRouter()

        let view = NavigationStack {
            MetricDetailView(kind: kind)
        }
        .modelContainer(container)
        .environmentObject(premiumStore)
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

    func testMetricDetail_weight_emptyState_dark() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let container = try makeContainer(seedSamples: false)
        let vc = makeHostingController(colorScheme: .dark, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    func testMetricDetail_weight_withSamples_dark() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let container = try makeContainer(seedSamples: true)
        let vc = makeHostingController(colorScheme: .dark, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    func testMetricDetail_weight_withSamples_light() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let container = try makeContainer(seedSamples: true)
        let vc = makeHostingController(colorScheme: .light, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    func testMetricDetail_waist_withSamples_dark() async throws {
        try requireSimulatorSnapshotEnvironment()

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        configureDefaults()
        UIView.setAnimationsEnabled(false)

        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )
        let context = ModelContext(container)
        let today = Date()
        let cal = Calendar.current
        for offset in 0..<20 {
            let date = cal.date(byAdding: .day, value: -offset * 2, to: today)!
            let sample = MetricSample(kind: .waist, value: 88.0 - Double(offset) * 0.2, date: date)
            context.insert(sample)
        }
        try context.save()

        let vc = makeHostingController(kind: .waist, colorScheme: .dark, container: container)

        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }
}
