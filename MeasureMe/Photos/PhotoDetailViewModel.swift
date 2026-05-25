import SwiftUI
import SwiftData

@Observable @MainActor final class PhotoDetailViewModel {
    var allPhotos: [PhotoEntry] = []

    func previousPhoto(relativeTo photo: PhotoEntry) -> PhotoEntry? {
        allPhotos
            .filter { $0.persistentModelID != photo.persistentModelID && $0.date < photo.date }
            .sorted { $0.date > $1.date }
            .first
    }
}
