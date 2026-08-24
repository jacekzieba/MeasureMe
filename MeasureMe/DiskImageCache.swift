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

    /// The directory grew for the lifetime of an install: there was no byte budget, no age
    /// limit and no sweep, only per-key removal that needed a caller who knew the key.
    private static let maxTotalBytes = 128 * 1024 * 1024
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
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

    /// Drops entries older than `maxAge`, then oldest-first until the directory fits
    /// `maxTotalBytes`. Cheap enough to run once per launch.
    func trim() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        struct Entry {
            let url: URL
            let modified: Date
            let size: Int
        }

        let now = Date()
        var entries: [Entry] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: keys)
            let modified = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            if now.timeIntervalSince(modified) > Self.maxAge {
                try? fileManager.removeItem(at: url)
                continue
            }
            entries.append(Entry(url: url, modified: modified, size: size))
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > Self.maxTotalBytes else { return }

        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= Self.maxTotalBytes { break }
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
