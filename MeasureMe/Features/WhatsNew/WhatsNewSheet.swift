// WhatsNewSheet.swift
//
// **WhatsNewSheet**
// Release notes shown once, on the first launch after an update.
//
// Deliberately not a step-by-step flow: one screen, one dismiss. Anything that
// needs the user to *do* something belongs in the activation checklist, not here.
//
import SwiftUI

struct WhatsNewSheet: View {
    let release: WhatsNewRelease
    /// Optional deep link out of the sheet — the primary highlight is worth more
    /// when the user can reach it in one tap instead of hunting for the tab.
    var onOpenHighlight: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let theme = FeatureTheme.home

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 240, tint: theme.softTint)

            VStack(spacing: 0) {
                header
                    .padding(.top, 32)
                    .padding(.horizontal, AppSpacing.lg)

                ScrollView {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(release.highlights) { highlight in
                            highlightRow(highlight)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
                }

                actions
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
            }
        }
        // The identifier goes on a zero-size marker, not on the ZStack: applied to a
        // container it propagates down and overwrites every child's identifier, so the
        // buttons below came out as "whatsNew.sheet" and nothing could address them.
        // Same trick HomeWidgetCard uses.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("whatsNew.sheet")
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)

            Text(AppLocalization.string("whatsNew.title"))
                .font(AppTypography.displayStatement)
                .foregroundStyle(AppColorRoles.textPrimary)
                .multilineTextAlignment(.center)

            Text(String(format: AppLocalization.string("whatsNew.subtitle"), release.version))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func highlightRow(_ highlight: WhatsNewRelease.Highlight) -> some View {
        AppGlassCard(depth: .base, tint: AppColorRoles.surfacePrimary, contentPadding: 16) {
            HStack(alignment: .top, spacing: AppSpacing.smmd) {
                Image(systemName: highlight.systemImage)
                    .font(AppTypography.iconLarge)
                    .foregroundStyle(theme.accent)
                    .frame(width: 32, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string(highlight.titleKey))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string(highlight.messageKey))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.xs) {
            if let onOpenHighlight {
                Button {
                    onOpenHighlight()
                    dismiss()
                } label: {
                    Text(AppLocalization.string("whatsNew.action.open"))
                        .font(AppTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppAccentButtonStyle())
                .accessibilityIdentifier("whatsNew.open")
            }

            Button(AppLocalization.string("whatsNew.action.dismiss")) {
                dismiss()
            }
            .font(AppTypography.buttonLabel)
            .foregroundStyle(AppColorRoles.textSecondary)
            .accessibilityIdentifier("whatsNew.dismiss")
        }
    }
}
