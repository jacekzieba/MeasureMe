import SwiftUI
import SwiftData


struct PhotoGridCell: View {
    private static var revealedPhotoIDs: Set<String> = []

    let photo: PhotoEntry
    let isSelected: Bool
    let isSelecting: Bool
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

            if isSelecting {
                selectionIndicator
            }
        }
        .opacity(isVisible ? 1 : 0.0)
        .offset(y: isVisible ? 0 : 8)
        .scaleEffect(isVisible ? 1 : 0.985)
        .onAppear {
            let hasStoredThumbnail = photo.thumbnailData != nil
            PhotoThumbnailTelemetry.recordPhotosTileAppearance(
                photoID: photoID,
                hasStoredThumbnail: hasStoredThumbnail
            )
            if !hasStoredThumbnail {
                Task(priority: .utility) {
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
            imageData: photo.thumbnailOrImageData,
            targetSize: CGSize(width: 110, height: 120),
            contentMode: .fill,
            cornerRadius: 12,
            showsProgress: false,
            cacheID: String(describing: photo.id)
        )
        .frame(width: 110, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
