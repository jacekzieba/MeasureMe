// Color+Hex.swift
//
// **Color+Hex Extension**
// Rozszerzenie Color umożliwiające inicjalizację kolorów z ciągów HEX.
//
// **Funkcje:**
// - Parsowanie kolorów w formacie "#RRGGBB"
// - Obsługa opcjonalnego kanału alpha "#RRGGBBAA"
// - Wsparcie dla formatów z lub bez #
//
import SwiftUI

extension Color {
    /// Inicjalizuje kolor z ciągu HEX
    /// - Parameter hex: Ciąg w formacie "#RRGGBB" lub "RRGGBB"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Returns black or white text color that best meets WCAG contrast on a given HEX background.
    /// For regular-size text we target at least 4.5:1.
    static func bestAccessibleTextColor(onHex backgroundHex: String, minimumRatio: Double = 4.5) -> Color {
        guard let bg = hexComponents(backgroundHex) else { return .white }

        let bgLuminance = relativeLuminance(r: bg.r, g: bg.g, b: bg.b)
        let whiteContrast = contrastRatio(foregroundLuminance: 1.0, backgroundLuminance: bgLuminance)
        let blackContrast = contrastRatio(foregroundLuminance: 0.0, backgroundLuminance: bgLuminance)

        if whiteContrast >= minimumRatio && whiteContrast >= blackContrast {
            return .white
        }

        if blackContrast >= minimumRatio && blackContrast >= whiteContrast {
            return .black
        }

        return whiteContrast >= blackContrast ? .white : .black
    }

    private static func contrastRatio(foregroundLuminance: Double, backgroundLuminance: Double) -> Double {
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        let rLinear = linearized(r)
        let gLinear = linearized(g)
        let bLinear = linearized(b)
        return 0.2126 * rLinear + 0.7152 * gLinear + 0.0722 * bLinear
    }

    private static func linearized(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private static func hexComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&int) else { return nil }

        let r, g, b: UInt64
        switch sanitized.count {
        case 3:
            r = (int >> 8) * 17
            g = (int >> 4 & 0xF) * 17
            b = (int & 0xF) * 17
        case 6:
            r = int >> 16
            g = int >> 8 & 0xFF
            b = int & 0xFF
        case 8:
            r = int >> 16 & 0xFF
            g = int >> 8 & 0xFF
            b = int & 0xFF
        default:
            return nil
        }

        return (Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)
    }
}
