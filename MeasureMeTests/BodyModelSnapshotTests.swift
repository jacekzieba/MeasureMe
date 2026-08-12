/// Cel testow: Snapshot ekranu modelu 3D w obu schematach kolorow.
/// Dlaczego to wazne: Manekin renderuje sie poza systemem designu; regresja kolorow jest tu latwa.
/// Kryteria zaliczenia: Render zgadza sie z baseline'em dla light i dark.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting
import SwiftData

// NOTE: record is controlled by the RECORD_SNAPSHOTS env var rather than a hard-coded flag.
// Set RECORD_SNAPSHOTS=1 in the scheme environment variables to record new reference snapshots.

@MainActor
final class BodyModelSnapshotTests: XCTestCase {

    // MARK: - Environment guard

    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    // MARK: - Managed UserDefaults keys
    //
    // Every key BodyModelScreen reads via @AppSetting, found in
    // MeasureMe/SettingsStore/AppSettingsKeys.swift (Profile / Experience enums):
    // - userGender, userAge, manualHeight, unitsSystem: AppSettingsKeys.Profile
    // - animationsEnabled: AppSettingsKeys.Experience
    // unitsSystem is read directly by the screen (to prefill the quick-add sheet) and
    // also by MetricKind formatting used in the change list rows.
    // appLanguage is included too, matching ComparePhotosSnapshotTests /
    // MetricDetailSnapshotTests, since the screen's strings are localized.
    private static let managedKeys: [String] = [
        "appLanguage",
        "unitsSystem",
        "userGender",
        "userAge",
        "manualHeight",
        "animationsEnabled",
    ]

    /// Fixed reference instant so nothing in the render depends on wall-clock time.
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private static let anchor = Date(timeIntervalSince1970: 1_695_000_000)

    // MARK: - Helpers

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

    /// Sets **every** key BodyModelScreen reads explicitly, rather than relying on
    /// whatever a previous test left behind — the home snapshot suite leaked
    /// metric-enable defaults between runs this way once already.
    private func configureDefaults() {
        AppClock.overrideNowForTesting = Self.fixedNow
        let d = UserDefaults.standard
        d.set("en", forKey: "appLanguage")
        d.set("metric", forKey: "unitsSystem")
        d.set("male", forKey: "userGender")
        d.set(30, forKey: "userAge")
        d.set(180.0, forKey: "manualHeight")
        d.set(false, forKey: "animationsEnabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: d)
        AppLocalization.reloadLanguage()
    }

    /// Two complete anchor snapshots (older/newer), 90 days apart, so the screen
    /// resolves to `.comparison` — the richest state: mannequin, date pickers, morph
    /// slider and the change list are all on screen at once.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: MetricGoal.self, MetricSample.self, PhotoEntry.self,
            configurations: config
        )
        let context = ModelContext(container)

        func insertCompleteSamples(at date: Date, waist: Double) {
            let values: [MetricKind: Double] = [
                .height: 180, .weight: 80, .bodyFat: 18,
                .neck: 38, .shoulders: 118, .chest: 100, .waist: waist, .hips: 98,
                .leftBicep: 34, .rightBicep: 34, .leftForearm: 28, .rightForearm: 28,
                .leftThigh: 58, .rightThigh: 58, .leftCalf: 38, .rightCalf: 38
            ]
            for (kind, value) in values {
                context.insert(MetricSample(kind: kind, value: value, date: date))
            }
        }

        insertCompleteSamples(at: Self.anchor.addingTimeInterval(-90 * 86_400), waist: 95)
        insertCompleteSamples(at: Self.anchor, waist: 85)
        try context.save()

        return container
    }

    private func makeHostingController(
        colorScheme: ColorScheme,
        container: ModelContainer
    ) -> UIHostingController<some View> {
        let premiumStore = PremiumStore(startListener: false)
        premiumStore.isPremium = true
        let router = AppRouter()

        let view = BodyModelScreen()
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

    /// Co sprawdza: Wyglad ekranu porownania w trybie ciemnym — manekin, pickery dat, suwak morfu, lista zmian.
    /// Dlaczego: SceneKit nie uczestniczy w systemie kolorow SwiftUI; regresja materialu/tla jest tu latwa do przeoczenia.
    /// Kryteria: Render zgadza sie z zarejestrowanym baseline'em.
    func testBodyModelComparison_snapshot_dark() async throws {
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

    /// Co sprawdza: Wyglad ekranu porownania w trybie jasnym — te same elementy co w dark.
    /// Dlaczego: MannequinView odswieza material recznie w updateUIView; bez tego jasny motyw renderuje ciemny blok.
    /// Kryteria: Render zgadza sie z zarejestrowanym baseline'em.
    func testBodyModelComparison_snapshot_light() async throws {
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
}
