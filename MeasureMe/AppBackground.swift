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
                        Color(hex: "#F1F1F0"),
                        Color(hex: "#ECECEA"),
                        Color(hex: "#E3E3E0"),
                        Color(hex: "#EFEFED")
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

        }
        .ignoresSafeArea()
    }
}
