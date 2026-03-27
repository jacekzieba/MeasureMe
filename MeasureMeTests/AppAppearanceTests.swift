@testable import MeasureMe

import SwiftUI
import UIKit
import XCTest

final class AppAppearanceTests: XCTestCase {

    // MARK: - preferredColorScheme

    func testPreferredColorScheme_system_returnsNil() {
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
    }

    func testPreferredColorScheme_light_returnsLight() {
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
    }

    func testPreferredColorScheme_dark_returnsDark() {
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
    }

    // MARK: - rawValue round-trip

    func testRawValueRoundTrip() {
        for appearance in AppAppearance.allCases {
            let reconstructed = AppAppearance(rawValue: appearance.rawValue)
            XCTAssertEqual(reconstructed, appearance, "rawValue round-trip failed for \(appearance)")
        }
    }

    func testUnknownRawValueReturnsNil() {
        XCTAssertNil(AppAppearance(rawValue: "unknown"))
        XCTAssertNil(AppAppearance(rawValue: ""))
    }

    // MARK: - settingsSummaryKey

    func testAllCasesHaveNonEmptySettingsSummaryKey() {
        for appearance in AppAppearance.allCases {
            XCTAssertFalse(
                appearance.settingsSummaryKey.isEmpty,
                "settingsSummaryKey should not be empty for \(appearance)"
            )
        }
    }

    func testSettingsSummaryKeysAreDistinct() {
        let keys = AppAppearance.allCases.map(\.settingsSummaryKey)
        XCTAssertEqual(keys.count, Set(keys).count, "All settingsSummaryKey values should be unique")
    }

    // MARK: - Registered default is .dark

    @MainActor
    func testDefaultRegisteredAppearanceIsDark() {
        let suite = "AppAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(
            store.snapshot.experience.appAppearance,
            AppAppearance.dark.rawValue,
            "Fresh install default should be dark, not system"
        )
    }

    // MARK: - Light vs dark color distinction

    func testLightModeColorsAreDistinctFromDark() {
        XCTAssertNotEqual(
            rgba(AppColorRoles.surfaceCanvas, style: .light),
            rgba(AppColorRoles.surfaceCanvas, style: .dark),
            "surfaceCanvas should differ between light and dark"
        )
        XCTAssertNotEqual(
            rgba(AppColorRoles.textPrimary, style: .light),
            rgba(AppColorRoles.textPrimary, style: .dark),
            "textPrimary should differ between light and dark"
        )
        XCTAssertNotEqual(
            rgba(AppColorRoles.surfacePrimary, style: .light),
            rgba(AppColorRoles.surfacePrimary, style: .dark),
            "surfacePrimary should differ between light and dark"
        )
    }

    // MARK: - Helpers

    private func rgba(_ color: Color, style: UIUserInterfaceStyle = .light) -> [CGFloat] {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        let uiColor = UIColor(color).resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue, alpha].map { round($0 * 1000) / 1000 }
    }
}
