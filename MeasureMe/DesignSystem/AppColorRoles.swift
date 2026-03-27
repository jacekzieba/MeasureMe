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
        light: UIColor(Color(hex: "#EBEBEA")),
        dark: UIColor(Color.appInk)
    )
    static let surfacePrimary = dynamic(
        light: UIColor(Color(hex: "#DFDFDD")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.07)
    )
    static let surfaceSecondary = dynamic(
        light: UIColor(Color(hex: "#D8D8D5")).withAlphaComponent(0.98),
        dark: UIColor.black.withAlphaComponent(0.26)
    )
    static let surfaceElevated = dynamic(
        light: UIColor(Color(hex: "#E3E3E0")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.09)
    )
    static let surfaceInteractive = dynamic(
        light: UIColor(Color(hex: "#DDDDDA")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.05)
    )
    static let surfaceGlass = dynamic(
        light: UIColor(Color(hex: "#DBDBD8")).withAlphaComponent(0.90),
        dark: UIColor.white.withAlphaComponent(0.06)
    )
    static let surfaceChrome = dynamic(
        light: UIColor(Color(hex: "#E1E1DE")).withAlphaComponent(0.95),
        dark: UIColor(Color.appMidnight).withAlphaComponent(0.86)
    )
    static let surfaceAccentSoft = dynamic(
        light: UIColor(Color(hex: "#D8D8D5")).withAlphaComponent(0.98),
        dark: UIColor.white.withAlphaComponent(0.08)
    )

    static let borderSubtle = dynamic(
        light: UIColor(Color.appMidnight).withAlphaComponent(0.09),
        dark: UIColor.white.withAlphaComponent(0.12)
    )
    static let borderStrong = dynamic(
        light: UIColor(Color.appMidnight).withAlphaComponent(0.15),
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
        light: UIColor(Color.appNavy).withAlphaComponent(0.14),
        dark: UIColor.black.withAlphaComponent(0.18)
    )
    static let shadowStrong = dynamic(
        light: UIColor(Color.appNavy).withAlphaComponent(0.22),
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
        light: Color(hex: "#E9E9E6"),
        dark: Color.white.opacity(0.06)
    )
    static let surfaceCoolHighlight = Color.dynamic(
        light: Color(hex: "#DFDFDC"),
        dark: Color.white.opacity(0.03)
    )

    static let accentPrimary = Color.dynamic(light: Color.appAmberLight, dark: Color.appAmber)
    static let accentPhoto = Color.appCyan
    static let accentData = Color.appTeal
    static let accentPhysique = Color.dynamic(
        light: Color(hex: "#4F46E5"),
        dark: Color(hex: "#A5B4FC")
    )
    static let accentPremium = Color.dynamic(light: Color.appAmberLight, dark: Color.appAmber)
    static let accentHealth = Color.appEmerald

    static let stateSuccessHex = "#16A34A"
    static let stateWarningHex = "#D97706"
    static let stateErrorHex = "#DC2626"
    static let stateInfoHex = "#2563EB"
    static let stateNeutralHex = "#64748B"

    static let stateSuccess = Color.dynamic(
        light: Color(hex: stateSuccessHex),
        dark: Color(hex: "#4ADE80")
    )
    static let stateWarning = Color.dynamic(
        light: Color(hex: stateWarningHex),
        dark: Color(hex: "#F59E0B")
    )
    static let stateError = Color.dynamic(
        light: Color(hex: stateErrorHex),
        dark: Color(hex: "#F87171")
    )
    static let stateInfo = Color.dynamic(
        light: Color(hex: stateInfoHex),
        dark: Color(hex: "#60A5FA")
    )

    static let chartPositive = Color.appEmerald
    static let chartNegative = Color.appRose
    static let chartNeutral = Color.dynamic(
        light: Color.appNavy.opacity(0.52),
        dark: Color.appFog.opacity(0.8)
    )
    static let compareBefore = Color.appCyan
    static let compareAfter = Color.appAmber
}
