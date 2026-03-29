import SwiftUI
import SwiftData

enum HomeRecentPhotoTileViewModel: Identifiable {
    case persisted(PhotoEntry)
    case pending(PendingPhotoSaveItem)

    var id: String {
        switch self {
        case .persisted(let photo):
            return "persisted_\(String(describing: photo.persistentModelID))"
        case .pending(let item):
            return "pending_\(item.id.uuidString)"
        }
    }
}

struct HomeRecentPhotosSnapshot {
    let subtitle: String
    let contextPrimary: String
    let contextSecondary: String
    let insightTitle: String
    let insightDetail: String
    let insightNote: String?
    let hasEnoughSavedPhotosForCompare: Bool
    let tileCount: Int
}

struct HomeRecentPhotosCard: View {
    let snapshot: HomeRecentPhotosSnapshot
    let tiles: [HomeRecentPhotoTileViewModel]
    let onOpenPhotos: () -> Void
    let onOpenPhoto: (PhotoEntry) -> Void
    let onCompare: () -> Void

    private let theme = FeatureTheme.photos

    var body: some View {
        HomeWidgetCard(
            tint: theme.softTint,
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.recentPhotos"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                header

                Text(String(snapshot.tileCount))
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("home.recentPhotos.tileCount")
                    .frame(width: 1, height: 1)
                    .clipped()

                if !tiles.isEmpty {
                    GeometryReader { proxy in
                        let spacing: CGFloat = 8
                        let side = max(min((proxy.size.width - (spacing * 2)) / 3, 112), 0)
                        HStack(spacing: spacing) {
                            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                                tileView(tile, index: index, side: side)
                            }

                            ForEach(0..<max(0, 3 - tiles.count), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColorRoles.surfaceInteractive)
                                    .frame(width: side, height: side)
                                    .hidden()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        infoPill(text: snapshot.contextPrimary, tint: theme.accent)
                        infoPill(text: snapshot.contextSecondary, tint: AppColorRoles.textSecondary)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        infoPill(text: snapshot.contextPrimary, tint: theme.accent)
                        infoPill(text: snapshot.contextSecondary, tint: AppColorRoles.textSecondary)
                    }
                }

                Spacer(minLength: 2)

                Button(action: onCompare) {
                    insightCard
                }
                .buttonStyle(.plain)
                .disabled(!snapshot.hasEnoughSavedPhotosForCompare)
                .accessibilityIdentifier("home.recentPhotos.compare.button")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("home.photos.latestsession"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(theme.accent)
                    .textCase(.uppercase)

                Text(AppLocalization.string("Recent photos"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(snapshot.subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onOpenPhotos) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(theme.pillFill)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("accessibility.open.photos"))
        }
        .accessibilityIdentifier("home.module.recentPhotos.title")
    }

    @ViewBuilder
    private func tileView(_ tile: HomeRecentPhotoTileViewModel, index: Int, side: CGFloat) -> some View {
        switch tile {
        case .persisted(let photo):
            Button {
                onOpenPhoto(photo)
            } label: {
                PhotoGridThumb(
                    photo: photo,
                    size: side,
                    cacheID: String(describing: photo.id)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.recentPhotos.item.\(index)")
        case .pending(let pending):
            PendingPhotoGridCell(
                thumbnailData: pending.thumbnailData,
                progress: pending.progress,
                status: pending.status,
                targetSize: CGSize(width: side, height: side),
                cornerRadius: 12,
                cacheID: pending.id.uuidString,
                showsStatusLabel: false,
                accessibilityIdentifier: "home.recentPhotos.item.\(index)"
            )
            .frame(width: side, height: side)
        }
    }

    private func infoPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTypography.microEmphasis)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
            )
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("home.photos.latestsession"))
                .font(AppTypography.eyebrow)
                .foregroundStyle(theme.accent)
                .textCase(.uppercase)

            Text(snapshot.insightTitle)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)

            Text(snapshot.insightDetail)
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = snapshot.insightNote {
                Text(note)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.pillFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        )
    }
}

struct HomeRecentPhotosEmptyCard: View {
    let onOpenPhotos: () -> Void

    private let theme = FeatureTheme.photos

    var body: some View {
        HomeWidgetCard(
            tint: theme.softTint,
            depth: .elevated,
            contentPadding: 16,
            accessibilityIdentifier: "home.module.recentPhotos"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("home.photos.latestsession"))
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(theme.accent)
                        .textCase(.uppercase)

                    Text(AppLocalization.string("Recent photos"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string("home.photos.empty.subtitle"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                Button(action: onOpenPhotos) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLocalization.string("home.empty.eyebrow"))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(theme.accent)
                            .textCase(.uppercase)

                        Text(AppLocalization.string("home.photos.empty.title"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)

                        Text(AppLocalization.string("home.photos.empty.detail"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(AppLocalization.string("Open Photos"))
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
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }
}
