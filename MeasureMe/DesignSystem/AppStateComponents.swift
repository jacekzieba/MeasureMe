import SwiftUI

struct EmptyStateCard: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var accessibilityIdentifier: String? = nil

    var body: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.xl, tint: Color.appAccent.opacity(0.10), contentPadding: AppSpacing.md) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
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
                .tint(Color.appAccent)
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
