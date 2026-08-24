/// Cel testow: Powierzchnie "glass" muszą respektować Reduce Transparency.
/// Dlaczego to wazne: To 109 miejsc w aplikacji; bez tego ustawienie systemowe nie robi nic.
/// Kryteria zaliczenia: Materiał jest używany wyłącznie w dark mode przy wyłączonym Reduce Transparency.

import XCTest
import SwiftUI
@testable import MeasureMe

final class AppGlassBackgroundTests: XCTestCase {
    func testDarkModeUsesMaterialOnlyWhenTransparencyIsAllowed() {
        XCTAssertFalse(AppGlassBackground.usesOpaqueFill(colorScheme: .dark, reduceTransparency: false))
        XCTAssertTrue(AppGlassBackground.usesOpaqueFill(colorScheme: .dark, reduceTransparency: true))
    }

    func testLightModeIsAlwaysOpaque() {
        XCTAssertTrue(AppGlassBackground.usesOpaqueFill(colorScheme: .light, reduceTransparency: false))
        XCTAssertTrue(AppGlassBackground.usesOpaqueFill(colorScheme: .light, reduceTransparency: true))
    }
}
