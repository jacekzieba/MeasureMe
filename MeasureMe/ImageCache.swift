import UIKit
import SwiftUI

/// LRU (Least Recently Used) Cache dla obrazów
/// Automatycznie zarządza pamięcią i usuwa najdawniej używane obrazy przy przekroczeniu limitu
@MainActor
final class ImageCache {
    
    // MARK: - Singleton
    
    static let shared = ImageCache()
    
    // MARK: - Properties
    
    private var cache: NSCache<NSString, UIImage>
    private var accessOrder: [String] = [] // Kolejność dostępu dla LRU
    private let maxAccessOrderSize = 200 // Max liczba śledzionych kluczy
    
    // MARK: - Configuration
    
    /// Maksymalna liczba obiektów w cache (domyślnie 50)
    var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }
    
    /// Maksymalny koszt w bajtach (domyślnie 100MB)
    var totalCostLimit: Int {
        get { cache.totalCostLimit }
        set { cache.totalCostLimit = newValue }
    }
    
    // MARK: - Initialization
    
    private init() {
        self.cache = NSCache<NSString, UIImage>()
        
        // Domyślna konfiguracja
        cache.countLimit = 50 // Max 50 obrazów
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
        cache.name = "ImageCache"
        
        // Obsługa memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        AppLog.debug("✅ ImageCache initialized (limit: \(countLimit) images, \(totalCostLimit / 1024 / 1024)MB)")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Cache Operations
    
    /// Pobiera obraz z cache
    func image(forKey key: String) -> UIImage? {
        let nsKey = key as NSString
        
        if let image = cache.object(forKey: nsKey) {
            // Aktualizuj kolejność dostępu (LRU)
            updateAccessOrder(key: key)
            return image
        }
        
        return nil
    }
    
    /// Zapisuje obraz do cache
    func setImage(_ image: UIImage, forKey key: String) {
        let nsKey = key as NSString
        
        // Oblicz koszt (przybliżony rozmiar w pamięci)
        let cost = calculateImageCost(image)
        
        cache.setObject(image, forKey: nsKey, cost: cost)
        
        // Aktualizuj kolejność dostępu
        updateAccessOrder(key: key)
        
        #if DEBUG
        AppLog.debug("📦 Cached image: \(key) (cost: \(cost / 1024)KB)")
        #endif
    }
    
    /// Usuwa obraz z cache
    func removeImage(forKey key: String) {
        let nsKey = key as NSString
        cache.removeObject(forKey: nsKey)
        
        accessOrder.removeAll { $0 == key }
        
        #if DEBUG
        AppLog.debug("🗑️ Removed from cache: \(key)")
        #endif
    }
    
    /// Czyści cały cache
    func removeAll() {
        cache.removeAllObjects()
        accessOrder.removeAll()
        
        AppLog.debug("🗑️ Image cache cleared")
    }
    
    // MARK: - LRU Management
    
    private func updateAccessOrder(key: String) {
        // Usuń poprzednie wystąpienie
        accessOrder.removeAll { $0 == key }
        
        // Dodaj na koniec (most recently used)
        accessOrder.append(key)
        
        // Utrzymuj rozmiar kolejności w rozsądnych granicach
        if accessOrder.count > maxAccessOrderSize {
            let removeCount = accessOrder.count - maxAccessOrderSize
            accessOrder.removeFirst(removeCount)
        }
    }
    
    /// Zwraca najmniej ostatnio używane klucze (dla debugowania)
    func getLeastRecentlyUsedKeys(count: Int) -> [String] {
        Array(accessOrder.prefix(count))
    }
    
    // MARK: - Memory Management
    
    @objc private func handleMemoryWarning() {
        AppLog.debug("⚠️ Memory warning received - clearing image cache")
        removeAll()
    }
    
    /// Oblicza przybliżony koszt obrazu w bajtach
    private func calculateImageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4 // RGBA
        
        return width * height * bytesPerPixel
    }
    
    // MARK: - Statistics
    
    /// Zwraca statystyki cache (dla debugowania)
    func getStatistics() -> CacheStatistics {
        CacheStatistics(
            cachedImagesCount: accessOrder.count,
            countLimit: countLimit,
            totalCostLimit: totalCostLimit,
            leastRecentlyUsed: getLeastRecentlyUsedKeys(count: 5)
        )
    }
}

// MARK: - Cache Statistics

struct CacheStatistics {
    let cachedImagesCount: Int
    let countLimit: Int
    let totalCostLimit: Int
    let leastRecentlyUsed: [String]
    
    var totalCostLimitMB: Int {
        totalCostLimit / 1024 / 1024
    }
    
    var description: String {
        """
        Image Cache Statistics:
        - Cached images: \(cachedImagesCount) / \(countLimit)
        - Memory limit: \(totalCostLimitMB)MB
        - LRU keys: \(leastRecentlyUsed.joined(separator: ", "))
        """
    }
}

// MARK: - Convenience Extensions

extension UIImage {
    
    /// Cache key bazujący na danych obrazu (hash)
    static func cacheKey(from data: Data) -> String {
        let hash = data.hashValue
        return "image_\(hash)"
    }
    
    /// Pobiera obraz z cache lub tworzy nowy
    static func cachedImage(from data: Data) -> UIImage? {
        let key = cacheKey(from: data)
        
        // Sprawdź cache
        if let cached = ImageCache.shared.image(forKey: key) {
            return cached
        }
        
        // Stwórz nowy i cache'uj
        if let image = UIImage(data: data) {
            ImageCache.shared.setImage(image, forKey: key)
            return image
        }
        
        return nil
    }
}

// MARK: - Preview Helper

#if DEBUG
extension ImageCache {
    /// Resetuje cache (tylko dla testów)
    func reset() {
        cache.removeAllObjects()
        accessOrder.removeAll()
        AppLog.debug("🔄 ImageCache reset")
    }
}
#endif
