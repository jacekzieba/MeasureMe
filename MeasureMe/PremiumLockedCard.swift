import SwiftUI

struct PremiumLockedCard: View {
    let title: String
    let message: String
    let onUpgrade: () -> Void

    var body: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 20,
            tint: Color.appAccent.opacity(0.12),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color(hex: "#FCA311"))
                    Text(title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                }

                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Button(AppLocalization.string("View Premium options")) {
                    onUpgrade()
                }
                .buttonStyle(AppAccentButtonStyle())
            }
        }
    }
}
