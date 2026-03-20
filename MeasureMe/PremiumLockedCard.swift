import SwiftUI

struct PremiumLockedCard: View {
    private let premiumTheme = FeatureTheme.premium
    let title: String
    let message: String
    let onUpgrade: () -> Void

    var body: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 20,
            tint: premiumTheme.softTint,
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(premiumTheme.accent)
                    Text(title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }

                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Button(AppLocalization.string("View Premium options")) {
                    onUpgrade()
                }
                .buttonStyle(AppAccentButtonStyle())
            }
        }
    }
}
