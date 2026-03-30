import UIKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Utilities for photo handling
enum PhotoUtilities {
    struct EncodedPhoto: Sendable {
        let data: Data
        let format: String
        let quality: CGFloat
    }

    nonisolated static let gridThumbnailSize = CGSize(width: 220, height: 220)
    nonisolated static let gridThumbnailTargetBytes = 40_000
    nonisolated static let gridThumbnailMaxBytes = 60_000
    
    // MARK: - Image Compression
    
    /// Compresses the image to a specified size (in bytes)
    /// - Parameters:
    ///   - image: Image to compress
    ///   - maxSize: Maximum size in bytes
    /// - Returns: Compressed image data or nil
    nonisolated static func compress(_ image: UIImage, toMaxSize maxSize: Int = 2_000_000) -> Data? {
        encodeForStorage(image, maxSize: maxSize)?.data
    }
    
    /// Compresses the image to JPEG with a specified quality
    /// - Parameters:
    ///   - image: Image to compress
    ///   - quality: JPEG quality (0.0 - 1.0)
    /// - Returns: Compressed image data
    nonisolated static func compress(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        if supportsHEICEncoding(), let data = encode(image: image, typeIdentifier: UTType.heic.identifier, quality: quality) {
            return data
        }
        return image.jpegData(compressionQuality: quality)
    }
    
    // MARK: - Image Resizing
    
    /// Resizes the image while preserving aspect ratio
    /// - Parameters:
    ///   - image: Image to resize
    ///   - maxDimension: Maximum dimension (width or height)
    /// - Returns: Resized image
    nonisolated static func resize(_ image: UIImage, maxDimension: CGFloat = 1920) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Don't enlarge images smaller than maxDimension
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    nonisolated static func prepareImportedImage(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        fixOrientation(resize(image, maxDimension: maxDimension))
    }
    
    // MARK: - Image Orientation
    
