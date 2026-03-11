import SwiftUI

extension Color {
    // MARK: - App Colors
    static let appBlack = Color(hex: "#000000")
    static let appNavy = Color(hex: "#14213D")
    static let appAccent = Color(hex: "#FCA311")
    static let appGray = Color(hex: "#E5E5E5")
    static let appWhite = Color(hex: "#FFFFFF")

    // Backward-compatible semantic palette aliases.
    static let appInk = appBlack
    static let appAmber = appAccent
    static let appFog = appGray
    static let appPaper = appWhite

    // Feature accents used by theme roles and token-compatibility tests.
    static let appCyan = Color(hex: "#22D3EE")
    static let appTeal = Color(hex: "#14B8A6")
    static let appRose = Color(hex: "#F43F5E")
    static let appEmerald = Color(hex: "#22C55E")
}
