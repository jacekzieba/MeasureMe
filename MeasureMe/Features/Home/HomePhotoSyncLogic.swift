import SwiftUI
import SwiftData

struct PhotoGridThumb: View {
    let photo: PhotoEntry
    let size: CGFloat
    let cacheID: String
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        DownsampledImageView(
            imageData: photo.preferredGridImageData,
            targetSize: CGSize(width: size, height: size),
            contentMode: .fill,
            cornerRadius: 12,
            showsProgress: false,
            cacheID: cacheID
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            guard photo.thumbnailData == nil else { return }
            guard !ProcessInfo.processInfo.arguments.contains("-uiTestMode") else { return }
            Task {
                await PhotoThumbnailBackfillService.shared.enqueueIfNeeded(
                    photoID: photo.persistentModelID,
                    originalImageData: photo.imageData,
                    existingThumbnailData: photo.thumbnailData,
                    modelContainer: modelContext.container,
                    source: "home_last_photos"
                )
            }
        }
    }
}
