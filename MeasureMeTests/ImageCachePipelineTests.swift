import XCTest
import UIKit
@testable import MeasureMe

@MainActor
final class ImageCachePipelineTests: XCTestCase {
    func testMemoryCacheClearRemovesCachedImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let key = "image-cache-test"

        ImageCache.shared.setImage(image, forKey: key)
        XCTAssertNotNil(ImageCache.shared.image(forKey: key))

        ImageCache.shared.removeAll()
        XCTAssertNil(ImageCache.shared.image(forKey: key))
    }

    func testDiskCacheRemoveAllClearsStoredData() async throws {
        let key = "disk-cache-test"
        let data = Data([0xAA, 0xBB, 0xCC])

        await DiskImageCache.shared.setData(data, forKey: key)
        let cachedBefore = await DiskImageCache.shared.data(forKey: key)
        XCTAssertEqual(cachedBefore, data)

        try await DiskImageCache.shared.removeAll()
        let cachedAfter = await DiskImageCache.shared.data(forKey: key)
        XCTAssertNil(cachedAfter)
    }
}
