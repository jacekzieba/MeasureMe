import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Simple on-disk image cache (Caches directory).
/// Used as a secondary cache below `ImageCache` (memory) to avoid re-decoding thumbnails between launches.
actor DiskImageCache {
    static let shared = DiskImageCache()

    private let fileManager = FileManager.default
    private let directoryURL: URL

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("MeasureMeImageCache", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directoryURL.path
            )
        } catch {
            // Non-fatal: if directory creation fails, cache operations will no-op.
            AppLog.debug("⚠️ DiskImageCache: failed to create cache directory: \(error)")
        }
    }

    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        return try? Data(contentsOf: url)
    }

    func setData(_ data: Data, forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            // Non-fatal: disk cache best-effort.
            #if DEBUG
            AppLog.debug("⚠️ DiskImageCache: write failed for \(key): \(error)")
            #endif
        }
    }

    func removeImage(forKey key: String) {
        let url = fileURL(forKey: key)
        try? fileManager.removeItem(at: url)
    }

    func removeAll() throws {
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
        // Fallback (less stable, but still file-safe).
        let sanitized = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        return "\(sanitized).jpg"
        #endif
    }
}
