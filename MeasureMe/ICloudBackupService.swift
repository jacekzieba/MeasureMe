import Foundation
import SwiftData
import CryptoKit

enum ICloudBackupService {

    // MARK: - Errors

    enum BackupError: Error, Equatable {
        case premiumRequired
        case backupDisabled
        case noBackupFound
        case invalidBackupSchema
        case encryptionError
        case fileSystemError(String)

        var localizedMessage: String {
            switch self {
            case .premiumRequired:
                return AppLocalization.string("iCloud backup requires Premium.")
            case .backupDisabled:
                return AppLocalization.string("iCloud backup is disabled.")
            case .noBackupFound:
                return AppLocalization.string("No iCloud backup was found.")
            case .invalidBackupSchema:
                return AppLocalization.string("The backup is incompatible with this app version.")
            case .encryptionError:
                return AppLocalization.string("Could not create iCloud backup: %@.", "encryption")
            case .fileSystemError(let detail):
                if detail.contains("iCloud container unavailable") {
                    return AppLocalization.string("iCloud Drive is unavailable on this device.")
                }
                return AppLocalization.string("Could not create iCloud backup: %@.", detail)
            }
        }
    }

    // MARK: - Test overrides

    static var testBackupRootURLOverride: URL?
    static var testNowOverride: (() -> Date)?
    static var testEncryptionKeyOverride: SymmetricKey?

    static func resetTestOverrides() {
        testBackupRootURLOverride = nil
        testNowOverride = nil
        testEncryptionKeyOverride = nil
    }

    // MARK: - Constants

    private static let currentSchemaVersion = 1
    private static let maxRetainedBackups = 7
    private static let scheduledBackupInterval: TimeInterval = 86_400 // 24 hours
    private static let backupExtension = "measuremebackup"
    private static let keychainTag = "com.jacek.measureme.backup-key".data(using: .utf8)!

    // MARK: - Public API

    static func createBackupNow(
        context: ModelContext,
        isPremium: Bool
    ) async -> Result<ICloudBackupManifest, BackupError> {
        guard isPremium else { return .failure(.premiumRequired) }
        guard AppSettingsStore.shared.snapshot.iCloudBackup.isEnabled else {
            return .failure(.backupDisabled)
        }

        guard let rootURL = backupRootURL() else {
            return .failure(.fileSystemError("iCloud container unavailable"))
        }

        guard let key = encryptionKey() else {
            return .failure(.encryptionError)
        }

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let timestamp = now()
            let packageName = "backup-\(Int(timestamp.timeIntervalSince1970)).\(backupExtension)"
            let packageURL = rootURL.appendingPathComponent(packageName, isDirectory: true)
            try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

            let photosDir = packageURL.appendingPathComponent("photos", isDirectory: true)
            try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)

            // Fetch data
            let metrics = try context.fetch(FetchDescriptor<MetricSample>())
            let goals = try context.fetch(FetchDescriptor<MetricGoal>())
            let photos = try context.fetch(FetchDescriptor<PhotoEntry>())

            // Serialize and encrypt metrics
            let codableMetrics = metrics.map {
                CodableMetricSample(kindRaw: $0.kindRaw, value: $0.value, date: $0.date)
            }
            try writeEncrypted(codableMetrics, to: packageURL.appendingPathComponent("metrics.json"), key: key)

            // Serialize and encrypt goals
            let codableGoals = goals.map {
                CodableMetricGoal(
                    kindRaw: $0.kindRaw,
                    targetValue: $0.targetValue,
                    directionRaw: $0.directionRaw,
                    createdDate: $0.createdDate,
                    startValue: $0.startValue,
                    startDate: $0.startDate
                )
            }
            try writeEncrypted(codableGoals, to: packageURL.appendingPathComponent("goals.json"), key: key)

            // Serialize photos index and write image files
            var codablePhotos: [CodablePhotoEntry] = []
            for photo in photos {
                let fileID = UUID().uuidString
                try photo.imageData.write(to: photosDir.appendingPathComponent("\(fileID).dat"))
                if let thumb = photo.thumbnailData {
                    try thumb.write(to: photosDir.appendingPathComponent("\(fileID)_thumb.dat"))
                }
                codablePhotos.append(CodablePhotoEntry(
                    fileID: fileID,
                    date: photo.date,
                    tags: photo.tags.map(\.rawValue),
                    linkedMetrics: photo.linkedMetrics.map {
                        CodableLinkedMetric(metricRawValue: $0.metricRawValue, value: $0.value, unit: $0.unit)
                    },
                    hasThumbnail: photo.thumbnailData != nil
                ))
            }
            try writeEncrypted(codablePhotos, to: packageURL.appendingPathComponent("photos_index.json"), key: key)

            // Serialize settings
            let settingsEntries = captureSettings()
            try writeEncrypted(settingsEntries, to: packageURL.appendingPathComponent("settings.json"), key: key)

