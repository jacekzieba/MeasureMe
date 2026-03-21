import SwiftData
import SwiftUI

// MARK: - Photo Entry

@Model
final class PhotoEntry {
    @Attribute(.externalStorage)
    var imageData: Data

    var thumbnailData: Data?
    var date: Date
    var tags: [PhotoTag]
    var linkedMetrics: [MetricValueSnapshot]

    var thumbnailOrImageData: Data {
        thumbnailData ?? imageData
    }

    var preferredGridImageData: Data {
        if PhotoUtilities.matchesGridThumbnailSpec(thumbnailData) {
            return thumbnailData ?? imageData
        }
        return imageData
    }

    init(
        imageData: Data,
        thumbnailData: Data? = nil,
        date: Date = .now,
        tags: [PhotoTag],
        linkedMetrics: [MetricValueSnapshot] = []
    ) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.date = date
        self.tags = tags
        self.linkedMetrics = linkedMetrics
    }
}
