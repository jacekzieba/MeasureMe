import SwiftUI

struct ScreenTitleHeader: View {
    let title: String
    var topPadding: CGFloat = 8
    var bottomPadding: CGFloat = 6
    var horizontalPadding: CGFloat = 20

    var body: some View {
        Text(title)
            .font(AppTypography.screenTitle)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
    }
}
