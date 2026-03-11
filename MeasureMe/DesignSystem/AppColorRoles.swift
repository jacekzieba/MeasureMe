import SwiftUI

enum AppColorRoles {
    static let surfacePrimary = Color.white.opacity(0.07)
    static let surfaceSecondary = Color.black.opacity(0.26)
    static let borderSubtle = Color.white.opacity(0.16)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.5)

    static let stateSuccess = Color.appEmerald
    static let stateWarning = Color.appAmber
    static let stateError = Color(hex: "#EF4444")

    // Feature accents
    static let accentData = Color.appTeal
    static let accentPhoto = Color.appCyan
    static let accentPremium = Color.appRose
    static let accentHealth = Color.appEmerald

    // Backward-compatible aliases used by in-flight UI refactors.
    static let surfaceCanvas = Color.black
    static let surfaceGlass = surfaceSecondary
    static let surfaceElevated = surfacePrimary
    static let surfaceInteractive = surfacePrimary
    static let borderStrong = borderSubtle
    static let accentPrimary = Color.appAmber
    static let chartPositive = stateSuccess
    static let chartNegative = stateError
    static let compareAfter = Color.appAmber
}
