import UIKit
import SwiftUI
import CryptoKit

/// LRU (Least Recently Used) Cache dla obrazów
/// Automatycznie zarządza pamięcią i usuwa najdawniej używane obrazy przy przekroczeniu limitu.
///
/// Uzywa opakowania `CacheEntry`; gdy NSCache cicho usuwa obiekty
/// pod presja pamieci `deinit` opakowania zapisuje usuniety klucz.
/// This keeps the LRU linked list (and therefore `cachedImagesCount`) accurate.
@MainActor
final class ImageCache {

    // MARK: - Singleton

    static let shared = ImageCache()

    // MARK: - Properties

    private let cache = NSCache<NSString, CacheEntry>()
    private var lruNodes: [String: LRUNode] = [:]
    private var lruHead: LRUNode?
    private var lruTail: LRUNode?
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

        let nsKey = NSString(string: key)
        if let entry = cache.object(forKey: nsKey) {
            // Aktualizuj kolejność dostępu (LRU)
            updateAccessOrder(key: key)
            return entry.image
        }

        return nil
    }

    /// Zapisuje obraz do cache
    func setImage(_ image: UIImage, forKey key: String) {
        let nsKey = NSString(string: key)

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
        let nsKey = NSString(string: key)
        cache.removeObject(forKey: nsKey)

        removeFromLRU(key: key)
        drainEvictedKeys()

        #if DEBUG
        AppLog.debug("🗑️ Removed from cache: \(key)")
        #endif
    }

    /// Usuwa wszystkie obrazy, ktorych klucz zaczyna sie od podanego prefixu.
    /// Uzywane przy usuwaniu zdjecia, aby wyrzucic wszystkie warianty miniatur.
    func removeImages(withPrefix prefix: String) {
        let keysToRemove = lruNodes.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            let nsKey = NSString(string: key)
            cache.removeObject(forKey: nsKey)
            removeFromLRU(key: key)
        }
        drainEvictedKeys()

        #if DEBUG
        if !keysToRemove.isEmpty {
            AppLog.debug("🗑️ Removed \(keysToRemove.count) cache entries with prefix: \(prefix)")
        }
        #endif
    }

    /// Czyści cały cache
    func removeAll() {
        cache.removeAllObjects()
        lruNodes.removeAll()
        lruHead = nil
        lruTail = nil
        _ = evictionTracker.drain() // Discard stale eviction records

        AppLog.debug("🗑️ Image cache cleared")
    }

    // MARK: - LRU Management

    private func updateAccessOrder(key: String) {
        if let existing = lruNodes[key] {
            moveToTail(existing)
            return
        }

        let node = LRUNode(key: key)
        appendToTail(node)
        lruNodes[key] = node

        if lruNodes.count > maxAccessOrderSize, let oldest = lruHead {
            removeNode(oldest)
            lruNodes.removeValue(forKey: oldest.key)
        }
    }

    /// Removes keys from accessOrder that NSCache evicted behind our back.
    private func drainEvictedKeys() {
        let evicted = evictionTracker.drain()
        guard !evicted.isEmpty else { return }
        for key in evicted {
            removeFromLRU(key: key)
        }
    }

    /// Zwraca najmniej ostatnio używane klucze (dla debugowania)
    func getLeastRecentlyUsedKeys(count: Int) -> [String] {
        guard count > 0 else { return [] }
        var result: [String] = []
        result.reserveCapacity(count)
        var cursor = lruHead
        while let node = cursor, result.count < count {
            result.append(node.key)
            cursor = node.next
        }
        return result
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
            cachedImagesCount: lruNodes.count,
            countLimit: countLimit,
            totalCostLimit: totalCostLimit,
            leastRecentlyUsed: getLeastRecentlyUsedKeys(count: 5)
        )
    }

    private func appendToTail(_ node: LRUNode) {
        node.previous = lruTail
        node.next = nil
        if let tail = lruTail {
            tail.next = node
        } else {
            lruHead = node
        }
        lruTail = node
    }

    private func moveToTail(_ node: LRUNode) {
        guard lruTail !== node else { return }
        removeNode(node)
        appendToTail(node)
    }

    private func removeFromLRU(key: String) {
        guard let node = lruNodes.removeValue(forKey: key) else { return }
        removeNode(node)
    }

    private func removeNode(_ node: LRUNode) {
        let previous = node.previous
        let next = node.next

        if let previous {
            previous.next = next
        } else {
            lruHead = next
        }

        if let next {
            next.previous = previous
        } else {
            lruTail = previous
        }

        node.previous = nil
        node.next = nil
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

/// Bezpieczny watkowo kolektor kluczy usunietych z cache.
/// NSCache moze usuwac wpisy na dowolnym watku, dlatego zapisy sa chronione blokada.
/// Reads (drain) happen on @MainActor inside ImageCache.
private final class EvictionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _keys: [String] = []

    /// Rejestruje usuniecie klucza (wywolywane z CacheEntry.deinit na dowolnym watku).
    func record(_ key: String) {
        lock.lock()
        _keys.append(key)
        lock.unlock()
    }

    /// Zwraca i czysci wszystkie zebrane klucze usuniec.
    func drain() -> [String] {
        lock.lock()
        let result = _keys
        _keys.removeAll()
        lock.unlock()
        return result
    }
}

/// Wrapper around UIImage stored in NSCache.
/// Gdy NSCache cicho usunie wpis, `deinit` zapisuje klucz
/// aby ImageCache mogl posprzatac `accessOrder` przy kolejnym dostepie.
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

private final class LRUNode {
    let key: String
    var previous: LRUNode?
    var next: LRUNode?

    init(key: String) {
        self.key = key
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
