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
        XCTAssertEqual(rgba(Color.appAccent, style: .light), rgba(Color.appAmber))
        XCTAssertEqual(rgba(Color.appAccent, style: .dark), rgba(Color.appAmber))
        XCTAssertEqual(rgba(Color.appGray, style: .dark), rgba(Color.appFog))
        XCTAssertEqual(rgba(Color.appGray, style: .light), rgba(Color(hex: "#5E5D59")))
        XCTAssertEqual(rgba(Color.appWhite, style: .dark), rgba(Color.appPaper))
        XCTAssertEqual(rgba(Color.appWhite, style: .light), rgba(Color(hex: "#141413")))
    }

    func testFeatureThemesExposeDistinctAccents() {
        XCTAssertNotEqual(rgba(FeatureTheme.home.accent), rgba(FeatureTheme.photos.accent))
        XCTAssertNotEqual(rgba(FeatureTheme.measurements.accent), rgba(FeatureTheme.premium.accent))
        XCTAssertNotEqual(rgba(FeatureTheme.health.accent), rgba(FeatureTheme.premium.accent))
    }

    func testSemanticRolesMapToExpectedPalette() {
        XCTAssertEqual(rgba(AppColorRoles.accentPrimary, style: .light), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentPrimary, style: .dark), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentPhoto), rgba(Color.appCyan))
        XCTAssertEqual(rgba(AppColorRoles.accentData), rgba(Color.appTeal))
        XCTAssertEqual(rgba(AppColorRoles.accentPremium, style: .light), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentPremium, style: .dark), rgba(Color.appAmber))
        XCTAssertEqual(rgba(AppColorRoles.accentHealth, style: .light), rgba(Color(hex: "#166534")))
        XCTAssertEqual(rgba(AppColorRoles.accentHealth, style: .dark), rgba(Color.appEmerald))
        XCTAssertEqual(rgba(AppColorRoles.stateSuccess, style: .light), rgba(Color(hex: "#166534")))
        XCTAssertEqual(rgba(AppColorRoles.stateSuccess, style: .dark), rgba(Color(hex: "#4ADE80")))
        XCTAssertEqual(rgba(AppColorRoles.chartPositive), rgba(Color.appEmerald))
        XCTAssertEqual(rgba(AppColorRoles.compareAfter), rgba(Color.appAmber))
    }

    func testSemanticRolesAdaptAcrossLightAndDarkSchemes() {
        XCTAssertNotEqual(rgba(AppColorRoles.surfaceCanvas, style: .light), rgba(AppColorRoles.surfaceCanvas, style: .dark))
        XCTAssertNotEqual(rgba(AppColorRoles.textPrimary, style: .light), rgba(AppColorRoles.textPrimary, style: .dark))
        XCTAssertNotEqual(rgba(AppColorRoles.surfaceGlass, style: .light), rgba(AppColorRoles.surfaceGlass, style: .dark))
    }

    func testHealthAccentMaintainsReadableContrastOnLightGlassSurfaces() {
        let lightGlassBackgrounds = [
            UIColor(Color(hex: "#E6E6E3")),
            UIColor(Color(hex: "#E0E0DD")),
            UIColor(Color(hex: "#D6D6D3")),
            UIColor(Color(hex: "#DDDDDA"))
        ]

        assertReadableContrast(for: AppColorRoles.accentHealth, backgrounds: lightGlassBackgrounds)
        assertReadableContrast(for: AppColorRoles.stateSuccess, backgrounds: lightGlassBackgrounds)
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

    private func assertReadableContrast(for color: Color, backgrounds: [UIColor]) {
        let foreground = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        for background in backgrounds {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(foreground: foreground, background: background),
                4.5,
                "Semantic accent should stay readable on light glass surfaces"
            )
        }
    }

    private func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
        let foregroundLuminance = relativeLuminance(for: foreground)
        let backgroundLuminance = relativeLuminance(for: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(for color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        let linearRed = linearize(red)
        let linearGreen = linearize(green)
        let linearBlue = linearize(blue)

        return (0.2126 * linearRed) + (0.7152 * linearGreen) + (0.0722 * linearBlue)
    }

    private func linearize(_ component: CGFloat) -> CGFloat {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}
