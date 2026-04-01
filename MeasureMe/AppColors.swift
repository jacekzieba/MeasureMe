import SwiftUI
import UIKit

extension Color {
    // MARK: - Base palette
    static let appInk = Color(hex: "#050816")
    static let appMidnight = Color(hex: "#0C1329")
    static let appNavy = Color(hex: "#14213D")
    static let appFog = Color(hex: "#C6D0E1")
    static let appPaper = Color(hex: "#F3F7FD")

    static let appAmber = Color(hex: "#FCA311")
    static let appAmberLight = Color(hex: "#E87A08")
    static let appTeal = Color(hex: "#29C7B8")
    static let appCyan = Color(hex: "#46B8FF")
    static let appIndigo = Color(hex: "#7C8CFF")
    static let appEmerald = Color(hex: "#2DD881")
    static let appRose = Color(hex: "#FF6B8A")
    static let appSunbeam = Color(hex: "#FFE08A")
    static let appSkyMist = Color(hex: "#DDF1FF")
    static let appMintMist = Color(hex: "#C6F3E8")
    static let appLilacMist = Color(hex: "#E7E9FF")

    static func dynamic(light: Color, dark: Color) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            }
        )
    }

    // MARK: - Backward compatibility
    static let appBlack = appInk
    static let appAccent = Color.dynamic(light: appAmber, dark: appAmber)
    static let appGray = Color.dynamic(
        light: Color(hex: "#5E5D59"),
        dark: Color.appFog
    )
    static let appWhite = Color.dynamic(
        light: Color(hex: "#141413"),
        dark: Color.appPaper
    )
}
