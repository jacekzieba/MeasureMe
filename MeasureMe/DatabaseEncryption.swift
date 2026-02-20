import Foundation

/// Stosuje ochrone danych iOS do plikow bazy danych na urzadzeniu.
/// To zalecany przez Apple mechanizm "encryption at rest" dla wrazliwych danych aplikacji.
///
/// Uwaga: `.completeUntilFirstUserAuthentication` utrzymuje dane zaszyfrowane w spoczynku,
/// a jednoczesnie pozwala na prace w tle po pierwszym odblokowaniu (lepszy UX/stabilnosc dla aktualizacji HealthKit).
enum DatabaseEncryption {
    static let protection: FileProtectionType = .completeUntilFirstUserAuthentication
    private static let protectionVersionKey = "database_encryption_protection_applied_version"

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

            // SwiftData moze trzymac dane w pakietach `.store` lub plikach SQLite (plus WAL/SHM).
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

    static func applyRecommendedProtectionIfNeeded() {
        let defaults = UserDefaults.standard
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let versionFingerprint = "\(shortVersion)-\(buildVersion)"

        if defaults.string(forKey: protectionVersionKey) == versionFingerprint {
            return
        }

        applyRecommendedProtection()
        defaults.set(versionFingerprint, forKey: protectionVersionKey)
    }

    private static func isLikelyDatabaseStore(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "store" || ext == "sqlite" || ext == "db" { return true }
        // Zachowaj ostroznosc: domyslny store SwiftData czesto nazywa sie `default.store`.
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
            // Sprobuj tez zabezpieczyc pliki poboczne WAL/SHM, jesli to plik SQLite.
            protectSQLiteSidecars(for: url)
            return
        }

        // Zabezpiecz zawartosc pakietow `.store`.
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