            // Write manifest (plaintext)
            let manifest = ICloudBackupManifest(
                schemaVersion: currentSchemaVersion,
                createdAt: timestamp,
                metricsCount: metrics.count,
                goalsCount: goals.count,
                photosCount: photos.count,
                settingsCount: settingsEntries.count,
                isEncrypted: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))

            // Retention
            try enforceRetention(in: rootURL)

            // Calculate backup size
            let backupSize = directorySize(packageURL)
            AppSettingsStore.shared.set(\.iCloudBackup.lastBackupSizeBytes, backupSize)

            // Update settings
            AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, timestamp.timeIntervalSince1970)
            AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")

            let manifestWithSize = ICloudBackupManifest(
                schemaVersion: currentSchemaVersion,
                createdAt: timestamp,
                metricsCount: metrics.count,
                goalsCount: goals.count,
                photosCount: photos.count,
                settingsCount: settingsEntries.count,
                isEncrypted: true,
                sizeBytes: backupSize
            )

            return .success(manifestWithSize)
        } catch {
            let message = error.localizedDescription
            AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, message)
            return .failure(.fileSystemError(message))
        }
    }

    static func restoreLatestBackupManually(
        context: ModelContext,
        isPremium: Bool
    ) async -> Result<Void, BackupError> {
        guard isPremium else { return .failure(.premiumRequired) }

        guard let rootURL = backupRootURL() else {
            return .failure(.fileSystemError("iCloud container unavailable"))
        }

        guard let key = encryptionKey() else {
            return .failure(.encryptionError)
        }

        guard let latestPackage = latestBackupPackage(in: rootURL) else {
            return .failure(.noBackupFound)
        }

        return await restoreFromPackage(latestPackage, context: context, key: key)
    }

    static func restoreLatestBackupIfNeededOnStartup(context: ModelContext) async -> Bool {
        let settings = AppSettingsStore.shared.snapshot.iCloudBackup
        guard !settings.autoRestoreCompleted else { return false }

        let sampleCount = (try? context.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
        guard sampleCount == 0 else { return false }

        guard let rootURL = backupRootURL(),
              let key = encryptionKey(),
              let latestPackage = latestBackupPackage(in: rootURL) else {
            return false
        }

        let result = await restoreFromPackage(latestPackage, context: context, key: key)
        if case .success = result {
            AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, true)
            return true
        }
        return false
    }

    static func runScheduledBackupIfNeeded(context: ModelContext, isPremium: Bool) async {
        let settings = AppSettingsStore.shared.snapshot.iCloudBackup
        guard settings.isEnabled else { return }

        let lastSuccess = Date(timeIntervalSince1970: settings.lastSuccessTimestamp)
        let elapsed = now().timeIntervalSince(lastSuccess)
        guard elapsed >= scheduledBackupInterval else { return }

        _ = await createBackupNow(context: context, isPremium: isPremium)
    }

    /// Returns the manifest of the latest backup without performing a restore.
    /// Use this to display backup details before the user confirms a destructive restore.
    static func preflightRestore(
        context: ModelContext,
        isPremium: Bool
    ) async -> Result<ICloudBackupManifest, BackupError> {
        guard isPremium else { return .failure(.premiumRequired) }

        guard let rootURL = backupRootURL() else {
            return .failure(.fileSystemError("iCloud container unavailable"))
        }

        guard let latestPackage = latestBackupPackage(in: rootURL) else {
            return .failure(.noBackupFound)
        }

        do {
            let manifestURL = latestPackage.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(ICloudBackupManifest.self, from: manifestData)
            return .success(manifest)
        } catch {
            return .failure(.fileSystemError(error.localizedDescription))
        }
    }

    // MARK: - Restore helper

    private static func restoreFromPackage(
        _ packageURL: URL,
        context: ModelContext,
        key: SymmetricKey
    ) async -> Result<Void, BackupError> {
        do {
            // Read and validate manifest
            let manifestURL = packageURL.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(ICloudBackupManifest.self, from: manifestData)

            guard manifest.schemaVersion == currentSchemaVersion else {
                return .failure(.invalidBackupSchema)
            }

            // Decrypt all data before modifying the store
            let metrics: [CodableMetricSample] = try readEncrypted(
                from: packageURL.appendingPathComponent("metrics.json"), key: key
            )
            let goals: [CodableMetricGoal] = try readEncrypted(
                from: packageURL.appendingPathComponent("goals.json"), key: key
            )
            let photoEntries: [CodablePhotoEntry] = try readEncrypted(
                from: packageURL.appendingPathComponent("photos_index.json"), key: key
            )
            let settingsEntries: [SettingsEntry] = try readEncrypted(
                from: packageURL.appendingPathComponent("settings.json"), key: key
            )

            let photosDir = packageURL.appendingPathComponent("photos", isDirectory: true)

            // Delete existing data
            try deleteAll(MetricSample.self, from: context)
            try deleteAll(MetricGoal.self, from: context)
            try deleteAll(PhotoEntry.self, from: context)

            // Restore metrics
            for m in metrics {
                context.insert(MetricSample(kind: MetricKind(rawValue: m.kindRaw) ?? .weight, value: m.value, date: m.date))
            }

            // Restore goals
            for g in goals {
                context.insert(MetricGoal(
                    kind: MetricKind(rawValue: g.kindRaw) ?? .weight,
                    targetValue: g.targetValue,
                    direction: MetricGoal.Direction(rawValue: g.directionRaw) ?? .decrease,
                    createdDate: g.createdDate,
                    startValue: g.startValue,
                    startDate: g.startDate
                ))
            }

            // Restore photos
            for p in photoEntries {
                let imageURL = photosDir.appendingPathComponent("\(p.fileID).dat")
                let imageData = try Data(contentsOf: imageURL)

                var thumbnailData: Data?
                if p.hasThumbnail {
                    let thumbURL = photosDir.appendingPathComponent("\(p.fileID)_thumb.dat")
                    thumbnailData = try? Data(contentsOf: thumbURL)
                }

                let tags = p.tags.compactMap { PhotoTag(rawValue: $0) }
                let linked = p.linkedMetrics.map {
                    MetricValueSnapshot(metricRawValue: $0.metricRawValue, value: $0.value, unit: $0.unit)
                }

                context.insert(PhotoEntry(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    date: p.date,
                    tags: tags,
                    linkedMetrics: linked
                ))
            }

            try context.save()

            // Restore settings
            restoreSettings(settingsEntries)

            AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")

            return .success(())
        } catch {
            return .failure(.fileSystemError(error.localizedDescription))
        }
    }

    // MARK: - Encryption

    private static func writeEncrypted<T: Encodable>(_ value: T, to url: URL, key: SymmetricKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(value)
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        try sealed.combined.write(to: url)
    }

    private static func readEncrypted<T: Decodable>(from url: URL, key: SymmetricKey) throws -> T {
        let combined = try Data(contentsOf: url)
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        let plaintext = try ChaChaPoly.open(sealedBox, using: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: plaintext)
    }

    // MARK: - Encryption key management

    private static func encryptionKey() -> SymmetricKey? {
        if let override = testEncryptionKeyOverride { return override }
        return loadOrCreateKeychainKey()
    }

    private static func loadOrCreateKeychainKey() -> SymmetricKey? {
        // Try to read existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jacek.measureme.icloud-backup",
            kSecAttrAccount as String: "encryption-key",
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }

        // Generate and store new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jacek.measureme.icloud-backup",
            kSecAttrAccount as String: "encryption-key",
            kSecValueData as String: keyData,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { return nil }

        return newKey
    }

    // MARK: - Backup discovery & retention

    private static func backupRootURL() -> URL? {
        if let override = testBackupRootURLOverride { return override }
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jacek.measureme")?
            .appendingPathComponent("Documents/Backups", isDirectory: true)
    }

    private static func now() -> Date {
        testNowOverride?() ?? Date()
    }

    private static func allBackupPackages(in rootURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == backupExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func latestBackupPackage(in rootURL: URL) -> URL? {
        allBackupPackages(in: rootURL).last
    }

    private static func enforceRetention(in rootURL: URL) throws {
        let packages = allBackupPackages(in: rootURL)
        guard packages.count > maxRetainedBackups else { return }

        let toDelete = packages.prefix(packages.count - maxRetainedBackups)
        for url in toDelete {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Directory size

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Model deletion helper

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, from context: ModelContext) throws {
        try context.delete(model: type)
    }

    // MARK: - Settings backup

    private static let backupSettingsKeys: [String] = [
        AppSettingsKeys.Profile.userName,
        AppSettingsKeys.Profile.userAge,
        AppSettingsKeys.Profile.userGender,
        AppSettingsKeys.Profile.manualHeight,
        AppSettingsKeys.Profile.unitsSystem,
        AppSettingsKeys.Home.showLastPhotosOnHome,
        AppSettingsKeys.Home.showMeasurementsOnHome,
        AppSettingsKeys.Home.showHealthMetricsOnHome,
        AppSettingsKeys.Home.showStreakOnHome,
        AppSettingsKeys.Home.homePinnedAction,
        AppSettingsKeys.Home.homeLayoutSchemaVersion,
        AppSettingsKeys.Home.homeLayoutData,
        AppSettingsKeys.Onboarding.hasCompletedOnboarding,
        AppSettingsKeys.Experience.animationsEnabled,
        AppSettingsKeys.Experience.hapticsEnabled,
        AppSettingsKeys.Experience.appLanguage,
        AppSettingsKeys.Experience.saveUnchangedQuickAdd,
        AppSettingsKeys.Indicators.showWHtROnHome,
        AppSettingsKeys.Indicators.showRFMOnHome,
        AppSettingsKeys.Indicators.showBMIOnHome,
        AppSettingsKeys.Indicators.showBodyFatOnHome,
        AppSettingsKeys.Indicators.showLeanMassOnHome,
        AppSettingsKeys.Indicators.showWHROnHome,
        AppSettingsKeys.Indicators.showWaistRiskOnHome,
        AppSettingsKeys.Indicators.showABSIOnHome,
        AppSettingsKeys.Indicators.showBodyShapeScoreOnHome,
        AppSettingsKeys.Indicators.showCentralFatRiskOnHome,
        AppSettingsKeys.Indicators.showConicityOnHome,
        AppSettingsKeys.Indicators.showPhysiqueSWR,
        AppSettingsKeys.Indicators.showPhysiqueCWR,
        AppSettingsKeys.Indicators.showPhysiqueSHR,
        AppSettingsKeys.Indicators.showPhysiqueHWR,
        AppSettingsKeys.Indicators.showPhysiqueBWR,
        AppSettingsKeys.Indicators.showPhysiqueWHtR,
        AppSettingsKeys.Indicators.showPhysiqueBodyFat,
        AppSettingsKeys.Indicators.showPhysiqueRFM,
        AppSettingsKeys.Notifications.reminders,
        AppSettingsKeys.Notifications.notificationsEnabled,
        AppSettingsKeys.Notifications.smartEnabled,
        AppSettingsKeys.Notifications.smartDays,
        AppSettingsKeys.Notifications.smartTime,
        AppSettingsKeys.Notifications.photoRemindersEnabled,
        AppSettingsKeys.Notifications.goalAchievedEnabled,
        AppSettingsKeys.Notifications.importNotificationsEnabled,
        AppSettingsKeys.Analytics.analyticsEnabled,
        AppSettingsKeys.Analytics.appleIntelligenceEnabled,
        AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled,
    ] + AppSettingsKeys.Metrics.allEnabledKeys

    private static func captureSettings() -> [SettingsEntry] {
        let store = AppSettingsStore.shared
        var entries: [SettingsEntry] = []

        for key in backupSettingsKeys {
            guard let value = store.object(forKey: key) else { continue }

            if let s = value as? String {
                entries.append(SettingsEntry(key: key, type: .string, stringValue: s, numberValue: nil, boolValue: nil, dataValue: nil))
            } else if let b = value as? Bool {
                entries.append(SettingsEntry(key: key, type: .bool, stringValue: nil, numberValue: nil, boolValue: b, dataValue: nil))
            } else if let i = value as? Int {
                entries.append(SettingsEntry(key: key, type: .int, stringValue: nil, numberValue: Double(i), boolValue: nil, dataValue: nil))
            } else if let d = value as? Double {
                entries.append(SettingsEntry(key: key, type: .double, stringValue: nil, numberValue: d, boolValue: nil, dataValue: nil))
            } else if let data = value as? Data {
                entries.append(SettingsEntry(key: key, type: .data, stringValue: nil, numberValue: nil, boolValue: nil, dataValue: data))
            }
        }

        return entries
    }

    private static func restoreSettings(_ entries: [SettingsEntry]) {
        let store = AppSettingsStore.shared
        for entry in entries {
            switch entry.type {
            case .string:
                store.set(entry.stringValue, forKey: entry.key)
            case .bool:
                store.set(entry.boolValue, forKey: entry.key)
            case .int:
                if let n = entry.numberValue { store.set(Int(n), forKey: entry.key) }
            case .double:
                store.set(entry.numberValue, forKey: entry.key)
            case .data:
                store.set(entry.dataValue, forKey: entry.key)
            }
        }
    }

    // MARK: - Codable transport types

    private struct CodableMetricSample: Codable {
        let kindRaw: String
        let value: Double
        let date: Date
    }

    private struct CodableMetricGoal: Codable {
        let kindRaw: String
        let targetValue: Double
        let directionRaw: String
        let createdDate: Date
        let startValue: Double?
        let startDate: Date?
    }

    private struct CodablePhotoEntry: Codable {
        let fileID: String
        let date: Date
        let tags: [String]
        let linkedMetrics: [CodableLinkedMetric]
        let hasThumbnail: Bool
    }

    private struct CodableLinkedMetric: Codable {
        let metricRawValue: String
        let value: Double
        let unit: String
    }

    struct SettingsEntry: Codable {
        let key: String
        let type: ValueType
        let stringValue: String?
        let numberValue: Double?
        let boolValue: Bool?
        let dataValue: Data?

        enum ValueType: String, Codable {
            case string, int, double, bool, data
        }
    }
}
