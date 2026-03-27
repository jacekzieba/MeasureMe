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
        XCTAssertEqual(rgba(Color.appAccent, style: .light), rgba(Color.appAmberLight))
        XCTAssertEqual(rgba(Color.appAccent, style: .dark), rgba(Color.appAmber))
        XCTAssertEqual(rgba(Color.appGray, style: .dark), rgba(Color.appFog))
        XCTAssertEqual(rgba(Color.appGray, style: .light), rgba(Color.appInk.opacity(0.62)))
        XCTAssertEqual(rgba(Color.appWhite, style: .dark), rgba(Color.appPaper))
        XCTAssertEqual(rgba(Color.appWhite, style: .light), rgba(Color.appInk))
    }

    func testFeatureThemesExposeDistinctAccents() {
        XCTAssertNotEqual(rgba(FeatureTheme.home.accent), rgba(FeatureTheme.photos.accent))
        XCTAssertNotEqual(rgba(FeatureTheme.measurements.accent), rgba(FeatureTheme.premium.accent))
        XCTAssertNotEqual(rgba(FeatureTheme.health.accent), rgba(FeatureTheme.premium.accent))
    }

    func testSemanticRolesMapToExpectedPalette() {
        XCTAssertEqual(rgba(AppColorRoles.accentPrimary, style: .light), rgba(Color.appAmberLight))
        XCTAssertEqual(rgba(AppColorRoles.accentPrimary, style: .dark), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentPhoto), rgba(Color.appCyan))
        XCTAssertEqual(rgba(AppColorRoles.accentData), rgba(Color.appTeal))
        XCTAssertEqual(rgba(AppColorRoles.accentPremium, style: .light), rgba(Color.appAmberLight))
        XCTAssertEqual(rgba(AppColorRoles.accentPremium, style: .dark), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentHealth), rgba(Color.appEmerald))
        XCTAssertEqual(rgba(AppColorRoles.chartPositive), rgba(Color.appEmerald))
        XCTAssertEqual(rgba(AppColorRoles.compareAfter), rgba(Color.appAmber))
    }

    func testSemanticRolesAdaptAcrossLightAndDarkSchemes() {
        XCTAssertNotEqual(rgba(AppColorRoles.surfaceCanvas, style: .light), rgba(AppColorRoles.surfaceCanvas, style: .dark))
        XCTAssertNotEqual(rgba(AppColorRoles.textPrimary, style: .light), rgba(AppColorRoles.textPrimary, style: .dark))
        XCTAssertNotEqual(rgba(AppColorRoles.surfaceGlass, style: .light), rgba(AppColorRoles.surfaceGlass, style: .dark))
    }

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

    private func fontDescription(_ font: Font) -> String {
        String(describing: font)
    }
}
