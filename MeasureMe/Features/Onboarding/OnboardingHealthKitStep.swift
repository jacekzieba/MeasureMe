import SwiftUI

struct OnboardingHealthKitStep: View {
    let isSyncEnabled: Bool
    let isRequesting: Bool
    let statusText: String?
    let onRequest: () -> Void

    var body: some View {
        healthKitCard
    }

    private var healthKitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingFeatureCard(
                icon: "heart.text.square",
                title: AppLocalization.systemString("Connect Apple Health"),
                detail: AppLocalization.systemString("We can automatically fill in some values from Apple Health and keep them updated later.")
            )

            Text(AppLocalization.systemString("If you already track weight, body fat, or lean body mass in Apple Health, we can import that automatically."))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)

            Button {
                onRequest()
            } label: {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView()
                            .controlSize(.small)
                        .tint(Color.appAccent)
                    }
                    Text(isSyncEnabled
                         ? AppLocalization.systemString("Connected")
                         : AppLocalization.systemString("Connect Apple Health"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
            .disabled(isRequesting || isSyncEnabled)
            .accessibilityIdentifier("onboarding.booster.healthkit")

            if let statusText, !statusText.isEmpty {
                Text(statusText)
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(isSyncEnabled ? Color.appAccent : AppColorRoles.textSecondary)
            }

            Text(AppLocalization.systemString("You can skip this and enter everything manually. You can also connect later in Settings."))
                .font(AppTypography.micro)
                .foregroundStyle(AppColorRoles.textTertiary)
        }
        .padding(12)
        .background(AppColorRoles.surfaceInteractive)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        )
    }
}
