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
    let onEdit: () -> Void
    @ViewBuilder let content: () -> Content

    private let theme = FeatureTheme.measurements

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityIdentifier("home.module.keyMetrics")
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("Key metrics"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .textCase(.uppercase)

                if snapshot.state != .content {
                    Text(snapshot.subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("home.module.keyMetrics.title")

            Spacer(minLength: 8)

            Button(action: onEdit) {
                Text(AppLocalization.string("Edit"))
                    .font(AppTypography.sectionAction)
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Open tracked metrics settings"))
        }
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
