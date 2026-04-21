import SwiftUI

/// Wspolne tlo atmosferyczne z subtelnym ruchem i ziarnem.
struct AppScreenBackground: View {
    var topHeight: CGFloat = 320
    var scrollOffset: CGFloat = 0
    var tint: Color = .appAccent.opacity(0.2)
    var showsSpotlight: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var prefersPerformanceMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || reduceMotion || reduceTransparency
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let parallaxMultiplier: CGFloat = prefersPerformanceMode ? 0.025 : 0.06
            let parallax = scrollOffset * parallaxMultiplier

            ZStack(alignment: .top) {
                AppColorRoles.surfaceCanvas
                    .ignoresSafeArea()

                if colorScheme == .dark {
                    LinearGradient(
                        colors: [
                            Color.appNavy.opacity(0.95),
                            Color.appBlack
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    blob(
                        color: tint,
                        width: width * 0.95,
                        height: topHeight * 0.78,
                        blurRadius: prefersPerformanceMode ? 18 : 32
                    )
                    .offset(
                        x: width * 0.16,
                        y: -108 + parallax
                    )

                    blob(
                        color: Color.cyan.opacity(0.18),
                        width: width * 0.86,
                        height: topHeight * 0.68,
                        blurRadius: prefersPerformanceMode ? 18 : 32
                    )
                    .offset(
                        x: -width * 0.18,
                        y: 18 + parallax * 0.6
                    )

                    blob(
                        color: Color.white.opacity(0.10),
                        width: width * 0.65,
                        height: topHeight * 0.48,
                        blurRadius: prefersPerformanceMode ? 14 : 28
                    )
                    .offset(
                        x: width * 0.22,
                        y: 54 + parallax * 0.5
                    )

                    if showsSpotlight && !prefersPerformanceMode {
                        Ellipse()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.03),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: width * 0.58, height: topHeight * 0.66)
                            .blur(radius: 18)
                            .offset(
                                x: -width * 0.08,
                                y: -topHeight * 0.12 + parallax * 0.7
                            )
                    }

                    if !prefersPerformanceMode {
                        FilmGrainOverlay(grainPoints: 420)
                            .blendMode(.softLight)
                            .opacity(0.09)
                            .ignoresSafeArea()
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func blob(color: Color, width: CGFloat, height: CGFloat, blurRadius: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        color,
                        color.opacity(0.32),
                        color.opacity(0.10),
                        color.opacity(0.02),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(width, height) * 0.48
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blurRadius)
    }
}

struct FilmGrainOverlay: View {
    var grainPoints: Int = 1000
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            for index in 0..<grainPoints {
                let x = seeded(Float(index) * 12.93) * size.width
                let y = seeded(Float(index) * 67.31) * size.height
                let alpha = 0.04 + seeded(Float(index) * 3.17) * 0.08
                let point = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(
                    Path(point),
                    with: .color(
                        (colorScheme == .dark ? Color.white : Color.appInk)
                            .opacity(colorScheme == .dark ? Double(alpha) : Double(alpha * 0.32))
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func seeded(_ value: Float) -> CGFloat {
        let sine = sin(Double(value) * 12.9898) * 43758.5453
        return CGFloat(sine - floor(sine))
    }
}
