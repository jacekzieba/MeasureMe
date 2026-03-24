import Foundation
import SwiftData
import CryptoKit

enum ICloudBackupService {
    private struct StoredBackupManifest: Codable, Sendable {
        let schemaVersion: Int
        let createdAt: Date
        let isEncrypted: Bool
    }

    private actor RestoreCoordinator {
        private var isRestoring = false

        func beginRestore() -> Bool {
            guard !isRestoring else { return false }
            isRestoring = true
            return true
        }

        func endRestore() {
            isRestoring = false
        }
    }

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
                return AppLocalization.string("Could not access iCloud backup right now.")
            case .fileSystemError(let detail):
                if detail.contains("iCloud container unavailable") {
                    return AppLocalization.string("iCloud Drive is unavailable on this device.")
                }
                return AppLocalization.string("Could not access iCloud backup right now.")
            }
        }
    }

    // MARK: - Test overrides

    nonisolated(unsafe) static var testBackupRootURLOverride: URL?
    nonisolated(unsafe) static var testNowOverride: (() -> Date)?
    nonisolated(unsafe) static var testEncryptionKeyOverride: SymmetricKey?

    static func resetTestOverrides() {
        testBackupRootURLOverride = nil
        testNowOverride = nil
        testEncryptionKeyOverride = nil
    }

    // MARK: - Constants

    private nonisolated static let currentSchemaVersion = 1
    private nonisolated static let maxRetainedBackups = 7
    private nonisolated static let scheduledBackupInterval: TimeInterval = 86_400 // 24 hours
    private nonisolated static let backupExtension = "measuremebackup"
    private nonisolated static let photoBackupBatchSize = 100
    private static let restoreCoordinator = RestoreCoordinator()

    // MARK: - Public API

    static func createBackupNow(
        context: ModelContext,
        isPremium: Bool
    ) async -> Result<ICloudBackupManifest, BackupError> {
        guard isPremium else { return .failure(.premiumRequired) }
        let isEnabled = await MainActor.run { AppSettingsStore.shared.snapshot.iCloudBackup.isEnabled }
        guard isEnabled else { return .failure(.backupDisabled) }

        guard let rootURL = backupRootURL() else {
            return .failure(.fileSystemError("iCloud container unavailable"))
        }

        guard let key = encryptionKey() else {
            return .failure(.encryptionError)
        }

        let tempPhotosDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("measureme-backup-\(UUID().uuidString)", isDirectory: true)

        do {
            let metrics = try context.fetch(FetchDescriptor<MetricSample>())
            let goals = try context.fetch(FetchDescriptor<MetricGoal>())
            let codableMetrics = metrics.map {
                CodableMetricSample(kindRaw: $0.kindRaw, value: $0.value, date: $0.date, sourceRaw: $0.sourceRaw)
            }
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

            // Stream-write photos to a temp directory one at a time to avoid OOM.
            // Only one photo's imageData is in memory at any point.
            try FileManager.default.createDirectory(at: tempPhotosDir, withIntermediateDirectories: true)

            var codablePhotos: [CodablePhotoEntry] = []
            var photosCount = 0
            var photosOffset = 0

            while true {
                var photoDescriptor = FetchDescriptor<PhotoEntry>(
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
                photoDescriptor.fetchLimit = Self.photoBackupBatchSize
                photoDescriptor.fetchOffset = photosOffset
                let photosBatch = try context.fetch(photoDescriptor)
                guard !photosBatch.isEmpty else { break }

                for photo in photosBatch {
                    let fileID = UUID().uuidString
                    codablePhotos.append(CodablePhotoEntry(
                        fileID: fileID,
                        date: photo.date,
                        tags: photo.tags.map(\.rawValue),
                        linkedMetrics: photo.linkedMetrics.map {
                            CodableLinkedMetric(metricRawValue: $0.metricRawValue, value: $0.value, unit: $0.unit)
                        },
                        hasThumbnail: photo.thumbnailData != nil
                    ))
                    try Self.writeEncryptedData(photo.imageData, to: tempPhotosDir.appendingPathComponent("\(fileID).dat"), key: key)
                    if let thumb = photo.thumbnailData {
                        try Self.writeEncryptedData(thumb, to: tempPhotosDir.appendingPathComponent("\(fileID)_thumb.dat"), key: key)
                    }
                }
                photosCount += photosBatch.count
                photosOffset += photosBatch.count
            }
            let settingsEntries = await MainActor.run { captureSettings() }
            let manifest = ICloudBackupManifest(
                schemaVersion: currentSchemaVersion,
                createdAt: now(),
                metricsCount: metrics.count,
                goalsCount: goals.count,
                photosCount: photosCount,
                settingsCount: settingsEntries.count,
                isEncrypted: true
            )
            let timestamp = manifest.createdAt

            let backupFileExtension = Self.backupExtension

            let manifestData = try encodeStoredManifest(
                StoredBackupManifest(
                    schemaVersion: manifest.schemaVersion,
                    createdAt: manifest.createdAt,
                    isEncrypted: manifest.isEncrypted
                )
            )

            let backupSize = try await Task.detached(priority: .utility) { () -> Int64 in
                let fm = FileManager.default
                try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

                let stamp = Int(timestamp.timeIntervalSince1970)
                let wipName = "backup-\(stamp).\(backupFileExtension)-wip"
                let packageURL = rootURL.appendingPathComponent(wipName, isDirectory: true)
                try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

                // Move pre-written encrypted photos into the WIP package
                let photosDir = packageURL.appendingPathComponent("photos", isDirectory: true)
                try fm.moveItem(at: tempPhotosDir, to: photosDir)

                try Self.writeEncrypted(codableMetrics, to: packageURL.appendingPathComponent("metrics.json"), key: key)
                try Self.writeEncrypted(codableGoals, to: packageURL.appendingPathComponent("goals.json"), key: key)
                try Self.writeEncrypted(codablePhotos, to: packageURL.appendingPathComponent("photos_index.json"), key: key)
                try Self.writeEncrypted(settingsEntries, to: packageURL.appendingPathComponent("settings.json"), key: key)

                try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))

                // Atomically rename from WIP to final extension
                let finalName = "backup-\(stamp).\(backupFileExtension)"
                let finalURL = rootURL.appendingPathComponent(finalName, isDirectory: true)
                try fm.moveItem(at: packageURL, to: finalURL)

                try Self.enforceRetention(in: rootURL)
                return Self.directorySize(finalURL)
            }.value

            await MainActor.run {
                AppSettingsStore.shared.set(\.iCloudBackup.lastBackupSizeBytes, backupSize)
                AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, timestamp.timeIntervalSince1970)
                AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")
            }

            let manifestWithSize = ICloudBackupManifest(
                schemaVersion: currentSchemaVersion,
                createdAt: timestamp,
                metricsCount: metrics.count,
                goalsCount: goals.count,
                photosCount: photosCount,
                settingsCount: settingsEntries.count,
                isEncrypted: true,
                sizeBytes: backupSize
            )

            return .success(manifestWithSize)
        } catch {
            // Clean up temp photos dir if it was created but backup failed
            try? FileManager.default.removeItem(at: tempPhotosDir)
            let message = userFacingErrorMessage(for: error)
            await MainActor.run {
                AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, message)
            }
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
        let snapshot = await MainActor.run { AppSettingsStore.shared.snapshot }
        let settings = snapshot.iCloudBackup
        let onboarding = snapshot.onboarding
        let hasPremium = snapshot.premium.premiumEntitlement

        guard hasPremium else { return false }
        guard onboarding.onboardingViewedICloudBackupOffer else { return false }
        guard settings.isEnabled else { return false }
        guard !settings.autoRestoreCompleted else { return false }
        guard await restoreCoordinator.beginRestore() else { return false }

        guard isStoreEmpty(context: context) else {
            await restoreCoordinator.endRestore()
            return false
        }

        guard let rootURL = backupRootURL(),
              let key = encryptionKey(),
              let latestPackage = latestBackupPackage(in: rootURL) else {
            await restoreCoordinator.endRestore()
            return false
        }

        let result = await restoreFromPackage(latestPackage, context: context, key: key)
        await restoreCoordinator.endRestore()
        if case .success = result {
            await MainActor.run {
                AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, true)
            }
            return true
        }
        return false
    }

    static func runScheduledBackupIfNeeded(context: ModelContext, isPremium: Bool) async {
        let (isEnabled, lastSuccessTimestamp): (Bool, Double) = await MainActor.run {
            let s = AppSettingsStore.shared.snapshot.iCloudBackup
            return (s.isEnabled, s.lastSuccessTimestamp)
        }
        guard isPremium else { return }
        guard isEnabled else { return }

        let lastSuccess = Date(timeIntervalSince1970: lastSuccessTimestamp)
        let elapsed = now().timeIntervalSince(lastSuccess)
        guard elapsed >= scheduledBackupInterval else { return }

        _ = await createBackupNow(context: context, isPremium: isPremium)
    }

    /// Returns the manifest of the latest backup without performing a restore.
    /// Use this to display backup details before the user confirms a destructive restore.
    static func preflightRestore(
        context _: ModelContext,
        isPremium: Bool
    ) async -> Result<ICloudBackupManifest, BackupError> {
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

        do {
            let manifestURL = latestPackage.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try decodeStoredManifest(from: manifestData)
            let summary = try await loadManifestSummary(
                packageURL: latestPackage,
                key: key,
                storedManifest: manifest
            )
            return .success(summary)
        } catch {
            return .failure(.fileSystemError(userFacingErrorMessage(for: error)))
        }
    }

    // MARK: - Restore helper

    private static func restoreFromPackage(
        _ packageURL: URL,
        context: ModelContext,
        key: SymmetricKey
    ) async -> Result<Void, BackupError> {
        do {
            let manifestURL = packageURL.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try decodeStoredManifest(from: manifestData)
            guard manifest.schemaVersion == currentSchemaVersion else {
                return .failure(.invalidBackupSchema)
            }

            let payload = try await Task.detached(priority: .utility) { () -> RestorePayload in
                let metrics: [CodableMetricSample] = try Self.readEncrypted(
                    from: packageURL.appendingPathComponent("metrics.json"), key: key
                )
                let goals: [CodableMetricGoal] = try Self.readEncrypted(
                    from: packageURL.appendingPathComponent("goals.json"), key: key
                )
                let photoEntries: [CodablePhotoEntry] = try Self.readEncrypted(
                    from: packageURL.appendingPathComponent("photos_index.json"), key: key
                )
                let settingsEntries: [SettingsEntry] = try Self.readEncrypted(
                    from: packageURL.appendingPathComponent("settings.json"), key: key
                )

                return RestorePayload(
                    metrics: metrics,
                    goals: goals,
                    photoEntries: photoEntries,
                    settingsEntries: settingsEntries
                )
            }.value

            // Validate payload before deleting existing data — reject fully corrupt backups
            let validMetricCount = payload.metrics.filter { MetricKind(rawValue: $0.kindRaw) != nil }.count
            let validGoalCount = payload.goals.filter {
                MetricKind(rawValue: $0.kindRaw) != nil && MetricGoal.Direction(rawValue: $0.directionRaw) != nil
            }.count
            let totalRestorableItems = validMetricCount + validGoalCount + payload.photoEntries.count
            let totalPayloadItems = payload.metrics.count + payload.goals.count + payload.photoEntries.count

            if totalRestorableItems == 0 && totalPayloadItems > 0 {
                return .failure(.invalidBackupSchema)
            }

            // Snapshot existing metrics & goals for rollback (lightweight — no image data)
            let existingMetrics = try context.fetch(FetchDescriptor<MetricSample>())
            let existingGoals = try context.fetch(FetchDescriptor<MetricGoal>())

            let snapshotMetrics = existingMetrics.map {
                CodableMetricSample(kindRaw: $0.kindRaw, value: $0.value, date: $0.date, sourceRaw: $0.sourceRaw)
            }
            let snapshotGoals = existingGoals.map {
                CodableMetricGoal(
                    kindRaw: $0.kindRaw,
                    targetValue: $0.targetValue,
                    directionRaw: $0.directionRaw,
                    createdDate: $0.createdDate,
                    startValue: $0.startValue,
                    startDate: $0.startDate
                )
            }

            // Phase 1: Restore metrics & goals (small data, supports rollback)
            try deleteAll(MetricSample.self, from: context)
            try deleteAll(MetricGoal.self, from: context)
            try deleteAll(PhotoEntry.self, from: context)

            for m in payload.metrics {
                guard let kind = MetricKind(rawValue: m.kindRaw) else { continue }
                let source = MetricSampleSource(rawValue: m.sourceRaw ?? "") ?? .manual
                context.insert(MetricSample(kind: kind, value: m.value, date: m.date, source: source))
            }

            for g in payload.goals {
                guard let kind = MetricKind(rawValue: g.kindRaw) else { continue }
                guard let direction = MetricGoal.Direction(rawValue: g.directionRaw) else { continue }
                context.insert(MetricGoal(
                    kind: kind,
                    targetValue: g.targetValue,
                    direction: direction,
                    createdDate: g.createdDate,
                    startValue: g.startValue,
                    startDate: g.startDate
                ))
            }

            do {
                try context.save()
            } catch {
                // Rollback metrics & goals only
                try? deleteAll(MetricSample.self, from: context)
                try? deleteAll(MetricGoal.self, from: context)
                for m in snapshotMetrics {
                    if let kind = MetricKind(rawValue: m.kindRaw) {
                        let source = MetricSampleSource(rawValue: m.sourceRaw ?? "") ?? .manual
                        context.insert(MetricSample(kind: kind, value: m.value, date: m.date, source: source))
                    }
                }
                for g in snapshotGoals {
                    if let kind = MetricKind(rawValue: g.kindRaw),
                       let dir = MetricGoal.Direction(rawValue: g.directionRaw) {
                        context.insert(MetricGoal(
                            kind: kind,
                            targetValue: g.targetValue,
                            direction: dir,
                            createdDate: g.createdDate,
                            startValue: g.startValue,
                            startDate: g.startDate
                        ))
                    }
                }
                try? context.save()
                throw error
            }

            // Phase 2: Restore photos in batches to limit memory usage
            let photosDir = packageURL.appendingPathComponent("photos", isDirectory: true)
            let photoBatchSize = 10
            let photoChunks = stride(from: 0, to: payload.photoEntries.count, by: photoBatchSize).map {
                Array(payload.photoEntries[$0 ..< min($0 + photoBatchSize, payload.photoEntries.count)])
            }

            for batch in photoChunks {
                try autoreleasepool {
                    let restoredBatch: [RestoredPhotoEntry] = try batch.map { entry in
                        let imageURL = photosDir.appendingPathComponent("\(entry.fileID).dat")
                        let imageData = try Self.readEncryptedData(from: imageURL, key: key)

                        var thumbnailData: Data?
                        if entry.hasThumbnail {
                            let thumbURL = photosDir.appendingPathComponent("\(entry.fileID)_thumb.dat")
                            thumbnailData = try Self.readEncryptedData(from: thumbURL, key: key)
                        }

                        return RestoredPhotoEntry(
                            imageData: imageData,
                            thumbnailData: thumbnailData,
                            date: entry.date,
                            tagRawValues: entry.tags,
                            linkedMetrics: entry.linkedMetrics
                        )
                    }

                    for photo in restoredBatch {
                        context.insert(PhotoEntry(
                            imageData: photo.imageData,
                            thumbnailData: photo.thumbnailData,
                            date: photo.date,
                            tags: photo.tagRawValues.compactMap(PhotoTag.init(rawValue:)),
                            linkedMetrics: photo.linkedMetrics.map {
                                MetricValueSnapshot(metricRawValue: $0.metricRawValue, value: $0.value, unit: $0.unit)
                            }
                        ))
                    }

                    try context.save()
                }
            }

            await MainActor.run { restoreSettings(payload.settingsEntries) }
            await MainActor.run {
                AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")
            }
            return .success(())
        } catch let error as BackupError {
            return .failure(error)
        } catch {
            return .failure(.fileSystemError(userFacingErrorMessage(for: error)))
        }
    }

    // MARK: - Encryption

    private static func encodeStoredManifest(_ manifest: StoredBackupManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    private static func decodeStoredManifest(from data: Data) throws -> StoredBackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredBackupManifest.self, from: data)
    }

    private static func loadManifestSummary(
        packageURL: URL,
        key: SymmetricKey,
        storedManifest: StoredBackupManifest
    ) async throws -> ICloudBackupManifest {
        try await Task.detached(priority: .utility) {
            let metrics: [CodableMetricSample] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("metrics.json"), key: key
            )
            let goals: [CodableMetricGoal] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("goals.json"), key: key
            )
            let photos: [CodablePhotoEntry] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("photos_index.json"), key: key
            )
            let settings: [SettingsEntry] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("settings.json"), key: key
            )

            return ICloudBackupManifest(
                schemaVersion: storedManifest.schemaVersion,
                createdAt: storedManifest.createdAt,
                metricsCount: metrics.count,
                goalsCount: goals.count,
                photosCount: photos.count,
                settingsCount: settings.count,
                isEncrypted: storedManifest.isEncrypted,
                sizeBytes: Self.directorySize(packageURL)
            )
        }.value
    }

    private nonisolated static func writeEncrypted<T: Encodable>(_ value: T, to url: URL, key: SymmetricKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(value)
        try writeEncryptedData(plaintext, to: url, key: key)
    }

    private nonisolated static func readEncrypted<T: Decodable>(from url: URL, key: SymmetricKey) throws -> T {
        let plaintext = try readEncryptedData(from: url, key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: plaintext)
    }

    private nonisolated static func writeEncryptedData(_ data: Data, to url: URL, key: SymmetricKey) throws {
        let sealed = try ChaChaPoly.seal(data, using: key)
        try sealed.combined.write(to: url)
    }

    private nonisolated static func readEncryptedData(from url: URL, key: SymmetricKey) throws -> Data {
        let combined = try Data(contentsOf: url)
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(sealedBox, using: key)
    }

    // MARK: - Encryption key management

    private static func encryptionKey() -> SymmetricKey? {
        if let override = testEncryptionKeyOverride { return override }
        return loadOrCreateKeychainKey()
    }

    private static let keychainLock = NSLock()

    private static func loadOrCreateKeychainKey() -> SymmetricKey? {
        keychainLock.lock()
        defer { keychainLock.unlock() }

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
        if addStatus == errSecSuccess {
            return newKey
        } else if addStatus == errSecDuplicateItem {
            // Key was synced via iCloud Keychain between read and add — retry read
            var retryResult: AnyObject?
            let retryStatus = SecItemCopyMatching(query as CFDictionary, &retryResult)
            if retryStatus == errSecSuccess, let data = retryResult as? Data {
                return SymmetricKey(data: data)
            }
        }

        return nil
    }

    // MARK: - Backup discovery & retention

    private nonisolated static func backupRootURL() -> URL? {
        if let override = testBackupRootURLOverride { return override }
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jacek.measureme")?
            .appendingPathComponent("Documents/Backups", isDirectory: true)
    }

    private nonisolated static func now() -> Date {
        testNowOverride?() ?? Date()
    }

    private nonisolated static func allBackupPackages(in rootURL: URL) -> [URL] {
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

    private nonisolated static func latestBackupPackage(in rootURL: URL) -> URL? {
        allBackupPackages(in: rootURL).last
    }

    private nonisolated static func isStoreEmpty(context: ModelContext) -> Bool {
        let sampleCount = (try? context.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
        let goalCount = (try? context.fetchCount(FetchDescriptor<MetricGoal>())) ?? 0
        let photoCount = (try? context.fetchCount(FetchDescriptor<PhotoEntry>())) ?? 0
        return sampleCount == 0 && goalCount == 0 && photoCount == 0
    }

    private nonisolated static func enforceRetention(in rootURL: URL) throws {
        let packages = allBackupPackages(in: rootURL)
        guard packages.count > maxRetainedBackups else { return }

        let toDelete = packages.prefix(packages.count - maxRetainedBackups)
        for url in toDelete {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Directory size

    private nonisolated static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Model deletion helper

    private nonisolated static func deleteAll<T: PersistentModel>(_ type: T.Type, from context: ModelContext) throws {
        try context.delete(model: type)
    }

    // MARK: - Settings backup

    @MainActor private static func captureSettings() -> [SettingsEntry] {
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

    @MainActor private static func restoreSettings(_ entries: [SettingsEntry]) {
        let store = AppSettingsStore.shared
        for entry in entries {
            switch entry.type {
            case .string:
                if let value = entry.stringValue {
                    store.set(value, forKey: entry.key)
                } else {
                    store.removeObject(forKey: entry.key)
                }
            case .bool:
                if let value = entry.boolValue {
                    store.set(value, forKey: entry.key)
                } else {
                    store.removeObject(forKey: entry.key)
                }
            case .int:
                if let value = entry.numberValue {
                    store.set(Int(value), forKey: entry.key)
                } else {
                    store.removeObject(forKey: entry.key)
                }
            case .double:
                if let value = entry.numberValue {
                    store.set(value, forKey: entry.key)
                } else {
                    store.removeObject(forKey: entry.key)
                }
            case .data:
                if let value = entry.dataValue {
                    store.set(value, forKey: entry.key)
                } else {
                    store.removeObject(forKey: entry.key)
                }
            }
        }
        store.reload()
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        if let backupError = error as? BackupError {
            return backupError.localizedMessage
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return AppLocalization.string("iCloud storage is full. Free up space in Settings → iCloud to continue backups.")
        }
        return AppLocalization.string("Could not access iCloud backup right now.")
    }

    // MARK: - Codable transport types

    private struct CodableMetricSample: Codable, Sendable {
        let kindRaw: String
        let value: Double
        let date: Date
        let sourceRaw: String?
    }

    private struct CodableMetricGoal: Codable, Sendable {
        let kindRaw: String
        let targetValue: Double
        let directionRaw: String
        let createdDate: Date
        let startValue: Double?
        let startDate: Date?
    }

    private struct CodablePhotoEntry: Codable, Sendable {
        let fileID: String
        let date: Date
        let tags: [String]
        let linkedMetrics: [CodableLinkedMetric]
        let hasThumbnail: Bool
    }

    private struct CodableLinkedMetric: Codable, Sendable {
        let metricRawValue: String
        let value: Double
        let unit: String
    }

    private struct RestoredPhotoEntry: Sendable {
        let imageData: Data
        let thumbnailData: Data?
        let date: Date
        let tagRawValues: [String]
        let linkedMetrics: [CodableLinkedMetric]
    }

    private struct RestorePayload: Sendable {
        let metrics: [CodableMetricSample]
        let goals: [CodableMetricGoal]
        let photoEntries: [CodablePhotoEntry]
        let settingsEntries: [SettingsEntry]
    }

    struct SettingsEntry: Codable, Sendable {
        let key: String
        let type: ValueType
        let stringValue: String?
        let numberValue: Double?
        let boolValue: Bool?
        let dataValue: Data?

        enum ValueType: String, Codable, Sendable {
            case string, int, double, bool, data
        }
    }

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
}
