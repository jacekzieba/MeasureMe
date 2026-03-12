import SwiftUI

extension Color {
    // MARK: - Base palette
    static let appInk = Color(hex: "#050816")
    static let appMidnight = Color(hex: "#0C1329")
    static let appNavy = Color(hex: "#14213D")
    static let appFog = Color(hex: "#C6D0E1")
    static let appPaper = Color(hex: "#F7F8FB")

    static let appAmber = Color(hex: "#FCA311")
    static let appTeal = Color(hex: "#29C7B8")
    static let appCyan = Color(hex: "#46B8FF")
    static let appIndigo = Color(hex: "#7C8CFF")
    static let appEmerald = Color(hex: "#2DD881")
    static let appRose = Color(hex: "#FF6B8A")

    // MARK: - Backward compatibility
    static let appBlack = appInk
    static let appAccent = appAmber
    static let appGray = appFog
    static let appWhite = appPaper
}
