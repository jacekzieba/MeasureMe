import SwiftUI

enum HealthIndicatorPalette {
    static let emphasisHex = AppColorRoles.stateWarningHex
    static let placeholderHex = AppColorRoles.stateNeutralHex
    static let cardBackgroundHex = "#101A16"
    static let rowBackgroundHex = "#1B2B24"

    static let accent = AppColorRoles.accentHealth
    static let cardBackground = Color.dynamic(
        light: AppColorRoles.surfacePrimary,
        dark: Color(hex: cardBackgroundHex)
    )
    static let rowBackground = Color.dynamic(
        light: AppColorRoles.surfaceInteractive,
        dark: Color(hex: rowBackgroundHex)
    )
}
