import SwiftUI

/// Compact flame + count badge for the Home greeting card.
///
/// When ``shouldAnimate`` is `true`, plays a glow + number-increment
/// celebration on first appearance (once per ISO week).
struct StreakBadge: View {
    let count: Int
    let shouldAnimate: Bool
    let onAnimationComplete: () -> Void

    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var glowOpacity: Double = 0
    @State private var displayedCount: Int = 0
    @State private var didRunAnimation = false

    private var effectiveAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(flameGradient)
                .shadow(
                    color: Color.orange.opacity(glowOpacity),
                    radius: glowOpacity > 0 ? 8 : 0
                )

            Text("\(displayedCount)")
                .font(AppTypography.captionEmphasis.monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("accessibility.streak.count", count))
        .onAppear {
            if shouldAnimate && !didRunAnimation {
                displayedCount = max(count - 1, 0)
                if effectiveAnimate {
                    runAnimation()
                } else {
                    displayedCount = count
                    onAnimationComplete()
                }
                didRunAnimation = true
            } else {
                displayedCount = count
            }
        }
        .onChange(of: count) { _, newCount in
            if !shouldAnimate {
                displayedCount = newCount
            }
        }
    }

    // MARK: - Private

    private var flameGradient: LinearGradient {
        LinearGradient(
            colors: [Color.yellow, Color.orange, Color.red.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func runAnimation() {
        // Phase 1: Glow up
        withAnimation(.easeInOut(duration: 0.4)) {
            glowOpacity = 0.6
        }

        // Phase 2: Increment number
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(AppMotion.emphasized) {
                displayedCount = count
            }
            Haptics.success()
        }

        // Phase 3: Fade glow + complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                glowOpacity = 0
            }
            onAnimationComplete()
        }
    }
}
