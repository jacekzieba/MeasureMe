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
    let onOpenHealth: () -> Void
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
                } else {
                    summaryContent
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

    private var summaryContent: some View {
        Button(action: snapshot.isPremium ? onOpenHealth : onOpenPremium) {
            VStack(alignment: .leading, spacing: 10) {
                insightCard(
                    eyebrow: AppLocalization.string("home.health.summary.card"),
                    title: snapshot.summaryTitle,
                    detail: snapshot.summaryDetail,
                    tint: healthTheme.pillFill,
                    stroke: AppColorRoles.borderSubtle,
                    accent: healthTheme.accent
                )

                if let headlineItem {
                    headlineHealthStatCard(headlineItem)
                }

                HStack(spacing: 6) {
                    Text(additionalIndicatorsText)
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(healthTheme.accent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(healthTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(snapshot.isPremium ? "home.health.open.button" : "home.health.premium.button")
    }

    private var headlineItem: HomeHealthStatItemViewModel? {
        previewItems.first ?? items.first
    }

    private var additionalIndicatorsText: String {
        let additionalCount = max(items.count - 1, 0)
        if additionalCount <= 0 {
            return FlowLocalization.app("Open Health indicators", "Otwórz wskaźniki zdrowia", "Abrir indicadores de salud", "Gesundheitsindikatoren öffnen", "Ouvrir les indicateurs santé", "Abrir indicadores de saúde")
        }
        return FlowLocalization.app(
            "\(additionalCount) more indicators",
            "\(additionalCount) więcej wskaźników",
            "\(additionalCount) indicadores más",
            "\(additionalCount) weitere Indikatoren",
            "\(additionalCount) autres indicateurs",
            "\(additionalCount) indicadores a mais"
        )
    }

    private func headlineHealthStatCard(_ item: HomeHealthStatItemViewModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            hiddenAccessibilityMarker(text: item.label, identifier: "home.health.preview.label")
            if let badge = item.badge, !badge.isEmpty {
                hiddenAccessibilityMarker(text: badge, identifier: "home.health.preview.badge")
            }

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
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColorRoles.surfaceInteractive)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
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
