/// Cel testu: Chroni szczegolowe ekrany wskaznikow zdrowotnych przed regresjami UI.
/// Dlaczego to wazne: Te widoki lacza wynik, kategorie ryzyka i tresci edukacyjne w osobnych layoutach.
/// Kryteria zaliczenia: Snapshot kazdego detail view jest stabilny i zgodny ze wzorcem referencyjnym.

@testable import MeasureMe

import SnapshotTesting
import SwiftUI
import XCTest

@MainActor
final class HealthIndicatorDetailSnapshotTests: XCTestCase {
    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    func testBMIDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "bmi",
            testName: #function,
            view: BMIDetailView(
                result: try XCTUnwrap(HealthMetricsCalculator.calculateBMI(weightKg: 82, heightCm: 180, age: 34))
            )
        )
    }

    func testWHRDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "whr-male",
            testName: #function,
            view: WHRDetailView(
                result: try XCTUnwrap(HealthMetricsCalculator.calculateWHR(waistCm: 84, hipsCm: 99, gender: .male)),
                gender: .male
            )
        )
    }

    func testWHtRDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "whtr",
            testName: #function,
            view: WHtRDetailView(
                result: try XCTUnwrap(HealthMetricsCalculator.calculateWHtR(waistCm: 84, heightCm: 180))
            )
        )
    }

    func testRFMDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "rfm-female",
            testName: #function,
            view: RFMDetailView(
                result: try XCTUnwrap(HealthMetricsCalculator.calculateRFM(waistCm: 78, heightCm: 168, gender: .female))
            )
        )
    }

    func testABSIDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "absi-male",
            testName: #function,
            view: ABSIDetailView(
                result: try XCTUnwrap(HealthMetricsCalculator.calculateABSI(waistCm: 84, heightCm: 180, weightKg: 82, gender: .male))
            )
        )
    }

    func testBodyFatDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "body-fat-female",
            testName: #function,
            view: BodyFatDetailView(value: 27.5, gender: .female)
        )
    }

    func testLeanMassDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "lean-mass-imperial",
            testName: #function,
            view: LeanMassDetailView(
                value: 63.0,
                percentage: 78.8,
                totalWeight: 80.0,
                age: 42,
                unitsSystem: "imperial"
            )
        )
    }

    func testConicityDetail_snapshot_dark() async throws {
        try await assertDetailSnapshot(
            named: "conicity-male",
            testName: #function,
            view: ConicityDetailView(
                result: try XCTUnwrap(HealthMetricsCalculator.calculateConicity(waistCm: 84, heightCm: 180, weightKg: 82, gender: .male))
            )
        )
    }

    private func assertDetailSnapshot<V: View>(named name: String, testName: String, view: V) async throws {
        try requireSimulatorSnapshotEnvironment()
        let defaults = UserDefaults.standard
        let keys = ["appLanguage", "unitsSystem", "userGender"]
        let baselineDefaults = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            for (key, value) in baselineDefaults {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        defaults.set("en", forKey: "appLanguage")
        defaults.set("metric", forKey: "unitsSystem")
        defaults.set("male", forKey: "userGender")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let root = NavigationStack {
            view
        }
        .preferredColorScheme(.dark)

        let vc = UIHostingController(rootView: root)
        vc.overrideUserInterfaceStyle = .dark
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 1200)
        let window = UIWindow(frame: vc.view.frame)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, named: name, record: shouldRecord, testName: testName)
    }
}
