import SwiftData
import SwiftUI

// MARK: - Photo Entry

@Model
final class PhotoEntry {
    @Attribute(.externalStorage)
    var imageData: Data

    var date: Date
    var tags: [PhotoTag]
    var linkedMetrics: [MetricValueSnapshot]

    init(
        imageData: Data,
        date: Date = .now,
        tags: [PhotoTag],
        linkedMetrics: [MetricValueSnapshot] = []
    ) {
        self.imageData = imageData
        self.date = date
        self.tags = tags
        self.linkedMetrics = linkedMetrics
    }
}
