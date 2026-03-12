import SwiftUI

enum AppColorRoles {
    static let surfaceCanvas = Color.appInk
    static let surfacePrimary = Color.white.opacity(0.07)
    static let surfaceSecondary = Color.black.opacity(0.26)
    static let surfaceElevated = Color.white.opacity(0.09)
    static let surfaceInteractive = Color.white.opacity(0.05)
    static let surfaceGlass = Color.white.opacity(0.06)
    static let surfaceAccentSoft = Color.white.opacity(0.08)

    static let borderSubtle = Color.white.opacity(0.12)
    static let borderStrong = Color.white.opacity(0.22)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.74)
    static let textTertiary = Color.white.opacity(0.58)
    static let textOnAccent = Color.appInk

    static let accentPrimary = Color.appAmber
    static let accentPhoto = Color.appCyan
    static let accentData = Color.appTeal
    static let accentPhysique = Color.appIndigo
    static let accentPremium = Color.appAmber
    static let accentHealth = Color.appEmerald

    static let stateSuccess = Color.appEmerald
    static let stateWarning = Color.appAmber
    static let stateError = Color(hex: "#EF4444")
    static let stateInfo = Color.appCyan

    static let chartPositive = Color.appEmerald
    static let chartNegative = Color.appRose
    static let chartNeutral = Color.appFog.opacity(0.8)
    static let compareBefore = Color.appCyan
    static let compareAfter = Color.appAmber
}
