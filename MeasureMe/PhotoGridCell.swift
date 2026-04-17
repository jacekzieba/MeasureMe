import SwiftUI
import SwiftData


struct PhotoGridCell: View {
    private static var revealedPhotoIDs: Set<String> = []

    let photo: PhotoEntry
    let isSelected: Bool
    let isSelecting: Bool
    var size: CGFloat = 110
    var showsMetadata: Bool = true
    var revealIndex: Int = 0
    @State private var isVisible = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    private var photoID: String { String(describing: photo.persistentModelID) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            photoImage
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color(hex: "#FCA311") : Color.clear, lineWidth: 3)
                }
                .scaleEffect(isSelected ? 0.95 : 1.0)

            if showsMetadata {
                PhotoGridMetadataOverlay(photo: photo)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if isSelecting {
                selectionIndicator
            }
        }
        .opacity(isVisible ? 1 : 0.0)
        .offset(y: isVisible ? 0 : 8)
        .scaleEffect(isVisible ? 1 : 0.985)
        .onAppear {
            let hasStoredThumbnail = PhotoUtilities.matchesGridThumbnailSpec(photo.thumbnailData)
            PhotoThumbnailTelemetry.recordPhotosTileAppearance(
                photoID: photoID,
                hasStoredThumbnail: hasStoredThumbnail
            )
            let isUITestMode = UITestArgument.isPresent(.mode)
            if !hasStoredThumbnail && !isUITestMode {
                Task {
                    await PhotoThumbnailBackfillService.shared.enqueueIfNeeded(
                        photoID: photo.persistentModelID,
                        originalImageData: photo.imageData,
                        existingThumbnailData: photo.thumbnailData,
                        modelContainer: modelContext.container,
                        source: "photos_grid"
                    )
                }
            }

            guard shouldAnimateReveal else {
                isVisible = true
                Self.revealedPhotoIDs.insert(photoID)
                return
            }
            guard !isVisible else { return }
            if Self.revealedPhotoIDs.contains(photoID) {
                isVisible = true
                return
            }
            let bucket = revealIndex % 12
            let delay = Double(bucket) * 0.012
            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                withAnimation(AppMotion.sectionEnter) {
                    isVisible = true
                }
                Self.revealedPhotoIDs.insert(photoID)
            }
        }
    }

    private var shouldAnimateReveal: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }
}


private extension PhotoGridCell {

    var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color(hex: "#FCA311") : Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .scaleEffect(isSelected ? 1.1 : 1.0)
    }
    
    
}

private extension PhotoGridCell {

    var photoImage: some View {
        DownsampledImageView(
            imageData: photo.preferredGridImageData,
            targetSize: CGSize(width: size, height: size),
            contentMode: .fill,
            cornerRadius: 12,
            showsProgress: false,
            cacheID: String(describing: photo.id)
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PhotoGridMetadataOverlay: View {
    let photo: PhotoEntry

    private var dateText: String {
        photo.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var poseText: String? {
        PhotoTag.primaryPose(in: photo.tags)?.shortLabel
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(dateText)
                .font(AppTypography.microEmphasis)
                .monospacedDigit()

            if let poseText {
                Text(poseText)
                    .font(AppTypography.microEmphasis)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.68), Color.black.opacity(0.36)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .accessibilityHidden(true)
    }
}
