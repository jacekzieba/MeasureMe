import SwiftUI

/// Reusable liquid-glass icon pill used across settings-like lists.
struct GlassPillIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(GlassPillBackground(colorScheme: colorScheme))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}

private struct GlassPillBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        let outerStroke = LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.55 : 0.60),
                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let specular = LinearGradient(
            colors: [
                Color.white.opacity(0.40),
                Color.white.opacity(0.12),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(outerStroke, lineWidth: 1)
            )
            .overlay(
                Capsule()
                    .inset(by: 0.5)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.20), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            )
            .overlay(
                Capsule()
                    .fill(specular)
                    .blur(radius: 8)
                    .opacity(colorScheme == .dark ? 0.35 : 0.45)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 10, x: 0, y: 6)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.05), radius: 4, x: 0, y: 2)
    }
}
