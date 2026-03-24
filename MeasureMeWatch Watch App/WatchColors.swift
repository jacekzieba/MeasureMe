import SwiftUI

extension Color {
    /// App accent: #FCA311
    static let watchAccent = Color(red: 0.988, green: 0.639, blue: 0.067)
    /// Background navy: #14213D
    static let watchNavy   = Color(red: 0.078, green: 0.129, blue: 0.239)
    /// Positive trend: #22C55E
    static let watchGreen  = Color(red: 0.133, green: 0.773, blue: 0.369)
    /// Negative trend: #EF4444
    static let watchRed    = Color(red: 0.937, green: 0.267, blue: 0.267)
    /// Secondary copy tuned for small watch text.
    static let watchSecondaryText = Color.white.opacity(0.82)
    static let watchTertiaryText = Color.white.opacity(0.68)
    static let watchSubtleText = Color.white.opacity(0.56)
}
