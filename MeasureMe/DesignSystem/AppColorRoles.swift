import SwiftUI
import UIKit

enum AppColorRoles {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }

    static let surfaceCanvas = dynamic(
        light: UIColor(Color(hex: "#F2F6FD")),
        dark: UIColor(Color.appInk)
    )
    static let surfacePrimary = dynamic(
        light: UIColor(Color(hex: "#E5E5E5")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.07)
    )
    static let surfaceSecondary = dynamic(
        light: UIColor(Color(hex: "#DFDFDF")).withAlphaComponent(0.98),
        dark: UIColor.black.withAlphaComponent(0.26)
    )
    static let surfaceElevated = dynamic(
        light: UIColor(Color(hex: "#E5E5E5")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.09)
    )
    static let surfaceInteractive = dynamic(
        light: UIColor(Color(hex: "#E5E5E5")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.05)
    )
    static let surfaceGlass = dynamic(
        light: UIColor(Color(hex: "#E5E5E5")).withAlphaComponent(0.88),
        dark: UIColor.white.withAlphaComponent(0.06)
    )
    static let surfaceChrome = dynamic(
        light: UIColor(Color(hex: "#E5E5E5")).withAlphaComponent(0.94),
        dark: UIColor(Color.appMidnight).withAlphaComponent(0.86)
    )
    static let surfaceAccentSoft = dynamic(
        light: UIColor(Color(hex: "#DCDCDC")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.08)
    )

    static let borderSubtle = dynamic(
        light: UIColor(Color.appMidnight).withAlphaComponent(0.12),
        dark: UIColor.white.withAlphaComponent(0.12)
    )
    static let borderStrong = dynamic(
        light: UIColor(Color.appMidnight).withAlphaComponent(0.22),
        dark: UIColor.white.withAlphaComponent(0.22)
    )

    static let textPrimary = dynamic(
        light: UIColor(Color.appInk),
        dark: .white
    )
    static let textSecondary = dynamic(
        light: UIColor(Color.appInk).withAlphaComponent(0.80),
        dark: UIColor.white.withAlphaComponent(0.74)
    )
    static let textTertiary = dynamic(
        light: UIColor(Color.appInk).withAlphaComponent(0.64),
        dark: UIColor.white.withAlphaComponent(0.58)
    )
    static let textOnAccent = Color.appInk

    static let shadowSoft = dynamic(
        light: UIColor(Color.appNavy).withAlphaComponent(0.10),
        dark: UIColor.black.withAlphaComponent(0.18)
    )
    static let shadowStrong = dynamic(
        light: UIColor(Color.appNavy).withAlphaComponent(0.18),
        dark: UIColor.black.withAlphaComponent(0.30)
    )

    static let accentGradientStart = Color.dynamic(
        light: Color.appSunbeam,
        dark: Color(hex: "#FFC85A")
    )
    static let accentGradientMid = Color.dynamic(
        light: Color.appAmber,
        dark: Color.appAmber
    )
    static let accentGradientEnd = Color.dynamic(
        light: Color.appAmberLight,
        dark: Color(hex: "#E87A08")
    )
    static let surfaceWarmHighlight = Color.dynamic(
        light: Color(hex: "#E5E5E5"),
        dark: Color.white.opacity(0.06)
    )
    static let surfaceCoolHighlight = Color.dynamic(
        light: Color(hex: "#E5E5E5"),
        dark: Color.white.opacity(0.03)
    )

    static let accentPrimary = Color.dynamic(light: Color.appAmberLight, dark: Color.appAmber)
    static let accentPhoto = Color.appCyan
    static let accentData = Color.appTeal
    static let accentPhysique = Color.appIndigo
    static let accentPremium = Color.dynamic(light: Color.appAmberLight, dark: Color.appAmber)
    static let accentHealth = Color.appEmerald

    static let stateSuccess = Color.appEmerald
    static let stateWarning = Color.appAmber
    static let stateError = Color(hex: "#EF4444")
    static let stateInfo = Color.appCyan

    static let chartPositive = Color.appEmerald
    static let chartNegative = Color.appRose
    static let chartNeutral = Color.dynamic(
        light: Color.appNavy.opacity(0.52),
        dark: Color.appFog.opacity(0.8)
    )
    static let compareBefore = Color.appCyan
    static let compareAfter = Color.appAmber
}
