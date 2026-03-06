import Foundation
import SwiftUI
import UIKit

/// Maly wspolny pipeline dla downsamplingu i cache.
/// Utrzymuje kod widokow prosty i zapewnia spojne zachowanie miedzy ekranami.
enum ImagePipeline {
    private struct SendableCGImage: @unchecked Sendable {
        let cgImage: CGImage
    }

    private actor InFlightDownsampleTasks {
        private var tasks: [String: Task<SendableCGImage?, Never>] = [:]

        func task(
            for key: String,
            create: @escaping @Sendable () -> Task<SendableCGImage?, Never>
        ) -> (task: Task<SendableCGImage?, Never>, isNew: Bool) {
            if let existing = tasks[key] {
                return (existing, false)
            }
            let newTask = create()
            tasks[key] = newTask
            return (newTask, true)
        }

        func removeTask(for key: String) {
            tasks.removeValue(forKey: key)
        }
    }

    private static let inFlightTasks = InFlightDownsampleTasks()
    private static let prewarmSizes: [CGSize] = [
        CGSize(width: 110, height: 120), // Photos grid
        CGSize(width: 128, height: 128)  // Home "Last Photos" (typowy zakres)
    ]

    /// Laduje pomniejszony obraz do wyswietlania w UI.
    /// Kolejnosc: cache pamieci -> cache dyskowy -> downsampling -> zapis do cache.
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
        let (task, isNewTask) = await inFlightTasks.task(for: cacheKey) {
            Task.detached(priority: .userInitiated) {
                guard let cg = ImageDownsampler.downsampleCGImage(
                    imageData: sourceData,
                    to: sourceSize,
                    scale: sourceScale
                ) else { return nil }
                return SendableCGImage(cgImage: cg)
            }
        }

        let generated = await task.value
        if isNewTask {
            await inFlightTasks.removeTask(for: cacheKey)
        }
        guard let generated else { return nil }

        let image = UIImage(cgImage: generated.cgImage)
        await MainActor.run {
            ImageCache.shared.setImage(image, forKey: cacheKey)
        }

        if isNewTask, let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData() {
            await DiskImageCache.shared.setData(data, forKey: cacheKey)
        }
        return image
    }

    /// Asynchronicznie prewarmuje najczestsze warianty miniatur nowo zapisanego zdjecia.
    /// Dziala best-effort: wynik nie jest wymagany do kontynuacji flow zapisu.
    static func prewarmRecentPhotoVariants(
        imageData: Data,
        cacheID: String,
        scale: CGFloat? = nil
    ) async {
        let resolvedScale: CGFloat
        if let scale {
            resolvedScale = scale
        } else {
            resolvedScale = await MainActor.run { UIScreen.main.scale }
        }

        for size in prewarmSizes {
            let width = Int(max(size.width * resolvedScale, 1))
            let height = Int(max(size.height * resolvedScale, 1))
            let cacheKey = "\(cacheID)_downsample_\(width)x\(height)"
            _ = await downsampledImage(
                imageData: imageData,
                cacheKey: cacheKey,
                targetSize: size,
                scale: resolvedScale
            )
            await Task.yield()
        }
    }
}
