/// Cel testu: Chroni ExperienceSettingsDetailView przed regresjami wizualnymi w trybie ciemnym i jasnym.
/// Dlaczego to ważne: Picker wyglądu (System/Light/Dark) i przełączniki muszą być czytelne w obu schematach kolorów.
/// Kryteria zaliczenia: Snapshot jest stabilny i zgodny ze wzorcem referencyjnym.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting

final class ExperienceSettingsDetailViewSnapshotTests: XCTestCase {
    private func requireSimulatorSnapshotEnvironment() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else {
            throw XCTSkip("Snapshot baseline is simulator-only")
        }
    }

    private func makeView(colorScheme: ColorScheme) -> some View {
        NavigationStack {
            ExperienceSettingsDetailView(
                appAppearance: .constant(AppAppearance.dark.rawValue),
                animationsEnabled: .constant(true),
                hapticsEnabled: .constant(true)
            )
        }
        .preferredColorScheme(colorScheme)
    }

    private func makeHostingController(view: some View, colorScheme: ColorScheme) -> UIHostingController<some View> {
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Tests

    @MainActor
    func testExperienceSettings_darkMode_snapshot() throws {
        try requireSimulatorSnapshotEnvironment()

        let baselineLanguage = UserDefaults.standard.object(forKey: "appLanguage")
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            if let baselineLanguage {
                UserDefaults.standard.set(baselineLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        UserDefaults.standard.set("en", forKey: "appLanguage")
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .dark), colorScheme: .dark)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    @MainActor
    func testExperienceSettings_lightMode_snapshot() throws {
        try requireSimulatorSnapshotEnvironment()

        let baselineLanguage = UserDefaults.standard.object(forKey: "appLanguage")
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            if let baselineLanguage {
                UserDefaults.standard.set(baselineLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        UserDefaults.standard.set("en", forKey: "appLanguage")
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .light), colorScheme: .light)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }
}
