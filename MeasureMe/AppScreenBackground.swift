import SwiftUI

/// Wspolne tlo atmosferyczne z subtelnym ruchem i ziarnem.
struct AppScreenBackground: View {
    var topHeight: CGFloat = 320
    var scrollOffset: CGFloat = 0
    var tint: Color = .appAccent.opacity(0.2)
    var showsSpotlight: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let parallax = scrollOffset * 0.06

            ZStack(alignment: .top) {
                AppColorRoles.surfaceCanvas
                    .ignoresSafeArea()

                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.appNavy.opacity(0.95),
                            Color.appBlack
                        ]
                        : [
                            Color.white,
                            Color(hex: "#F7F8FA"),
                            Color(hex: "#F0F2F5"),
                            Color(hex: "#FBFBFC")
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                blob(
                    color: colorScheme == .dark
                        ? tint
                        : Color(hex: "#F1F2F5").opacity(0.88),
                    width: width * 0.95,
                    height: topHeight * 0.78
                )
                .offset(
                    x: -width * 0.08,
                    y: -88 + parallax
                )

                blob(
                    color: colorScheme == .dark
                        ? Color.cyan.opacity(0.18)
                        : Color(hex: "#ECEEF2").opacity(0.76),
                    width: width * 0.86,
                    height: topHeight * 0.68
                )
                .offset(
                    x: width * 0.20,
                    y: 20 + parallax * 0.6
                )

                blob(
                    color: colorScheme == .dark
                        ? Color.white.opacity(0.10)
                        : Color.white.opacity(0.78),
                    width: width * 0.65,
                    height: topHeight * 0.48
                )
                .offset(
                    x: -width * 0.18,
                    y: 62 + parallax * 0.5
                )

                if showsSpotlight {
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
                        .opacity(colorScheme == .dark ? 1 : 0.72)
                        .frame(width: width * 0.58, height: topHeight * 0.66)
                        .blur(radius: 18)
                        .offset(
                            x: width * 0.22,
                            y: -topHeight * 0.16 + parallax * 0.7
                        )
                }

                if colorScheme == .light {
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#E8EAEE").opacity(0.78),
                                    Color(hex: "#E8EAEE").opacity(0.18),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: width * 0.52, height: topHeight * 0.48)
                        .blur(radius: 20)
                        .offset(
                            x: -width * 0.10,
                            y: -topHeight * 0.08 + parallax * 0.35
                        )

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.44),
                                    Color(hex: "#ECEEF2").opacity(0.22),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: topHeight * 0.86)
                        .blur(radius: 18)
                        .offset(y: -topHeight * 0.10)
                }

                FilmGrainOverlay()
                    .blendMode(colorScheme == .dark ? .softLight : .overlay)
                    .opacity(colorScheme == .dark ? 0.11 : 0.04)
                    .ignoresSafeArea()
            }
            .drawingGroup(opaque: false, colorMode: .extendedLinear)
        }
        .ignoresSafeArea()
    }

    private func blob(color: Color, width: CGFloat, height: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        color,
                        color.opacity(0.28),
                        .clear
                    ],
                    center: .center,
                    startRadius: 14,
                    endRadius: max(width, height) * 0.52
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 14)
    }
}

private struct FilmGrainOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            for index in 0..<1000 {
                let x = seeded(Float(index) * 12.93) * size.width
                let y = seeded(Float(index) * 67.31) * size.height
                let alpha = 0.04 + seeded(Float(index) * 3.17) * 0.08
                let point = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(
                    Path(point),
                    with: .color(
                        (colorScheme == .dark ? Color.white : Color.appInk)
                            .opacity(Double(alpha))
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
