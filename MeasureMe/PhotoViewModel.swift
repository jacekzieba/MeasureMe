import SwiftUI
import SwiftData

@Observable @MainActor final class PhotoViewModel {
    var allPhotos: [PhotoEntry] = []

    var mostRecentPhotoThumbnailData: Data? {
        allPhotos.first?.thumbnailOrImageData
    }
}
