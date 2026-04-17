import SwiftUI
import SwiftData

struct PhotoComparePairSuggestion {
    let older: PhotoEntry
    let newer: PhotoEntry

    var dayGap: Int {
        max(Calendar.current.dateComponents([.day], from: older.date, to: newer.date).day ?? 0, 0)
    }
}

enum CompareChooserSlot {
    case older
    case newer
}

enum PhotoCompareHeroState {
    case onboarding
    case manualOnly
    case pair(PhotoComparePairSuggestion)
}

func suggestedPhotoComparePair(from photos: [PhotoEntry]) -> PhotoComparePairSuggestion? {
    guard photos.count >= 2 else { return nil }
    let sorted = photos.sorted { $0.date > $1.date }
    guard let newest = sorted.first else { return nil }
    guard let older = sorted.dropFirst().first(where: { candidate in
        let days = Calendar.current.dateComponents([.day], from: candidate.date, to: newest.date).day ?? 0
        return days >= 7
    }) else {
        return nil
    }
    return PhotoComparePairSuggestion(older: older, newer: newest)
}

struct PhotoCompareHeroCard: View {
    private let photosTheme = FeatureTheme.photos

    let state: PhotoCompareHeroState
    let isPremium: Bool
    let onOpenChooser: () -> Void
    let onChooseOlderPhoto: () -> Void
    let onChooseNewerPhoto: () -> Void
    let onCompare: () -> Void
    let onAddPhoto: () -> Void

    var body: some View {
        AppGlassCard(
            depth: .floating,
            cornerRadius: 24,
            tint: photosTheme.strongTint,
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("Your Progress"))
                            .font(AppTypography.displaySection)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }

                    Spacer(minLength: 12)
                }

                switch state {
                case .pair(let pair):
                    HStack(spacing: 10) {
                        compareSlot(
                            photo: pair.older,
                            title: comparisonSlotTitle(for: pair.older),
                            action: onChooseOlderPhoto
                        )
                        compareSlot(
                            photo: pair.newer,
                            title: comparisonSlotTitle(for: pair.newer),
                            action: onChooseNewerPhoto
                        )
                    }

                    HStack(spacing: 10) {
                        Label(AppLocalization.plural("compare.days.apart", pair.dayGap), systemImage: "clock")
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColorRoles.textSecondary)

                        Spacer()

                        Button {
                            onOpenChooser()
                        } label: {
                            Text(AppLocalization.string("Choose Photos"))
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.sectionAction)
                        .foregroundStyle(photosTheme.accent)
                    }

                    Button {
                        onCompare()
                    } label: {
                        Label(AppLocalization.string("Compare"), systemImage: "arrow.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                case .manualOnly:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalization.string("Too early for an automatic comparison. Choose photos manually."))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)

                        Button {
                            onOpenChooser()
                        } label: {
                            Label(AppLocalization.string("Choose Photos"), systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppAccentButtonStyle())
                    }
                case .onboarding:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalization.string("Take your first photo. In a few weeks, you’ll see what the mirror can’t show you."))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)

                        Button {
                            onAddPhoto()
                        } label: {
                            Label(AppLocalization.string("Take your first photo"), systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppAccentButtonStyle())
                    }
                }
            }
        }
    }

    private func compareSlot(photo: PhotoEntry, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack {
                    Text(title)
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(AppColorRoles.textTertiary)
                    Spacer()
                }

                PhotoGridThumb(
                    photo: photo,
                    size: 112,
                    cacheID: String(describing: photo.persistentModelID)
                )
                .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Text(photo.date.formatted(date: .abbreviated, time: .omitted))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
            )
        }
        .buttonStyle(.plain)
    }

    private func comparisonSlotTitle(for photo: PhotoEntry) -> String {
        let dateText = photo.date.formatted(.dateTime.month(.abbreviated).day())
        let days = Calendar.current.dateComponents([.day], from: photo.date, to: AppClock.now).day ?? 0
        if days >= 14 {
            let weeks = max(days / 7, 1)
            return AppLocalization.string("%d weeks ago", weeks) + " · " + dateText
        }
        if Calendar.current.isDateInToday(photo.date) {
            return AppLocalization.string("Today") + " · " + dateText
        }
        return dateText
    }
}

struct PhotoSessionSummaryCard: View {
    private let photosTheme = FeatureTheme.photos

    let photo: PhotoEntry
    let previousPhoto: PhotoEntry?

    private var gapText: String {
        guard let previousPhoto else { return AppLocalization.string("Current value") }
        let days = max(Calendar.current.dateComponents([.day], from: previousPhoto.date, to: photo.date).day ?? 0, 0)
        return AppLocalization.plural("compare.days.apart", days)
    }

    var body: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 22,
            tint: photosTheme.softTint,
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("Details"))
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(photosTheme.accent)

                HStack(spacing: 12) {
                    sessionStat(title: AppLocalization.string("Date"), value: photo.date.formatted(date: .abbreviated, time: .shortened))
                    sessionStat(title: AppLocalization.string("Progress"), value: gapText)
                }

                if !photo.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photo.tags, id: \.self) { tag in
                                TagChip(tag: tag)
                            }
                        }
                    }
                }

                if !photo.linkedMetrics.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(photo.linkedMetrics) { snapshot in
                            MetricSnapshotRow(snapshot: snapshot, compact: true)
                        }
                    }
                }
            }
        }
    }

    private func sessionStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.microEmphasis)
                .foregroundStyle(AppColorRoles.textTertiary)
            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
        )
    }
}
