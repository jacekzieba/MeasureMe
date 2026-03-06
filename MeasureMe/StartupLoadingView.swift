import SwiftUI

struct StartupLoadingView: View {
    let statusKey: String
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isBreathing = false
    @State private var breathingTask: Task<Void, Never>?

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var progressPercentText: String {
        "\(Int((clampedProgress * 100).rounded()))%"
    }

    var body: some View {
        ZStack {
            StartupLoadingBackground()

            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 24 : 18) {
                VStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 84 : 72, height: dynamicTypeSize.isAccessibilitySize ? 84 : 72)
                        .shadow(color: Color.appAccent.opacity(0.24), radius: 14, x: 0, y: 5)
                        .scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1.03 : 0.97))
                        .accessibilityIdentifier("startup.loading.logo")

                    Text(AppLocalization.string("MeasureMe"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(Color.appWhite)

                    Text(AppLocalization.string(statusKey))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(Color.appGray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .accessibilityIdentifier("startup.loading.status")
                }

                VStack(spacing: 8) {
                    GeometryReader { proxy in
                        let barWidth = max(0, proxy.size.width * clampedProgress)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.appAccent.opacity(0.88), Color.appAccent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: barWidth)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("startup.loading.progress")
                    .accessibilityLabel(Text(AppLocalization.string("startup.loading.progress.label")))
                    .accessibilityValue(Text(progressPercentText))

                    Text(progressPercentText)
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(Color.appGray.opacity(0.85))
                        .monospacedDigit()
                }
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 6 : 14)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("startup.loading.root")
        .onAppear {
            guard !reduceMotion else { return }
            breathingTask?.cancel()
            breathingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
        .onDisappear {
            breathingTask?.cancel()
            breathingTask = nil
            isBreathing = false
        }
    }
}

private struct StartupLoadingBackground: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.appNavy.opacity(0.96),
                    Color.appBlack
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.appAccent.opacity(0.22))
                .frame(width: 330, height: 330)
                .blur(radius: 58)
                .offset(x: -120, y: -210)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 56)
                .offset(x: 140, y: -160)
        }
        .accessibilityHidden(true)
    }
}
