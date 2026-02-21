import SwiftUI

/// Wspolne tlo atmosferyczne z subtelnym ruchem i ziarnem.
struct AppScreenBackground: View {
    var topHeight: CGFloat = 320
    var scrollOffset: CGFloat = 0
    var tint: Color = .appAccent.opacity(0.2)
    var showsSpotlight: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let parallax = scrollOffset * 0.06

            ZStack(alignment: .top) {
                Color.black
                    .ignoresSafeArea()

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
                    height: topHeight * 0.78
                )
                .offset(
                    x: -width * 0.08,
                    y: -88 + parallax
                )

                blob(
                    color: Color.cyan.opacity(0.18),
                    width: width * 0.86,
                    height: topHeight * 0.68
                )
                .offset(
                    x: width * 0.20,
                    y: 20 + parallax * 0.6
                )

                blob(
                    color: Color.white.opacity(0.10),
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
                        .frame(width: width * 0.58, height: topHeight * 0.66)
                        .blur(radius: 18)
                        .offset(
                            x: width * 0.22,
                            y: -topHeight * 0.16 + parallax * 0.7
                        )
                }

                FilmGrainOverlay()
                    .blendMode(.softLight)
                    .opacity(0.11)
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
    var body: some View {
        Canvas { context, size in
            for index in 0..<1000 {
                let x = seeded(Float(index) * 12.93) * size.width
                let y = seeded(Float(index) * 67.31) * size.height
                let alpha = 0.04 + seeded(Float(index) * 3.17) * 0.08
                let point = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(point), with: .color(.white.opacity(Double(alpha))))
            }
        }
        .allowsHitTesting(false)
    }

    private func seeded(_ value: Float) -> CGFloat {
        let sine = sin(Double(value) * 12.9898) * 43758.5453
        return CGFloat(sine - floor(sine))
    }
}
