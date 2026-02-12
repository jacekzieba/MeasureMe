import SwiftUI

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.appNavy,
                Color.appBlack
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
