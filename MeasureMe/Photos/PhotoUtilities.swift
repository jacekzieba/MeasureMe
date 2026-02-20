import UIKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Utilities dla obsługi zdjęć
enum PhotoUtilities {
    struct EncodedPhoto {
        let data: Data
        let format: String
        let quality: CGFloat
    }
    
    // MARK: - Image Compression
    
    /// Kompresuje obraz do określonego rozmiaru (w bajtach)
    /// - Parameters:
    ///   - image: Obraz do skompresowania
    ///   - maxSize: Maksymalny rozmiar w bajtach
    /// - Returns: Skompresowane dane obrazu lub nil
    static func compress(_ image: UIImage, toMaxSize maxSize: Int = 2_000_000) -> Data? {
        encodeForStorage(image, maxSize: maxSize)?.data
    }
    
    /// Kompresuje obraz do JPEG z określoną jakością
    /// - Parameters:
    ///   - image: Obraz do skompresowania
    ///   - quality: Jakość JPEG (0.0 - 1.0)
    /// - Returns: Skompresowane dane obrazu
    static func compress(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        if supportsHEICEncoding(), let data = encode(image: image, typeIdentifier: UTType.heic.identifier, quality: quality) {
            return data
        }
        return image.jpegData(compressionQuality: quality)
    }
    
    // MARK: - Image Resizing
    
    /// Zmienia rozmiar obrazu zachowując proporcje
    /// - Parameters:
    ///   - image: Obraz do przeskalowania
    ///   - maxDimension: Maksymalny wymiar (szerokość lub wysokość)
    /// - Returns: Przeskalowany obraz
    static func resize(_ image: UIImage, maxDimension: CGFloat = 1920) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Nie powiększaj obrazów mniejszych niż maxDimension
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func prepareImportedImage(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        fixOrientation(resize(image, maxDimension: maxDimension))
    }
    
    // MARK: - Image Orientation
    
    /// Naprawia orientację obrazu (usuwa flagi EXIF)
    /// - Parameter image: Obraz do naprawy
    /// - Returns: Obraz z poprawioną orientacją
    static func fixOrientation(_ image: UIImage) -> UIImage {
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

    static func downsampledImage(from url: URL, maxDimension: CGFloat = 2048) -> UIImage? {
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

    static func encodeForStorage(
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
    
    /// Generuje miniaturę obrazu
    /// - Parameters:
    ///   - image: Obraz źródłowy
    ///   - size: Rozmiar miniatury
    /// - Returns: Miniatura obrazu
    static func thumbnail(from image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - Format Detection
    
    /// Określa format obrazu na podstawie danych
    /// - Parameter data: Dane obrazu
    /// - Returns: Format obrazu jako string (np. "JPEG", "PNG")
    static func imageFormat(from data: Data) -> String? {
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
    
    /// Formatuje rozmiar danych do czytelnego stringu
    /// - Parameter bytes: Liczba bajtów
    /// - Returns: Sformatowany string (np. "1.5 MB")
    static func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func isPreparedForImport(_ image: UIImage, maxDimension: CGFloat = 2048) -> Bool {
        let maxImageDimension = max(image.size.width, image.size.height)
        return image.imageOrientation == .up && maxImageDimension <= maxDimension
    }

    private static func supportsHEICEncoding() -> Bool {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(UTType.heic.identifier)
    }

    private static func encodeBestFit(
        image: UIImage,
        typeIdentifier: String,
        formatLabel: String,
        maxSize: Int
    ) -> EncodedPhoto? {
        let minQuality: CGFloat = 0.45
        let maxQuality: CGFloat = 0.92
        let iterations = 7

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

    private static func encode(image: UIImage, typeIdentifier: String, quality: CGFloat) -> Data? {
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
    static func previewImage(systemName: String = "photo.fill") -> UIImage {
        UIImage(systemName: systemName) ?? UIImage()
    }
    
    /// Tworzy testowe dane obrazu dla preview
    static func previewImageData(systemName: String = "photo.fill") -> Data {
        previewImage(systemName: systemName).pngData() ?? Data()
    }
}
#endif
