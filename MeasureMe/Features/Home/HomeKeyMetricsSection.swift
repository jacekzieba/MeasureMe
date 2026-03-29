import SwiftUI

enum HomeKeyMetricsState {
    case noMeasurements
    case noSelection
    case content
}

struct HomeKeyMetricsSnapshot {
    let subtitle: String
    let state: HomeKeyMetricsState
}

struct HomeKeyMetricsCard<Content: View>: View {
    let snapshot: HomeKeyMetricsSnapshot
    let onAddMeasurement: () -> Void
    let onOpenMeasurements: () -> Void
    @ViewBuilder let content: () -> Content

    private let theme = FeatureTheme.measurements

    var body: some View {
        HomeWidgetCard(
            tint: theme.softTint,
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.keyMetrics"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                header

                switch snapshot.state {
                case .noMeasurements:
                    emptyStateCard(
                        title: AppLocalization.string("home.keymetrics.empty.title"),
                        detail: AppLocalization.string("home.keymetrics.empty.detail"),
                        ctaTitle: AppLocalization.string("Add measurement"),
                        action: onAddMeasurement
                    )
                case .noSelection:
                    emptyStateCard(
                        title: AppLocalization.string("home.keymetrics.empty.selection.title"),
                        detail: AppLocalization.string("home.keymetrics.empty.selection.detail"),
                        ctaTitle: AppLocalization.string("Open Measurements"),
                        action: onOpenMeasurements
                    )
                case .content:
                    content()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("home.module.metrics.eyebrow"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(Color.appAccent)
                    .textCase(.uppercase)

                Text(AppLocalization.string("Key metrics"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(snapshot.subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("home.module.keyMetrics.title")

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                headerAction(
                    systemImage: "plus",
                    accessibilityLabel: AppLocalization.string("Add measurement"),
                    action: onAddMeasurement
                )
                headerAction(
                    systemImage: "arrow.up.right",
                    accessibilityLabel: AppLocalization.string("accessibility.open.measurements"),
                    action: onOpenMeasurements
                )
            }
        }
    }

    private func headerAction(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(theme.pillFill)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func emptyStateCard(
        title: String,
        detail: String,
        ctaTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("home.empty.eyebrow"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(theme.accent)
                    .textCase(.uppercase)

                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(ctaTitle)
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(theme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
