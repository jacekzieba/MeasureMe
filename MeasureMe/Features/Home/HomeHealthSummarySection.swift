import SwiftUI

struct HomeHealthStatItemViewModel: Identifiable {
    let label: String
    let value: String
    let badge: String?

    var id: String { label }
}

struct HomeHealthSummarySnapshot {
    let subtitle: String
    let pillText: String
    let emptyTitle: String
    let emptyDetail: String
    let emptyCTA: String
    let summaryTitle: String
    let summaryDetail: String
    let isPremium: Bool
    let isSyncEnabled: Bool
}

struct HomeHealthSummaryCard: View {
    let snapshot: HomeHealthSummarySnapshot
    let items: [HomeHealthStatItemViewModel]
    let previewItems: [HomeHealthStatItemViewModel]
    let onConnectHealth: () -> Void
    let onOpenSettings: () -> Void
    let onOpenPremium: () -> Void

    private let healthTheme = FeatureTheme.health
    private let premiumTheme = FeatureTheme.premium

    var body: some View {
        HomeWidgetCard(
            tint: healthTheme.softTint,
            depth: .base,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.healthSummary"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("home.health.snapshot"))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(healthTheme.accent)
                            .textCase(.uppercase)

                        Text(AppLocalization.string("Health"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(snapshot.subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("home.module.healthSummary.title")

                    Text(snapshot.pillText)
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(healthTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppColorRoles.surfaceInteractive)
                        )
                }

                if items.isEmpty {
                    emptyStateCard
                } else if snapshot.isPremium {
                    premiumContent
                } else {
                    previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private var emptyStateCard: some View {
        Button(action: snapshot.isSyncEnabled ? onOpenSettings : onConnectHealth) {
            insightCard(
                eyebrow: AppLocalization.string("home.empty.eyebrow"),
                title: snapshot.emptyTitle,
                detail: snapshot.emptyDetail,
                note: snapshot.emptyCTA,
                tint: AppColorRoles.surfaceInteractive,
                stroke: AppColorRoles.borderSubtle,
                accent: healthTheme.accent
            )
        }
        .buttonStyle(.plain)
    }

    private var premiumContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            insightCard(
                eyebrow: AppLocalization.string("home.health.summary.card"),
                title: snapshot.summaryTitle,
                detail: snapshot.summaryDetail,
                tint: healthTheme.pillFill,
                stroke: AppColorRoles.borderSubtle,
                accent: healthTheme.accent
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(items) { item in
                    compactHealthStatCard(item)
                }
            }
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(previewItems) { item in
                compactHealthStatCard(item)
                    .accessibilityIdentifier("home.health.preview.metric")
            }

            if let previewLabel = previewItems.first?.label {
                hiddenAccessibilityMarker(text: previewLabel, identifier: "home.health.preview.label")
            }

            if let previewBadge = previewItems.first?.badge {
                hiddenAccessibilityMarker(text: previewBadge, identifier: "home.health.preview.badge")
            }

            Button(action: onOpenPremium) {
                insightCard(
                    eyebrow: AppLocalization.string("home.health.summary.card"),
                    title: AppLocalization.string("home.health.premium.title"),
                    detail: AppLocalization.string("home.health.premium.detail"),
                    note: AppLocalization.string("home.photos.compare.note.premium"),
                    tint: premiumTheme.pillFill,
                    stroke: premiumTheme.border,
                    accent: healthTheme.accent
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.health.premium.button")
        }
    }

    private func compactHealthStatCard(_ item: HomeHealthStatItemViewModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.label)
                .font(AppTypography.eyebrow)
                .foregroundStyle(AppColorRoles.textTertiary)
                .lineLimit(1)

            Text(item.value)
                .font(AppTypography.dataDelta)
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let badge = item.badge, !badge.isEmpty {
                Text(badge)
                    .font(AppTypography.badge)
                    .foregroundStyle(healthTheme.accent.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(healthTheme.pillFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(healthTheme.pillStroke, lineWidth: 1)
                            )
                    )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func insightCard(
        eyebrow: String,
        title: String,
        detail: String,
        note: String? = nil,
        tint: Color,
        stroke: Color,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(AppTypography.eyebrow)
                .foregroundStyle(accent)
                .textCase(.uppercase)

            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)

            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note {
                Text(note)
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
    }

    private func hiddenAccessibilityMarker(text: String, identifier: String) -> some View {
        Text(text)
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .accessibilityIdentifier(identifier)
            .frame(width: 1, height: 1)
            .clipped()
    }
}
