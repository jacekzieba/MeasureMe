// AppColors.swift
//
// **AppColors**
// Hex-based color palette and dark/light dynamic helpers.
//
// **Responsibilities:**
// - Defining the brand palette as named `Color` constants
// - Resolving dynamic (light/dark) colors via a single helper
// - Preserving backward-compatible aliases used by older call sites
//
// **Relationship to the design system:**
// This file holds raw color *values*. Semantic role-based colors (e.g. surface
// canvas, text primary) live in `DesignSystem/AppColorRoles.swift`. Feature code
// should prefer the role-based tokens; this file is for the design-system
// internals and one-off brand assets.
//
import SwiftUI
import UIKit

extension Color {
    // MARK: - Base palette

    /// Near-black ink (`#050816`) — the deepest tone in the brand palette.
    static let appInk = Color(hex: "#050816")
    /// Midnight blue (`#0C1329`) — used for subtle dark-mode surfaces.
    static let appMidnight = Color(hex: "#0C1329")
    /// Navy blue (`#14213D`) — base of the dark-mode background gradient.
    static let appNavy = Color(hex: "#14213D")
    /// Fog gray-blue (`#C6D0E1`) — used as light-mode `appGray` reference.
    static let appFog = Color(hex: "#C6D0E1")
    /// Paper white-blue (`#F3F7FD`) — light-mode `appWhite` reference.
    static let appPaper = Color(hex: "#F3F7FD")

    // MARK: - Accent palette

    /// Brand amber (`#FCA311`) — primary accent.
    static let appAmber = Color(hex: "#FCA311")
    /// Lighter amber (`#E87A08`) — used for warm hover/pressed states.
    static let appAmberLight = Color(hex: "#E87A08")
    /// Teal (`#29C7B8`).
    static let appTeal = Color(hex: "#29C7B8")
    /// Sky cyan (`#46B8FF`).
    static let appCyan = Color(hex: "#46B8FF")
    /// Soft indigo (`#7C8CFF`).
    static let appIndigo = Color(hex: "#7C8CFF")
    /// Emerald green (`#2DD881`) — used for positive trend deltas.
    static let appEmerald = Color(hex: "#2DD881")
    /// Rose pink (`#FF6B8A`).
    static let appRose = Color(hex: "#FF6B8A")
    /// Warm sunbeam yellow (`#FFE08A`).
    static let appSunbeam = Color(hex: "#FFE08A")
    /// Sky mist blue (`#DDF1FF`) — light-mode tint backgrounds.
    static let appSkyMist = Color(hex: "#DDF1FF")
    /// Mint mist green (`#C6F3E8`) — light-mode tint backgrounds.
    static let appMintMist = Color(hex: "#C6F3E8")
    /// Lilac mist purple (`#E7E9FF`) — light-mode tint backgrounds.
    static let appLilacMist = Color(hex: "#E7E9FF")
    /// Danger red (`#EF4444`) — destructive actions and error states.
    static let appDanger = Color(hex: "#EF4444")
    /// Information blue (`#3B82F6`) — neutral informational accents.
    static let appBlue = Color(hex: "#3B82F6")
    /// Violet (`#A78BFA`).
    static let appViolet = Color(hex: "#A78BFA")
    /// Mint green (`#5DD39E`).
    static let appMint = Color(hex: "#5DD39E")

    /// Resolves a color that differs between light and dark appearance.
    /// - Parameters:
    ///   - light: Color to use in light mode.
    ///   - dark: Color to use in dark mode.
    /// - Returns: A SwiftUI `Color` that automatically switches based on
    ///   the current `UITraitCollection.userInterfaceStyle`.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            }
        )
    }

    // MARK: - Backward compatibility

    /// Legacy alias for `appInk` — kept for older call sites.
    static let appBlack = appInk
    /// Brand accent — uses amber in both light and dark modes.
    static let appAccent = Color.dynamic(light: appAmber, dark: appAmber)
    /// Neutral mid-gray (light: `#5E5D59`, dark: `appFog`).
    static let appGray = Color.dynamic(
        light: Color(hex: "#5E5D59"),
        dark: Color.appFog
    )
    /// Soft text/icon background (light: `#141413`, dark: `appPaper`).
    static let appWhite = Color.dynamic(
        light: Color(hex: "#141413"),
        dark: Color.appPaper
    )
}
