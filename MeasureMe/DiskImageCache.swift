import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Simple disk-based image cache (Caches directory).
/// Used as a second-level cache below `ImageCache` (in-memory) to avoid re-decoding thumbnails between launches.
actor DiskImageCache {
    static let shared = DiskImageCache()

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let memoryDataCache = NSCache<NSString, NSData>()

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("MeasureMeImageCache", isDirectory: true)
        memoryDataCache.countLimit = 300
        memoryDataCache.totalCostLimit = 64 * 1024 * 1024

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directoryURL.path
            )
        } catch {
            // Non-critical: if directory creation fails, cache operations will be skipped.
            AppLog.debug("⚠️ DiskImageCache: failed to create cache directory: \(error)")
        }
    }

    func data(forKey key: String) -> Data? {
        let nsKey = NSString(string: key)
        if let cached = memoryDataCache.object(forKey: nsKey) {
            return cached as Data
        }

        let url = fileURL(forKey: key)
        guard let loaded = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        memoryDataCache.setObject(loaded as NSData, forKey: nsKey, cost: loaded.count)
        return loaded
    }

    func setData(_ data: Data, forKey key: String) {
        let nsKey = NSString(string: key)
        memoryDataCache.setObject(data as NSData, forKey: nsKey, cost: data.count)

        let url = fileURL(forKey: key)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            // Non-critical: disk cache operates on a best-effort basis.
            #if DEBUG
            AppLog.debug("⚠️ DiskImageCache: write failed for \(key): \(error)")
            #endif
        }
    }

    func removeImage(forKey key: String) {
        let nsKey = NSString(string: key)
        memoryDataCache.removeObject(forKey: nsKey)
        let url = fileURL(forKey: key)
        try? fileManager.removeItem(at: url)
    }

    /// Removes disk cache data for all provided keys.
    func removeImages(forKeys keys: [String]) {
        for key in keys {
            removeImage(forKey: key)
        }
    }

    func removeAll() throws {
        memoryDataCache.removeAllObjects()
        let items: [URL]
        do {
            items = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        for url in items {
            try fileManager.removeItem(at: url)
        }
    }

    private func fileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent(hashedFileName(forKey: key), isDirectory: false)
    }

    private func hashedFileName(forKey key: String) -> String {
        // File-system safe and stable.
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).jpg"
        #else
        // Fallback (less stable, but still file-system safe).
        let sanitized = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        return "\(sanitized).jpg"
        #endif
    }
}
