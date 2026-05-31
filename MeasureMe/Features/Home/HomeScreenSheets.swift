import SwiftUI

// MARK: - Goal Status Legend Sheet

struct GoalStatusLegendSheet: View {
    let currentStatus: HomeView.GoalStatusLevel
    let currentStatusColor: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("home.goalstatus.legend.title"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(AppLocalization.string("home.goalstatus.legend.subtitle"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsCard(tint: AppColorRoles.surfacePrimary) {
                        goalLegendRow(
                            color: AppColorRoles.stateSuccess,
                            titleKey: "home.goalstatus.legend.ontrack.title",
                            descriptionKey: "home.goalstatus.legend.ontrack.description"
                        )
                        SettingsRowDivider()
                        goalLegendRow(
                            color: AppColorRoles.stateWarning,
                            titleKey: "home.goalstatus.legend.slightlyoff.title",
                            descriptionKey: "home.goalstatus.legend.slightlyoff.description"
                        )
                        SettingsRowDivider()
                        goalLegendRow(
                            color: AppColorRoles.stateError,
                            titleKey: "home.goalstatus.legend.needsattention.title",
                            descriptionKey: "home.goalstatus.legend.needsattention.description"
                        )
                    }

                    SettingsCard(tint: currentStatusColor.opacity(0.18)) {
                        Text(AppLocalization.string("home.goalstatus.legend.current.title"))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(AppColorRoles.textTertiary)

                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(currentStatusColor)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentStatusTitle)
                                    .font(AppTypography.bodyStrong)
                                    .foregroundStyle(AppColorRoles.textPrimary)

                                Text(currentStatusDescription)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
            }
            .background(AppColorRoles.surfaceCanvas.ignoresSafeArea())
            .navigationTitle(AppLocalization.string("home.goalstatus.legend.navtitle"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentStatusTitle: String {
        switch currentStatus {
        case .onTrack:
            return AppLocalization.string("home.goalstatus.legend.current.ontrack")
        case .slightlyOff:
            return AppLocalization.string("home.goalstatus.legend.current.slightlyoff")
        case .needsAttention:
            return AppLocalization.string("home.goalstatus.legend.current.needsattention")
        case .noGoals:
            return AppLocalization.string("home.goalstatus.legend.current.nogoals")
        }
    }

    private var currentStatusDescription: String {
        switch currentStatus {
        case .onTrack:
            return AppLocalization.string("home.goalstatus.legend.ontrack.description")
        case .slightlyOff:
            return AppLocalization.string("home.goalstatus.legend.slightlyoff.description")
        case .needsAttention:
            return AppLocalization.string("home.goalstatus.legend.needsattention.description")
        case .noGoals:
            return AppLocalization.string("home.goalstatus.legend.nogoals.description")
        }
    }

    private func goalLegendRow(color: Color, titleKey: String, descriptionKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(titleKey))
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string(descriptionKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Home Last Photos Grid

struct HomeLastPhotosGrid: View {
    let tiles: [HomePhotoTile]
    let onPersistedTap: (PhotoEntry) -> Void

    private let columns = 3
    private let spacing: CGFloat = 8
    private let minimumSide: CGFloat = 86

    var body: some View {
        GeometryReader { geometry in
            let side = tileSide(for: geometry.size.width)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(tiles) { tile in
                    switch tile {
                    case .persisted(let photo):
                        Button {
                            onPersistedTap(photo)
                        } label: {
                            PhotoGridThumb(
                                photo: photo,
                                size: side,
                                cacheID: String(describing: photo.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.string("accessibility.open.photo.details"))
                        .accessibilityValue(photo.date.formatted(date: .abbreviated, time: .omitted))
                    case .pending(let pending):
                        PendingPhotoGridCell(
                            thumbnailData: pending.thumbnailData,
                            progress: pending.progress,
                            status: pending.status,
                            targetSize: CGSize(width: side, height: side),
                            cornerRadius: 12,
                            cacheID: pending.id.uuidString,
                            showsStatusLabel: false,
                            accessibilityIdentifier: "home.lastPhotos.pending.item"
                        )
                        .frame(width: side, height: side)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(tiles.count) / Double(columns))))
        return CGFloat(rows) * minimumSide + CGFloat(max(rows - 1, 0)) * spacing
    }

    private func tileSide(for width: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        guard width.isFinite, width > totalSpacing else { return minimumSide }
        let raw = (width - totalSpacing) / CGFloat(columns)
        guard raw.isFinite, raw > 0 else { return minimumSide }
        return max(floor(raw), minimumSide)
    }
}
