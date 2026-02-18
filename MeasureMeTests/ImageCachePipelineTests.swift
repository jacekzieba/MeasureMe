import XCTest
import UIKit
@testable import MeasureMe

@MainActor
final class ImageCachePipelineTests: XCTestCase {
    private func makeTestImage() -> UIImage {
        UIImage(systemName: "circle.fill") ?? UIImage()
    }

    override func setUp() {
        super.setUp()
        ImageCache.shared.countLimit = 50
    }

    func testMemoryCacheStoresAndReturnsImage() {
        let image = makeTestImage()
        let key = "image-cache-test"

        ImageCache.shared.setImage(image, forKey: key)
        XCTAssertNotNil(ImageCache.shared.image(forKey: key))
    }

    func testMemoryCacheLRUOrderUpdatesOnAccess() {
        let image = makeTestImage()
        let prefix = UUID().uuidString

        let k1 = "\(prefix)-k1"
        let k2 = "\(prefix)-k2"
        let k3 = "\(prefix)-k3"

        ImageCache.shared.setImage(image, forKey: k1)
        ImageCache.shared.setImage(image, forKey: k2)
        ImageCache.shared.setImage(image, forKey: k3)

        _ = ImageCache.shared.image(forKey: k1)

        let leastRecentlyUsed = ImageCache.shared
            .getLeastRecentlyUsedKeys(count: 200)
            .filter { $0.hasPrefix(prefix) }
        XCTAssertEqual(leastRecentlyUsed, [k2, k3, k1])
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
