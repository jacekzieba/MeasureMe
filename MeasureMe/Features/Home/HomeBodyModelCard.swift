// HomeBodyModelCard.swift
//
// **HomeBodyModelCard**
// Home's entry point to the 3D body model.
//
// The model's only other door is an unlabelled `figure.stand` glyph in the Photos
// toolbar, which nobody finds on purpose. This card is the discovery surface — hence
// the BETA badge riding along: whoever meets the feature here meets the caveat with it.
//
import SwiftUI

struct HomeBodyModelCard: View {
    /// Drives the trailing glyph only: a locked model is still worth advertising,
    /// but it should look locked rather than ready.
    let isPremium: Bool
    let onOpen: () -> Void

    private let theme = FeatureTheme.photos

    var body: some View {
        Button(action: onOpen) {
            HomeWidgetCard(tint: theme.softTint) {
                HStack(alignment: .center, spacing: AppSpacing.smmd) {
                    Image(systemName: "figure.stand")
                        .font(AppTypography.iconHero)
                        .foregroundStyle(theme.accent)
                        .frame(width: 40)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(AppLocalization.string("home.bodyModel.title"))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)

                            Text(AppLocalization.string("bodyModel.beta.badge"))
                                .font(AppTypography.badge)
                                .foregroundStyle(AppColorRoles.textOnAccent)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(theme.accent))
                        }

                        Text(AppLocalization.string("home.bodyModel.subtitle"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isPremium ? "chevron.right" : "lock.fill")
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        // One element, one action: the badge and the chevron say nothing a screen
        // reader needs on their own, and three stops here would just be noise.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string("home.bodyModel.title"))
        .accessibilityHint(AppLocalization.string("home.bodyModel.subtitle"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.bodyModel.card")
    }
}
