import SwiftUI

/// Primary accent button style used for the main action on a screen.
struct AppPrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = animationsEnabled && !reduceMotion
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.appWhite)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.appAccent.opacity(configuration.isPressed ? 0.24 : 0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(configuration.isPressed ? 0.34 : 0.24), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 0.5)
                            .stroke(Color.black.opacity(0.22), lineWidth: 0.6)
                    )
            )
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
    }
}

/// Solid accent button style for high-contrast primary actions.
struct AppAccentButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = animationsEnabled && !reduceMotion
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.appAccent)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
    }
}
