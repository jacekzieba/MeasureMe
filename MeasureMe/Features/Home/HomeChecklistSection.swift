import SwiftUI

struct HomeChecklistItemViewModel: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
}

struct HomeChecklistSnapshot {
    let activeCount: Int
    let isCollapsed: Bool
    let showMoreVisible: Bool
    let remainingCount: Int
    let statusText: String?
}

struct HomeChecklistCard: View {
    let snapshot: HomeChecklistSnapshot
    let items: [HomeChecklistItemViewModel]
    let iconSurface: Color
    let rowFill: Color
    let rowStroke: Color
    let onHide: () -> Void
    let onToggleCollapse: () -> Void
    let onItemTap: (String) -> Void
    let onShowMore: () -> Void

    private let theme: FeatureTheme = .home

    var body: some View {
        HomeWidgetCard(
            tint: theme.softTint,
            depth: .base,
            contentPadding: 14,
            accessibilityIdentifier: "home.module.setupChecklist"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                header

                if snapshot.isCollapsed {
                    Text(AppLocalization.string("Checklist collapsed. Open menu to expand."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                } else {
                    ForEach(items) { item in
                        Button {
                            onItemTap(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.appAccent)
                                    .frame(width: 28, height: 28)
                                    .background(iconSurface)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(AppTypography.captionEmphasis)
                                        .foregroundStyle(AppColorRoles.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.detail)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(AppColorRoles.textSecondary)
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.85)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppColorRoles.textTertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(rowFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(rowStroke, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.checklist.item.\(item.id)")
                    }

                    if snapshot.showMoreVisible {
                        Button(action: onShowMore) {
                            Text(AppLocalization.plural("Show %d more", snapshot.remainingCount))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(Color.appAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.checklist.showMore")
                    }

                    Text("\(items.count)")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("home.checklist.visibleCount")
                        .frame(width: 1, height: 1)
                        .clipped()

                    Text(items.map(\.id).joined(separator: ","))
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("home.checklist.visibleIDs")
                        .frame(width: 1, height: 1)
                        .clipped()
                }

                if let statusText = snapshot.statusText {
                    Text(statusText)
                        .font(AppTypography.micro)
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("home.module.setup.eyebrow"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appAccent)
                Text(AppLocalization.string("Finish setup"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(AppLocalization.plural("home.module.setup.subtitle", snapshot.activeCount))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            Spacer()

            Text(AppLocalization.string("home.module.setup.pill", snapshot.activeCount))
                .font(AppTypography.microEmphasis)
                .foregroundStyle(Color.appAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                )

            Menu {
                Button(AppLocalization.string("Hide checklist"), action: onHide)
                Button(
                    snapshot.isCollapsed
                    ? AppLocalization.string("Expand checklist")
                    : AppLocalization.string("Collapse checklist"),
                    action: onToggleCollapse
                )
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColorRoles.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
    }
}
