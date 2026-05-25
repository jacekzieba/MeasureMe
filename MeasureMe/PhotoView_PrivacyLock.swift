import SwiftUI
import SwiftData
import UIKit

// MARK: - Privacy locked overlay

struct PhotoPrivacyLockedView: View {
    let onUnlock: () -> Void

    var body: some View {
        AppGlassCard(
            depth: .floating,
            cornerRadius: 18,
            tint: FeatureTheme.photos.strongTint,
            contentPadding: 18
        ) {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FeatureTheme.photos.accent)

                Text(AppLocalization.string("Photos locked"))
                    .font(AppTypography.headlineEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("Unlock to view progress photos."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onUnlock) {
                    Label(AppLocalization.string("Unlock photos"), systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                .accessibilityIdentifier("photos.privacy.unlock")
            }
        }
    }
}