    /// Fixes image orientation (removes EXIF flags)
    /// - Parameter image: Image to fix
    /// - Returns: Image with corrected orientation
    nonisolated static func fixOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    nonisolated static func downsampledImage(from url: URL, maxDimension: CGFloat = 2048) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    nonisolated static func encodeForStorage(
        _ image: UIImage,
        maxSize: Int = 2_000_000,
        alreadyPrepared: Bool = false
    ) -> EncodedPhoto? {
        let prepared = alreadyPrepared ? image : prepareImportedImage(image)
        let formats: [(id: String, label: String)] = supportsHEICEncoding()
            ? [(UTType.heic.identifier, "HEIC"), (UTType.jpeg.identifier, "JPEG")]
            : [(UTType.jpeg.identifier, "JPEG")]

        for format in formats {
            if let encoded = encodeBestFit(
                image: prepared,
                typeIdentifier: format.id,
                formatLabel: format.label,
                maxSize: maxSize
            ) {
                return encoded
            }
        }
        return nil
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generates an image thumbnail
    /// - Parameters:
    ///   - image: Source image
    ///   - size: Thumbnail size
    /// - Returns: Image thumbnail
    nonisolated static func thumbnail(from image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0, size.width > 0, size.height > 0 else {
            return image
        }

        let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (size.width - scaledSize.width) / 2,
            y: (size.height - scaledSize.height) / 2
        )
        let drawRect = CGRect(origin: origin, size: scaledSize)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: drawRect)
        }
    }

    nonisolated static func matchesGridThumbnailSpec(_ data: Data?) -> Bool {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return false
        }

        return Int(width.rounded()) == Int(gridThumbnailSize.width.rounded())
            && Int(height.rounded()) == Int(gridThumbnailSize.height.rounded())
    }

    nonisolated static func makeGridThumbnailData(
        from image: UIImage,
        size: CGSize = gridThumbnailSize,
        targetBytes: Int = gridThumbnailTargetBytes,
        maxBytes: Int = gridThumbnailMaxBytes
    ) -> Data? {
        let thumbnailImage = thumbnail(from: image, size: size)
        if let optimistic = thumbnailImage.jpegData(compressionQuality: 0.82),
           optimistic.count <= targetBytes {
            return optimistic
        }

        let minQuality: CGFloat = 0.35
        let maxQuality: CGFloat = 0.92
        var lower = minQuality
        var upper = maxQuality
        var bestData: Data?

        for _ in 0..<6 {
            let quality = (lower + upper) / 2
            guard let data = thumbnailImage.jpegData(compressionQuality: quality) else {
                break
            }
            if data.count <= targetBytes {
                bestData = data
                lower = quality
            } else {
                upper = quality
            }
        }

        if let bestData {
            return bestData
        }

        var quality = minQuality
        while quality >= 0.1 {
            if let data = thumbnailImage.jpegData(compressionQuality: quality),
               data.count <= maxBytes {
                return data
            }
            quality -= 0.08
        }

        return thumbnailImage.jpegData(compressionQuality: 0.1)
    }

    nonisolated static func makeGridThumbnailData(
        from imageData: Data,
        size: CGSize = gridThumbnailSize,
        targetBytes: Int = gridThumbnailTargetBytes,
        maxBytes: Int = gridThumbnailMaxBytes
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return makeGridThumbnailData(
            from: image,
            size: size,
            targetBytes: targetBytes,
            maxBytes: maxBytes
        )
    }
    
    // MARK: - Format Detection
    
    /// Determines the image format based on data
    /// - Parameter data: Image data
    /// - Returns: Image format as a string (e.g. "JPEG", "PNG")
    nonisolated static func imageFormat(from data: Data) -> String? {
        guard let firstByte = data.first else { return nil }
        
        switch firstByte {
        case 0xFF:
            return "JPEG"
        case 0x89:
            return "PNG"
        case 0x47:
            return "GIF"
        case 0x49, 0x4D:
            return "TIFF"
        default:
            return nil
        }
    }
    
    // MARK: - Size Formatting
    
    /// Formats data size to a human-readable string
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g. "1.5 MB")
    nonisolated static func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    nonisolated static func isPreparedForImport(_ image: UIImage, maxDimension: CGFloat = 2048) -> Bool {
        let maxImageDimension = max(image.size.width, image.size.height)
        return image.imageOrientation == .up && maxImageDimension <= maxDimension
    }

    private nonisolated static func supportsHEICEncoding() -> Bool {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(UTType.heic.identifier)
    }

    private nonisolated static func encodeBestFit(
        image: UIImage,
        typeIdentifier: String,
        formatLabel: String,
        maxSize: Int
    ) -> EncodedPhoto? {
        let minQuality: CGFloat = 0.45
        let maxQuality: CGFloat = 0.92
        // 4 binary search iterations = ~0.03 quality precision (visually indistinguishable).
        // Each iteration is a full encode ~30-80ms — fewer iterations = faster.
        let iterations = 4

        // Optimistic start: try maxQuality first — if it fits within the limit,
        // no binary search is needed at all.
        if let data = encode(image: image, typeIdentifier: typeIdentifier, quality: maxQuality),
           data.count <= maxSize {
            return EncodedPhoto(data: data, format: formatLabel, quality: maxQuality)
        }

        var lower = minQuality
        var upper = maxQuality
        var bestData: Data?
        var bestQuality: CGFloat = minQuality

        for _ in 0..<iterations {
            let quality = (lower + upper) / 2
            guard let data = encode(image: image, typeIdentifier: typeIdentifier, quality: quality) else {
                break
            }

            if data.count <= maxSize {
                bestData = data
                bestQuality = quality
                lower = quality
            } else {
                upper = quality
            }
        }

        if let bestData {
            return EncodedPhoto(data: bestData, format: formatLabel, quality: bestQuality)
        }

        guard let fallback = encode(image: image, typeIdentifier: typeIdentifier, quality: minQuality) else {
            return nil
        }
        return EncodedPhoto(data: fallback, format: formatLabel, quality: minQuality)
    }

    private nonisolated static func encode(image: UIImage, typeIdentifier: String, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    
    /// Kompresuje obraz do określonego rozmiaru
    func compressed(toMaxSize maxSize: Int = 2_000_000) -> Data? {
        PhotoUtilities.encodeForStorage(self, maxSize: maxSize)?.data
    }
    
    /// Kompresuje obraz z określoną jakością
    func compressed(quality: CGFloat = 0.8) -> Data? {
        PhotoUtilities.compress(self, quality: quality)
    }
    
    /// Zmienia rozmiar obrazu zachowując proporcje
    func resized(maxDimension: CGFloat = 1920) -> UIImage {
        PhotoUtilities.resize(self, maxDimension: maxDimension)
    }
    
    /// Naprawia orientację obrazu
    func fixedOrientation() -> UIImage {
        PhotoUtilities.fixOrientation(self)
    }
    
    /// Generuje miniaturę obrazu
    func thumbnail(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        PhotoUtilities.thumbnail(from: self, size: size)
    }
}

// MARK: - Pomocniki podgladu

#if DEBUG
extension PhotoUtilities {
    
    /// Tworzy testowy obraz dla preview
    nonisolated static func previewImage(systemName: String = "photo.fill") -> UIImage {
        UIImage(systemName: systemName) ?? UIImage()
    }
    
    /// Tworzy testowe dane obrazu dla preview
    nonisolated static func previewImageData(systemName: String = "photo.fill") -> Data {
        previewImage(systemName: systemName).pngData() ?? Data()
    }
}
#endif
