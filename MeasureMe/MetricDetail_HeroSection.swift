import SwiftUI
import SwiftData

// MARK: - Hero Section

private extension MetricDetailView {

    var heroSection: some View {
        VStack(spacing: 18) {
            metricHeroSummary

            Divider()
                .overlay(Color.white.opacity(0.08))

            chartSectionContent
        }
        .padding(18)
        .background(heroCardBackground)
        .padding(.vertical, 4)
    }

    var heroCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)

        return shape
            .fill(
                ClaudeLightStyle.directionalGradient(
                    colors: colorScheme == .dark
                        ? [
                            AppColorRoles.surfaceChrome.opacity(0.98),
                            AppColorRoles.surfacePrimary.opacity(0.92)
                        ]
                        : [
                            Color(hex: "#FAFAF7"),
                            Color(hex: "#EFF1EB")
                        ],
                    colorScheme: colorScheme,
                    lightColor: AppColorRoles.surfacePrimary
                )
            )
            .overlay(
                shape.fill(
                    ClaudeLightStyle.directionalGradient(
                        colors: [
                            measurementsTheme.strongTint.opacity(colorScheme == .dark ? 0.18 : 0.08),
                            .clear
                        ],
                        colorScheme: colorScheme,
                        lightColor: measurementsTheme.strongTint.opacity(0.04)
                    )
                )
            )
            .overlay(
                shape.stroke(
                    ClaudeLightStyle.directionalGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.88),
                            AppColorRoles.borderStrong.opacity(colorScheme == .dark ? 0.72 : 0.54)
                        ],
                        colorScheme: colorScheme,
                        lightColor: AppColorRoles.borderSubtle
                    ),
                    lineWidth: 1
                )
            )
    }

    var metricHeroSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        kind.iconView(size: 18, tint: measurementsTheme.accent)
                        Text(AppLocalization.string("Current value"))
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Text(valueString(latestSampleValue ?? 0))
                        .font(AppTypography.dataCompact)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.22)
                        .allowsTightening(true)

                    if let latestSample {
                        Text(latestSample.date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                if let currentValueTrendSummary {
                    Label(currentValueTrendSummary.text, systemImage: currentValueTrendSummary.icon)
                        .font(AppTypography.badge)
                        .foregroundStyle(currentValueTrendSummary.color)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(currentValueTrendSummary.color.opacity(0.14))
                        )
                }
            }
            if relatedTag != nil {
                metricHeroPhotoProof
            }
        }
    }

    @ViewBuilder
    var metricHeroPhotoProof: some View {
        if relatedPhotos.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.headline)
                    .foregroundStyle(measurementsTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Photo Progress"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string("No related photos yet."))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                Spacer()
            }
            .padding(AppSpacing.smmd)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColorRoles.surfaceInteractive)
            )
        } else {
            Button {
                if let tag = relatedTag {
                    photosFilterTag = tag.rawValue
                    router.selectedTab = .photos
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("Photo Progress"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(heroDeltaCaption)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        ForEach(visiblePhotos, id: \.persistentModelID) { photo in
                            DownsampledImageView(
                                imageData: photo.thumbnailOrImageData,
                                targetSize: CGSize(width: 42, height: 42),
                                contentMode: .fill,
                                cornerRadius: 12,
                                showsProgress: false,
                                cacheID: String(describing: photo.id)
                            )
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
                .padding(AppSpacing.smmd)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColorRoles.surfaceInteractive)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("View more photos"))
            .accessibilityHint(AppLocalization.string("accessibility.photos.filtered"))
        }
    }
}
