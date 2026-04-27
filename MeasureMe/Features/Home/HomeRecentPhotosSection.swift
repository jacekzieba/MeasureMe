import SwiftUI
import SwiftData
import UIKit

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
    @ObservedObject private var photoPrivacyGate = PhotoPrivacyGate.shared
    @AppSetting(\.privacy.requireBiometricForPhotos) private var requireBiometricForPhotos: Bool = false

    let snapshot: HomeRecentPhotosSnapshot
    let tiles: [HomeRecentPhotoTileViewModel]
    let onOpenPhotos: () -> Void
    let onOpenPhoto: (PhotoEntry) -> Void
    let onCompare: () -> Void

    private let theme = FeatureTheme.photos
    private let photoSpacing: CGFloat = 8
    private let photoCornerRadius: CGFloat = 16
    private let photoHorizontalPadding: CGFloat = 12
    private let photoTopPadding: CGFloat = 12

    private var canDisplayPhotos: Bool {
        photoPrivacyGate.canDisplayPhotos(requireBiometric: requireBiometricForPhotos)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(String(snapshot.tileCount))
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("home.recentPhotos.tileCount")
                .frame(width: 1, height: 1)
                .clipped()

            progressCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityIdentifier("home.module.recentPhotos")
                .allowsHitTesting(false)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            photoPrivacyGate.lock()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            photoPrivacyGate.lock()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AppLocalization.string("Progress photos"))
                .font(AppTypography.eyebrow)
                .foregroundStyle(AppColorRoles.textSecondary)
                .textCase(.uppercase)
                .accessibilityIdentifier("home.module.recentPhotos.title")

            Spacer(minLength: 8)

            Button(action: onOpenPhotos) {
                Text(AppLocalization.string("View all"))
                    .font(AppTypography.sectionAction)
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("accessibility.open.photos"))
        }
    }

    private var progressCard: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: theme.softTint,
            contentPadding: 0
        ) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    let paneWidth = max((proxy.size.width - (photoHorizontalPadding * 2) - photoSpacing) / 2, 0)
                    HStack(spacing: photoSpacing) {
                        comparisonPane(tile: comparisonOlderTile, index: 1, width: paneWidth)
                        comparisonPane(tile: comparisonLatestTile, index: 0, width: paneWidth)
                    }
                    .padding(.horizontal, photoHorizontalPadding)
                    .padding(.top, photoTopPadding)
                    .blur(radius: canDisplayPhotos ? 0 : 10)
                    .allowsHitTesting(canDisplayPhotos)
                    .overlay {
                        if !canDisplayPhotos {
                            Button {
                                Task { await photoPrivacyGate.unlock() }
                            } label: {
                                Label(AppLocalization.string("Unlock photos"), systemImage: "faceid")
                                    .font(AppTypography.captionEmphasis)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.52), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.recentPhotos.unlock")
                        }
                    }
                }
                .frame(height: 162)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(progressGapTitle)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(progressDateRangeText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 8)

                    Button(action: onCompare) {
                        Label(AppLocalization.string("Compare"), systemImage: "rectangle.split.2x1")
                            .font(AppTypography.buttonLabel)
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .stroke(theme.accent, lineWidth: 1.4)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!snapshot.hasEnoughSavedPhotosForCompare)
                    .opacity(snapshot.hasEnoughSavedPhotosForCompare ? 1 : 0.55)
                    .accessibilityIdentifier("home.recentPhotos.compare.button")
                }
                .padding(16)
            }
        }
    }

    private var comparisonLatestTile: HomeRecentPhotoTileViewModel? {
        tiles.first
    }

    private var comparisonOlderTile: HomeRecentPhotoTileViewModel? {
        tiles.dropFirst().first
    }

    private var progressGapTitle: String {
        guard let latestDate = tileDate(comparisonLatestTile),
              let olderDate = tileDate(comparisonOlderTile) else {
            return AppLocalization.string("home.photos.first.title")
        }
        let days = max(Calendar.current.dateComponents([.day], from: olderDate, to: latestDate).day ?? 0, 0)
        return FlowLocalization.app(
            "\(days) days apart",
            "\(days) dni roznicy",
            "\(days) dias de diferencia",
            "\(days) Tage Abstand",
            "\(days) jours d'ecart",
            "\(days) dias de intervalo"
        )
    }

    private var progressDateRangeText: String {
        guard let latestDate = tileDate(comparisonLatestTile) else {
            return snapshot.subtitle
        }
        let latest = latestDate.formatted(.dateTime.month(.abbreviated).day().year())
        guard let olderDate = tileDate(comparisonOlderTile) else {
            return latest
        }
        let older = olderDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(older) -> \(latest)"
    }

    @ViewBuilder
    private func comparisonPane(tile: HomeRecentPhotoTileViewModel?, index: Int, width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let tile {
                tilePreview(tile, index: index, width: width)
            } else {
                Rectangle()
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay {
                        Image(systemName: "photo")
                            .font(AppTypography.iconLarge)
                            .foregroundStyle(AppColorRoles.textTertiary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
            }

            Text(tileMonthYear(tile))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.32), in: Capsule())
                .padding(.bottom, 10)
        }
        .frame(width: width, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func tilePreview(_ tile: HomeRecentPhotoTileViewModel, index: Int, width: CGFloat) -> some View {
        switch tile {
        case .persisted(let photo):
            Button {
                onOpenPhoto(photo)
            } label: {
                PhotoGridThumb(
                    photo: photo,
                    size: width,
                    cacheID: String(describing: photo.id)
                )
                .frame(width: width, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.recentPhotos.item.\(index)")
        case .pending(let pending):
            PendingPhotoGridCell(
                thumbnailData: pending.thumbnailData,
                progress: pending.progress,
                status: pending.status,
                targetSize: CGSize(width: width, height: 150),
                cornerRadius: photoCornerRadius,
                cacheID: pending.id.uuidString,
                showsStatusLabel: false,
                accessibilityIdentifier: "home.recentPhotos.item.\(index)"
            )
            .frame(width: width, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
        }
    }

    private func tileMonthYear(_ tile: HomeRecentPhotoTileViewModel?) -> String {
        guard let date = tileDate(tile) else { return AppLocalization.string("No photo") }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    private func tileDate(_ tile: HomeRecentPhotoTileViewModel?) -> Date? {
        guard let tile else { return nil }
        switch tile {
        case .persisted(let photo):
            return photo.date
        case .pending(let item):
            return item.date
        }
    }
}

struct HomeRecentPhotosEmptyCard: View {
    let onOpenPhotos: () -> Void

    private let theme = FeatureTheme.photos

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(AppLocalization.string("Progress photos"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .textCase(.uppercase)
                    .accessibilityIdentifier("home.module.recentPhotos.title")

                Spacer(minLength: 8)

                Button(action: onOpenPhotos) {
                    Text(AppLocalization.string("View all"))
                        .font(AppTypography.sectionAction)
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }

            Button(action: onOpenPhotos) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppLocalization.string("home.photos.empty.title"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    Text(AppLocalization.string("Take one full-body photo. In 4 weeks, the comparison will show changes your eye missed."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppLocalization.string("Take your first photo"))
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(theme.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    AppGlassBackground(
                        depth: .elevated,
                        cornerRadius: 24,
                        tint: theme.softTint
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityIdentifier("home.module.recentPhotos")
                .allowsHitTesting(false)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }
}
