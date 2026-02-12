import Foundation
import ImageIO

enum ImageDownsampler {
    nonisolated static func downsampleCGImage(imageData: Data, to pointSize: CGSize, scale: CGFloat) -> CGImage? {
        autoreleasepool {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let source = CGImageSourceCreateWithData(imageData as CFData, options as CFDictionary) else {
                return nil
            }

            let maxDimensionInPixels = Int(max(pointSize.width, pointSize.height) * scale)
            guard maxDimensionInPixels > 0 else { return nil }

            let downsampleOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                downsampleOptions as CFDictionary
            ) else {
                return nil
            }

            return cgImage
        }
    }
}

