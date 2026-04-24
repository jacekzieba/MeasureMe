import SwiftUI

struct EmptyStateCard: View {
    private let premiumTheme = FeatureTheme.premium
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var accessibilityIdentifier: String? = nil

    var body: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.xl, tint: premiumTheme.softTint, contentPadding: AppSpacing.md) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(premiumTheme.accent)
                    .accessibilityHidden(true)

                Text(title)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
                        .appHitTarget()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct InlineErrorBanner: View {
    let message: String
    var accessibilityIdentifier: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColorRoles.stateError)
                .accessibilityHidden(true)

            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColorRoles.stateError.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(AppColorRoles.stateError.opacity(0.50), lineWidth: 1)
                )
        )
        .accessibilityLabel(message)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct LoadingBlock: View {
    let title: String
    var accessibilityIdentifier: String? = nil

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ProgressView()
                .tint(AppColorRoles.accentPremium)
                .accessibilityHidden(true)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColorRoles.surfacePrimary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct BeforeAfterSliderInteractionHint: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: compact ? 10 : 12, weight: .bold))
                .accessibilityHidden(true)

            Text(AppLocalization.string("beforeAfterSlider.hint"))
                .font(compact ? AppTypography.microEmphasis : AppTypography.captionEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(Color.appWhite)
        .padding(.horizontal, compact ? 9 : 11)
        .padding(.vertical, compact ? 5 : 7)
        .background(Color.black.opacity(0.42), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.string("beforeAfterSlider.hint"))
    }
}
