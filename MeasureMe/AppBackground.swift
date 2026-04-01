import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColorRoles.surfaceCanvas
                .ignoresSafeArea()

            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color.appNavy,
                        Color.appBlack
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}
