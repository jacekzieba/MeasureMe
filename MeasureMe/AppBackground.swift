import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColorRoles.surfaceCanvas
                .ignoresSafeArea()

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color.appNavy,
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

            if colorScheme == .light {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#F2F3F6").opacity(0.72),
                                .clear
                            ],
                            center: .center,
                            startRadius: 24,
                            endRadius: 220
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: 120, y: -230)
                    .blur(radius: 18)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#ECEEF2").opacity(0.78),
                                .clear
                            ],
                            center: .center,
                            startRadius: 24,
                            endRadius: 240
                        )
                    )
                    .frame(width: 380, height: 380)
                    .offset(x: -140, y: 180)
                    .blur(radius: 24)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#E7E9ED").opacity(0.62),
                                .clear
                            ],
                            center: .center,
                            startRadius: 18,
                            endRadius: 180
                        )
                    )
                    .frame(width: 260, height: 260)
                    .offset(x: -120, y: -180)
                    .blur(radius: 18)
            }
        }
        .ignoresSafeArea()
    }
}
