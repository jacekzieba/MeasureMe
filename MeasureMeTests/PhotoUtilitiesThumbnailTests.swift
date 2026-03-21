import XCTest
import UIKit
@testable import MeasureMe

final class PhotoUtilitiesThumbnailTests: XCTestCase {

    func testThumbnailUsesAspectFillCropInsteadOfStretching() throws {
        let sourceSize = CGSize(width: 400, height: 200)
        let image = UIGraphicsImageRenderer(size: sourceSize).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            UIColor.green.setFill()
            context.fill(CGRect(x: 100, y: 0, width: 200, height: 200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 300, y: 0, width: 100, height: 200))
        }

        let thumbnail = PhotoUtilities.thumbnail(from: image, size: CGSize(width: 100, height: 100))

        XCTAssertEqual(Int(thumbnail.size.width), 100)
        XCTAssertEqual(Int(thumbnail.size.height), 100)

        let leftEdge = try XCTUnwrap(pixelColor(in: thumbnail, x: 5, y: 50))
        let rightEdge = try XCTUnwrap(pixelColor(in: thumbnail, x: 95, y: 50))

        XCTAssertTrue(leftEdge.isClose(to: .green, tolerance: 0.05))
        XCTAssertTrue(rightEdge.isClose(to: .green, tolerance: 0.05))
    }

    func testMatchesGridThumbnailSpecRecognizesCurrentCanvas() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: PhotoUtilities.gridThumbnailSize, format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: PhotoUtilities.gridThumbnailSize))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))

        XCTAssertTrue(PhotoUtilities.matchesGridThumbnailSpec(data))
    }

    func testMatchesGridThumbnailSpecRejectsLegacyCanvas() throws {
        let legacySize = CGSize(width: 220, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: legacySize, format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: legacySize))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))

        XCTAssertFalse(PhotoUtilities.matchesGridThumbnailSpec(data))
    }

    private func pixelColor(in image: UIImage, x: Int, y: Int) -> UIColor? {
        guard let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return nil
        }

        let ptr = CFDataGetBytePtr(data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
        guard let ptr, offset + 3 < CFDataGetLength(data) else { return nil }

        let red = CGFloat(ptr[offset]) / 255
        let green = CGFloat(ptr[offset + 1]) / 255
        let blue = CGFloat(ptr[offset + 2]) / 255
        let alpha = CGFloat(ptr[offset + 3]) / 255

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension UIColor {
    func isClose(to other: UIColor, tolerance: CGFloat) -> Bool {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return false
        }

        return abs(r1 - r2) <= tolerance
            && abs(g1 - g2) <= tolerance
            && abs(b1 - b2) <= tolerance
            && abs(a1 - a2) <= tolerance
    }
}
