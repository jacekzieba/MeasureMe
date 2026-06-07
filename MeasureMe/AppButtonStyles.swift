// AppButtonStyles.swift
//
// **AppButtonStyles**
// Thin wrappers around the design-system button styles.
//
// **Responsibilities:**
// - Exposing `AppPrimaryButtonStyle` and `AppAccentButtonStyle` as the two
//   first-class button styles used by feature views
// - Delegating to the canonical styles in `DesignSystem/AppControlStyles.swift`
//   (`AppSecondaryButtonStyle`, `AppCTAButtonStyle`) so visual treatment stays
//   in one place
//
// **Why these wrappers exist:**
// Feature code prefers referring to a "primary" or "accent" button. When the
// design system evolves (e.g. a brand refresh), only the underlying style
// needs to change — call sites keep working.
//
import SwiftUI

/// Primary button style — for the dominant action on a screen (e.g. "Save").
///
/// Internally delegates to `AppSecondaryButtonStyle`, the canonical style
/// defined in the design-system module.
struct AppPrimaryButtonStyle: ButtonStyle {
    /// Corner radius in points. Default `12` matches the rest of the app.
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        AppSecondaryButtonStyle(cornerRadius: cornerRadius).makeBody(configuration: configuration)
    }
}

/// Accent button style — for high-contrast, high-emphasis CTAs
/// (e.g. "Start Premium", "Continue").
///
/// Internally delegates to `AppCTAButtonStyle(.large)`, the canonical style
/// defined in the design-system module.
struct AppAccentButtonStyle: ButtonStyle {
    /// Corner radius in points. Default `12` matches the rest of the app.
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        AppCTAButtonStyle(size: .large, cornerRadius: cornerRadius).makeBody(configuration: configuration)
    }
}
