@testable import MeasureMe

import SwiftUI
import UIKit
import XCTest

final class DesignSystemTokenTests: XCTestCase {
    func testLegacyTypographyAliasesResolveToNewRoleTokens() {
        XCTAssertEqual(fontDescription(AppTypography.screenTitle), fontDescription(AppTypography.displaySection))
        XCTAssertEqual(fontDescription(AppTypography.sectionTitle), fontDescription(AppTypography.titlePrimary))
        XCTAssertEqual(fontDescription(AppTypography.metricValue), fontDescription(AppTypography.dataHero))
    }

    func testLegacyBrandColorsDelegateToNewPalette() {
        XCTAssertEqual(rgba(Color.appBlack), rgba(Color.appInk))
        XCTAssertEqual(rgba(Color.appAccent), rgba(Color.appAmber))
        XCTAssertEqual(rgba(Color.appGray), rgba(Color.appFog))
        XCTAssertEqual(rgba(Color.appWhite), rgba(Color.appPaper))
    }

    func testFeatureThemesExposeDistinctAccents() {
        XCTAssertNotEqual(rgba(FeatureTheme.home.accent), rgba(FeatureTheme.photos.accent))
        XCTAssertNotEqual(rgba(FeatureTheme.measurements.accent), rgba(FeatureTheme.premium.accent))
        XCTAssertNotEqual(rgba(FeatureTheme.health.accent), rgba(FeatureTheme.premium.accent))
    }

    func testSemanticRolesMapToExpectedPalette() {
        XCTAssertEqual(rgba(AppColorRoles.accentPrimary), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentPhoto), rgba(Color.appCyan))
        XCTAssertEqual(rgba(AppColorRoles.accentData), rgba(Color.appTeal))
        XCTAssertEqual(rgba(AppColorRoles.accentPremium), rgba(Color.appRose))
        XCTAssertEqual(rgba(AppColorRoles.accentHealth), rgba(Color.appEmerald))
        XCTAssertEqual(rgba(AppColorRoles.chartPositive), rgba(Color.appEmerald))
        XCTAssertEqual(rgba(AppColorRoles.compareAfter), rgba(Color.appAmber))
    }

    private func rgba(_ color: Color) -> [CGFloat] {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue, alpha].map { round($0 * 1000) / 1000 }
    }

    private func fontDescription(_ font: Font) -> String {
        String(describing: font)
    }
}
