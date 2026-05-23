import SwiftUI
import SwiftData

@Observable @MainActor final class PhotoFilterViewModel {
    var availableTags: [PhotoTag] = []

    func updateAvailableTags(from photos: [PhotoEntry]) {
        var tags = Set<PhotoTag>()
        for photo in photos { tags.formUnion(photo.tags) }
        availableTags = tags.sorted { $0.title < $1.title }
    }
}
