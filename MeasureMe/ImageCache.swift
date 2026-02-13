import UIKit
import SwiftUI
import CryptoKit

/// LRU (Least Recently Used) Cache dla obrazów
/// Automatycznie zarządza pamięcią i usuwa najdawniej używane obrazy przy przekroczeniu limitu.
///
/// Uses a `CacheEntry` wrapper so that when NSCache silently evicts objects
/// under memory pressure, the wrapper's `deinit` records the evicted key.
/// This keeps `accessOrder` (and therefore `cachedImagesCount`) accurate.
@MainActor
final class ImageCache {

    // MARK: - Singleton

    static let shared = ImageCache()

    // MARK: - Properties

    private let cache = NSCache<NSString, CacheEntry>()
    private var accessOrder: [String] = [] // Kolejność dostępu dla LRU
    private let maxAccessOrderSize = 200 // Max liczba śledzionych kluczy
    private let evictionTracker = EvictionTracker()

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
        drainEvictedKeys()

        let nsKey = key as NSString
        if let entry = cache.object(forKey: nsKey) {
            // Aktualizuj kolejność dostępu (LRU)
            updateAccessOrder(key: key)
            return entry.image
        }

        return nil
    }

    /// Zapisuje obraz do cache
    func setImage(_ image: UIImage, forKey key: String) {
        let nsKey = key as NSString

        // Oblicz koszt (przybliżony rozmiar w pamięci)
        let cost = calculateImageCost(image)

        let entry = CacheEntry(key: key, image: image, tracker: evictionTracker)
        cache.setObject(entry, forKey: nsKey, cost: cost)

        // Aktualizuj kolejność dostępu
        updateAccessOrder(key: key)

        // Drain any keys evicted by NSCache during setObject
        drainEvictedKeys()

        #if DEBUG
        AppLog.debug("📦 Cached image: \(key) (cost: \(cost / 1024)KB)")
        #endif
    }

    /// Usuwa obraz z cache
    func removeImage(forKey key: String) {
        let nsKey = key as NSString
        cache.removeObject(forKey: nsKey)

        accessOrder.removeAll { $0 == key }
        drainEvictedKeys()

        #if DEBUG
        AppLog.debug("🗑️ Removed from cache: \(key)")
        #endif
    }

    /// Czyści cały cache
    func removeAll() {
        cache.removeAllObjects()
        accessOrder.removeAll()
        _ = evictionTracker.drain() // Discard stale eviction records

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

    /// Removes keys from accessOrder that NSCache evicted behind our back.
    private func drainEvictedKeys() {
        let evicted = evictionTracker.drain()
        guard !evicted.isEmpty else { return }
        let evictedSet = Set(evicted)
        accessOrder.removeAll { evictedSet.contains($0) }
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
        drainEvictedKeys()
        return CacheStatistics(
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

// MARK: - Eviction Tracking

/// Thread-safe collector of evicted cache keys.
/// NSCache may evict on any thread, so writes are lock-protected.
/// Reads (drain) happen on @MainActor inside ImageCache.
private final class EvictionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _keys: [String] = []

    /// Records that a key was evicted (called from CacheEntry.deinit, any thread).
    func record(_ key: String) {
        lock.lock()
        _keys.append(key)
        lock.unlock()
    }

    /// Returns and clears all collected evicted keys.
    func drain() -> [String] {
        lock.lock()
        let result = _keys
        _keys.removeAll()
        lock.unlock()
        return result
    }
}

/// Wrapper around UIImage stored in NSCache.
/// When NSCache silently evicts this entry, `deinit` fires and records the key
/// so that ImageCache can clean up `accessOrder` on the next access.
private final class CacheEntry {
    let key: String
    let image: UIImage
    private let tracker: EvictionTracker

    init(key: String, image: UIImage, tracker: EvictionTracker) {
        self.key = key
        self.image = image
        self.tracker = tracker
    }

    deinit {
        tracker.record(key)
    }
}

// MARK: - Convenience Extensions

extension UIImage {

    /// Cache key bazujący na danych obrazu (SHA-256, stabilny między uruchomieniami)
    static func cacheKey(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "image_\(hex)"
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
        removeAll()
        AppLog.debug("🔄 ImageCache reset")
    }
}
#endif
