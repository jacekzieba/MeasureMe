import Foundation

/// Applies iOS Data Protection to on-device database files.
/// This is Apple's recommended "encryption at rest" mechanism for sensitive app data.
///
/// Note: `.completeUntilFirstUserAuthentication` keeps data encrypted at rest,
/// while still allowing background work after the first unlock (better UX/stability for HealthKit updates).
enum DatabaseEncryption {
    static let protection: FileProtectionType = .completeUntilFirstUserAuthentication

    static func applyRecommendedProtection() {
        let fm = FileManager.default
        let roots: [URL] = [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for root in roots {
            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                try fm.setAttributes([.protectionKey: protection], ofItemAtPath: root.path)
            } catch {
                AppLog.debug("⚠️ DatabaseEncryption: failed to protect \(root.lastPathComponent) directory: \(error)")
            }

            // SwiftData may store data in `.store` packages or SQLite files (plus WAL/SHM).
            let candidates: [URL]
            do {
                candidates = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                #if DEBUG
                AppLog.debug("⚠️ DatabaseEncryption: failed to enumerate \(root.lastPathComponent): \(error)")
                #endif
                continue
            }

            for url in candidates where isLikelyDatabaseStore(url) {
                protectRecursively(url)
            }
        }
    }

    private static func isLikelyDatabaseStore(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "store" || ext == "sqlite" || ext == "db" { return true }
        // Be conservative: SwiftData default store is often named `default.store`.
        if url.lastPathComponent.lowercased().contains("default.store") { return true }
        return false
    }

    private static func protectRecursively(_ url: URL) {
        let fm = FileManager.default

        do {
            try fm.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        } catch {
            #if DEBUG
            AppLog.debug("⚠️ DatabaseEncryption: failed to protect \(url.lastPathComponent): \(error)")
            #endif
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            // Also try protecting WAL/SHM sidecars if this is a SQLite file.
            protectSQLiteSidecars(for: url)
            return
        }

        // Protect children of `.store` packages.
        if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for child in children {
                protectRecursively(child)
            }
        }
    }

    private static func protectSQLiteSidecars(for sqliteURL: URL) {
        let basePath = sqliteURL.path
        let fm = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let path = basePath + suffix
            if fm.fileExists(atPath: path) {
                try? fm.setAttributes([.protectionKey: protection], ofItemAtPath: path)
            }
        }
    }
}
