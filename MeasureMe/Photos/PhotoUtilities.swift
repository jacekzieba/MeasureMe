import UIKit
import SwiftUI

/// Utilities dla obsługi zdjęć
enum PhotoUtilities {
    
    // MARK: - Image Compression
    
    /// Kompresuje obraz do określonego rozmiaru (w bajtach)
    /// - Parameters:
    ///   - image: Obraz do skompresowania
    ///   - maxSize: Maksymalny rozmiar w bajtach
    /// - Returns: Skompresowane dane obrazu lub nil
    static func compress(_ image: UIImage, toMaxSize maxSize: Int = 2_000_000) -> Data? {
        var compression: CGFloat = 1.0
        var imageData = image.jpegData(compressionQuality: compression)
        
        // Jeśli obraz jest już wystarczająco mały, zwróć go
        if let data = imageData, data.count <= maxSize {
            return data
        }
        
        // Binarne wyszukiwanie najlepszej kompresji
        var minCompression: CGFloat = 0.0
        var maxCompression: CGFloat = 1.0
        
        for _ in 0..<6 { // Max 6 iteracji
            compression = (minCompression + maxCompression) / 2
            
            guard let data = image.jpegData(compressionQuality: compression) else {
                return nil
            }
            
            imageData = data
            
            if data.count < Int(Double(maxSize) * 0.9) {
                minCompression = compression
            } else if data.count > maxSize {
                maxCompression = compression
            } else {
                break
            }
        }
        
        return imageData
    }
    
    /// Kompresuje obraz do JPEG z określoną jakością
    /// - Parameters:
    ///   - image: Obraz do skompresowania
    ///   - quality: Jakość JPEG (0.0 - 1.0)
    /// - Returns: Skompresowane dane obrazu
    static func compress(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
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
}

// MARK: - UIImage Extensions

extension UIImage {
    
    /// Kompresuje obraz do określonego rozmiaru
    func compressed(toMaxSize maxSize: Int = 2_000_000) -> Data? {
        PhotoUtilities.compress(self, toMaxSize: maxSize)
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

// MARK: - Preview Helpers

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
