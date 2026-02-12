import Foundation
import SwiftUI
import UIKit

/// Small shared pipeline for downsampling + caching.
/// Keeps view code minimal and ensures consistent behavior across screens.
enum ImagePipeline {
    private struct SendableCGImage: @unchecked Sendable {
        let cgImage: CGImage
    }

    /// Loads a downsampled image for UI display.
    /// Order: memory cache -> disk cache -> downsample -> store in caches.
    static func downsampledImage(
        imageData: Data,
        cacheKey: String,
        targetSize: CGSize,
        scale: CGFloat
    ) async -> UIImage? {
        if let cached = await MainActor.run(body: { ImageCache.shared.image(forKey: cacheKey) }) {
            return cached
        }

        if let diskData = await DiskImageCache.shared.data(forKey: cacheKey),
           let diskImage = UIImage(data: diskData) {
            await MainActor.run {
                ImageCache.shared.setImage(diskImage, forKey: cacheKey)
            }
            return diskImage
        }

        let sourceData = imageData
        let sourceSize = targetSize
        let sourceScale = scale
        let task: Task<SendableCGImage?, Never> = Task.detached(priority: .userInitiated) {
            guard let cg = ImageDownsampler.downsampleCGImage(
                imageData: sourceData,
                to: sourceSize,
                scale: sourceScale
            ) else { return nil }
            return SendableCGImage(cgImage: cg)
        }
        let generated = await task.value

        guard let generated else { return nil }

        let image = UIImage(cgImage: generated.cgImage)
        await MainActor.run {
            ImageCache.shared.setImage(image, forKey: cacheKey)
        }

        if let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData() {
            await DiskImageCache.shared.setData(data, forKey: cacheKey)
        }
        return image
    }
}
