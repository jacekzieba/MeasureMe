import Foundation
import SwiftData
import CryptoKit

enum ICloudBackupService {
    private nonisolated struct StoredBackupManifest: Codable, Sendable {
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
        case encryptionKeyUnavailable
        case nothingToBackUp
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
            case .nothingToBackUp:
                return AppLocalization.string("There is nothing to back up yet, so your existing iCloud backups were left as they are.")
            case .encryptionKeyUnavailable:
                return AppLocalization.string("The key that unlocks your backups has not reached this device yet. Make sure iCloud Keychain is on, wait a few minutes and try again.")
            case .fileSystemError(let detail):
                if detail.contains("iCloud container unavailable") {
                    return AppLocalization.string("iCloud Drive is unavailable on this device.")
                }
                return AppLocalization.string("Could not access iCloud backup right now.")
            }
        }
    }

    // MARK: - Test overrides

#if DEBUG
    // These are DEBUG-only so they cannot race with production code.
    // XCTest mutates them serially from setUp/tearDown; concurrent release-time
    // access is impossible because the symbols don't exist in release builds.
    nonisolated(unsafe) static var testBackupRootURLOverride: URL?
    nonisolated(unsafe) static var testNowOverride: (() -> Date)?
    nonisolated(unsafe) static var testEncryptionKeyOverride: SymmetricKey?
    nonisolated(unsafe) static var testNotificationManagerOverride: NotificationManager?
    nonisolated(unsafe) static var testKeyStoreOverride: BackupKeyStore?

    static func resetTestOverrides() {
        testBackupRootURLOverride = nil
        testNowOverride = nil
        testEncryptionKeyOverride = nil
        testNotificationManagerOverride = nil
        testKeyStoreOverride = nil
    }
#endif

    // MARK: - Constants

    private nonisolated static let currentSchemaVersion = 1
    private nonisolated static let maxRetainedBackups = 7
    private nonisolated static let scheduledBackupInterval: TimeInterval = 86_400 // 24 hours
    private nonisolated static let backupExtension = "measuremebackup"
    /// Photos fetched and handed to a background task at a time: few enough to keep memory flat and
    /// the main actor free, since each hand-off gives it back to the UI.
    private nonisolated static let photoTransferChunkSize = 10
    private nonisolated static let staleWorkInProgressAge: TimeInterval = 3_600
    private static let restoreCoordinator = RestoreCoordinator()

    // MARK: - Public API

    static func createBackupNow(
        context: ModelContext,
        isPremium: Bool
    ) async -> Result<ICloudBackupManifest, BackupError> {
        await serialized { await performBackup(context: context, isPremium: isPremium) }
    }

    private static func performBackup(
        context: ModelContext,
        isPremium: Bool
    ) async -> Result<ICloudBackupManifest, BackupError> {
        guard isPremium else { return .failure(.premiumRequired) }
        let isEnabled = await MainActor.run { AppSettingsStore.shared.snapshot.iCloudBackup.isEnabled }
        guard isEnabled else { return .failure(.backupDisabled) }

        guard let rootURL = backupRootURL() else {
            return .failure(.fileSystemError("iCloud container unavailable"))
        }

        // A device that was never restored has an empty store; backing it up would make an empty backup
        // the latest — the one the next restore picks. The first backup may be empty: it hides nothing.
        if isStoreEmpty(context: context), !allBackupPackages(in: rootURL).isEmpty {
            return .failure(.nothingToBackUp)
        }

        guard let key = encryptionKeyCreatingIfNeeded() else {
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
                    startDate: $0.startDate,
                    commitmentWeeklyRate: $0.commitmentWeeklyRate
                )
            }
            let codableCustomMetrics = try context.fetch(FetchDescriptor<CustomMetricDefinition>()).map(CodableCustomMetric.init)

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
                photoDescriptor.fetchLimit = Self.photoTransferChunkSize
                photoDescriptor.fetchOffset = photosOffset
                let photosBatch = try context.fetch(photoDescriptor)
                guard !photosBatch.isEmpty else { break }

                // The background-task expiration handler cancels a backup that ran out of time.
                try Task.checkCancellation()
                var files: [PhotoFilePayload] = []
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
                    files.append(PhotoFilePayload(fileID: fileID, imageData: photo.imageData, thumbnailData: photo.thumbnailData))
                }
                // Encrypting and writing ran on the main actor with no suspension, freezing the UI for the
                // whole photo pass. Off the main actor, a batch at a time, the UI runs in between.
                try await Task.detached(priority: .utility) {
                    for file in files {
                        try Self.writeEncryptedData(file.imageData, to: tempPhotosDir.appendingPathComponent("\(file.fileID).dat"), key: key)
                        if let thumbnail = file.thumbnailData {
                            try Self.writeEncryptedData(thumbnail, to: tempPhotosDir.appendingPathComponent("\(file.fileID)_thumb.dat"), key: key)
                        }
                    }
                }.value
                photosCount += photosBatch.count
                photosOffset += photosBatch.count
            }
            let customMetricIDs = codableCustomMetrics.map(\.identifier)
            let settingsEntries = await MainActor.run { captureSettings(customMetricIDs: customMetricIDs) }
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

            try Task.checkCancellation()
            let backupSize = try await Task.detached(priority: .utility) { () -> Int64 in
                let fm = FileManager.default
                try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
                Self.removeStaleWorkInProgress(in: rootURL, now: timestamp)

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
                // Older builds fail the whole restore on an entry type they do not know, so list-valued
                // settings live in their own file and settings.json keeps to the original scalar types.
                try Self.writeEncrypted(
                    settingsEntries.filter { $0.type != .stringArray },
                    to: packageURL.appendingPathComponent("settings.json"), key: key
                )
                try Self.writeEncrypted(
                    settingsEntries.filter { $0.type == .stringArray },
                    to: packageURL.appendingPathComponent(Self.settingsListsFileName), key: key
                )
                try Self.writeEncrypted(codableCustomMetrics, to: packageURL.appendingPathComponent(Self.customMetricsFileName), key: key)

                try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))

                // Atomically rename from WIP to final extension
                let finalName = "backup-\(stamp).\(backupFileExtension)"
                let finalURL = rootURL.appendingPathComponent(finalName, isDirectory: true)
                try fm.moveItem(at: packageURL, to: finalURL)

                // The backup is complete at this point; failing to prune older ones must not report it as failed.
                Self.enforceRetention(in: rootURL)
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
            if error is CancellationError {
                // Not something the person needs to see; the next run tries again.
                return .failure(.fileSystemError("cancelled"))
            }
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

        guard let latestPackage = latestBackupPackage(in: rootURL) else {
            return .failure(.noBackupFound)
        }

        guard let key = existingEncryptionKey() else {
            return .failure(.encryptionKeyUnavailable)
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
              let latestPackage = latestBackupPackage(in: rootURL),
              let key = existingEncryptionKey() else {
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
        // Checked and run under one lock, so two triggers arriving together make one backup, not two.
        await serialized { await performScheduledBackupIfNeeded(context: context, isPremium: isPremium) }
    }

    private static func performScheduledBackupIfNeeded(context: ModelContext, isPremium: Bool) async {
        let (isEnabled, lastSuccessTimestamp): (Bool, Double) = await MainActor.run {
            let s = AppSettingsStore.shared.snapshot.iCloudBackup
            return (s.isEnabled, s.lastSuccessTimestamp)
        }
        guard isPremium else { return }
        guard isEnabled else { return }

        let lastSuccess = Date(timeIntervalSince1970: lastSuccessTimestamp)
        let elapsed = now().timeIntervalSince(lastSuccess)
        guard elapsed >= scheduledBackupInterval else { return }

        _ = await performBackup(context: context, isPremium: isPremium)
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

        guard let latestPackage = latestBackupPackage(in: rootURL) else {
            return .failure(.noBackupFound)
        }

        guard let key = existingEncryptionKey() else {
            return .failure(.encryptionKeyUnavailable)
        }

        do {
            let summary = try await loadManifestSummary(packageURL: latestPackage, key: key)
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
        await serialized { await performRestore(from: packageURL, context: context, key: key) }
    }

    private static func performRestore(
        from packageURL: URL,
        context: ModelContext,
        key: SymmetricKey
    ) async -> Result<Void, BackupError> {
        do {
            // Every read below goes through a coordinated read, which waits for iCloud to download the
            // file; asking for the whole package up front lets those downloads run side by side.
            try? FileManager.default.startDownloadingUbiquitousItem(at: packageURL)
            let manifest = try await Task.detached(priority: .utility) {
                try Self.decodeStoredManifest(
                    from: Self.readUbiquitousData(at: packageURL.appendingPathComponent("manifest.json"))
                )
            }.value
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
                let settingsEntries = try Self.readSettingsEntries(in: packageURL, key: key)
                // Backups from before custom metrics were saved have no such file: nil means
                // "leave the local definitions alone", an empty list means "the backup had none".
                let customMetricsURL = packageURL.appendingPathComponent(Self.customMetricsFileName)
                let customMetrics: [CodableCustomMetric]? = Self.ubiquitousItemExists(at: customMetricsURL)
                    ? try Self.readEncrypted(from: customMetricsURL, key: key)
                    : nil

                // Everything local is deleted below, so every photo must be known readable first — one
                // missing file used to surface only after the local photos were already gone.
                let photosDir = packageURL.appendingPathComponent("photos", isDirectory: true)
                for entry in photoEntries {
                    try autoreleasepool {
                        _ = try Self.readEncryptedData(from: photosDir.appendingPathComponent("\(entry.fileID).dat"), key: key)
                        if entry.hasThumbnail {
                            _ = try Self.readEncryptedData(from: photosDir.appendingPathComponent("\(entry.fileID)_thumb.dat"), key: key)
                        }
                    }
                }

                return RestorePayload(
                    metrics: metrics,
                    goals: goals,
                    photoEntries: photoEntries,
                    settingsEntries: settingsEntries,
                    customMetrics: customMetrics
                )
            }.value

            // Validate payload before deleting existing data — reject fully corrupt backups
            let validMetricCount = payload.metrics.filter { Self.isRestorableKind($0.kindRaw) }.count
            let validGoalCount = payload.goals.filter {
                Self.isRestorableKind($0.kindRaw) && MetricGoal.Direction(rawValue: $0.directionRaw) != nil
            }.count
            let totalRestorableItems = validMetricCount + validGoalCount + payload.photoEntries.count
            let totalPayloadItems = payload.metrics.count + payload.goals.count + payload.photoEntries.count

            if totalRestorableItems == 0 && totalPayloadItems > 0 {
                return .failure(.invalidBackupSchema)
            }

            // Snapshot existing metrics & goals for rollback (lightweight — no image data)
            let existingMetrics = try context.fetch(FetchDescriptor<MetricSample>())
            let existingGoals = try context.fetch(FetchDescriptor<MetricGoal>())
            let existingCustomMetrics = try context.fetch(FetchDescriptor<CustomMetricDefinition>()).map(CodableCustomMetric.init)

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
                    startDate: $0.startDate,
                    commitmentWeeklyRate: $0.commitmentWeeklyRate
                )
            }

            // Phase 1: Restore metrics & goals (small data, supports rollback)
            try deleteAll(MetricSample.self, from: context)
            try deleteAll(MetricGoal.self, from: context)
            if payload.customMetrics != nil {
                try deleteAll(CustomMetricDefinition.self, from: context)
            }

            for definition in payload.customMetrics ?? [] {
                context.insert(definition.makeModel())
            }

            for m in payload.metrics {
                guard Self.isRestorableKind(m.kindRaw) else { continue }
                let source = MetricSampleSource(rawValue: m.sourceRaw ?? "") ?? .manual
                context.insert(MetricSample(kindRaw: m.kindRaw, value: m.value, date: m.date, source: source))
            }

            for g in payload.goals {
                guard Self.isRestorableKind(g.kindRaw) else { continue }
                guard let direction = MetricGoal.Direction(rawValue: g.directionRaw) else { continue }
                context.insert(MetricGoal(
                    kindRaw: g.kindRaw,
                    targetValue: g.targetValue,
                    direction: direction,
                    createdDate: g.createdDate,
                    startValue: g.startValue,
                    startDate: g.startDate,
                    commitmentWeeklyRate: g.commitmentWeeklyRate
                ))
            }

            do {
                try context.save()
            } catch {
                // Rollback metrics & goals only
                try? deleteAll(MetricSample.self, from: context)
                try? deleteAll(MetricGoal.self, from: context)
                if payload.customMetrics != nil {
                    try? deleteAll(CustomMetricDefinition.self, from: context)
                    for definition in existingCustomMetrics {
                        context.insert(definition.makeModel())
                    }
                }
                for m in snapshotMetrics where Self.isRestorableKind(m.kindRaw) {
                    let source = MetricSampleSource(rawValue: m.sourceRaw ?? "") ?? .manual
                    context.insert(MetricSample(kindRaw: m.kindRaw, value: m.value, date: m.date, source: source))
                }
                for g in snapshotGoals {
                    if Self.isRestorableKind(g.kindRaw),
                       let dir = MetricGoal.Direction(rawValue: g.directionRaw) {
                        context.insert(MetricGoal(
                            kindRaw: g.kindRaw,
                            targetValue: g.targetValue,
                            direction: dir,
                            createdDate: g.createdDate,
                            startValue: g.startValue,
                            startDate: g.startDate,
                            commitmentWeeklyRate: g.commitmentWeeklyRate
                        ))
                    }
                }
                try? context.save()
                throw error
            }

            // Photos are only replaced once the measurements are safely in; the rollback above has no
            // copy of them to put back.
            try deleteAll(PhotoEntry.self, from: context)
            try context.save()

            // Phase 2: Restore photos in batches to limit memory usage
            let photosDir = packageURL.appendingPathComponent("photos", isDirectory: true)
            let photoChunks = stride(from: 0, to: payload.photoEntries.count, by: Self.photoTransferChunkSize).map {
                Array(payload.photoEntries[$0 ..< min($0 + Self.photoTransferChunkSize, payload.photoEntries.count)])
            }

            for batch in photoChunks {
                // Reading and decrypting off the main actor; only inserting and saving stay on it.
                let restoredBatch = try await Task.detached(priority: .utility) { () -> [RestoredPhotoEntry] in
                    try autoreleasepool {
                        try batch.map { entry in
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
                    }
                }.value

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

            await MainActor.run { restoreSettings(payload.settingsEntries) }
            // The restored reminder list and notification switches are only data until the system is
            // told about them; this asks for permission if it is still open, then schedules from them.
            let notifications = await MainActor.run { Self.notificationManagerForRestore }
            await notifications.rescheduleAfterRestore()
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

    private nonisolated static func decodeStoredManifest(from data: Data) throws -> StoredBackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredBackupManifest.self, from: data)
    }

    private static func loadManifestSummary(
        packageURL: URL,
        key: SymmetricKey
    ) async throws -> ICloudBackupManifest {
        try? FileManager.default.startDownloadingUbiquitousItem(at: packageURL)
        return try await Task.detached(priority: .utility) {
            let storedManifest = try Self.decodeStoredManifest(
                from: Self.readUbiquitousData(at: packageURL.appendingPathComponent("manifest.json"))
            )
            let metrics: [CodableMetricSample] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("metrics.json"), key: key
            )
            let goals: [CodableMetricGoal] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("goals.json"), key: key
            )
            let photos: [CodablePhotoEntry] = try Self.readEncrypted(
                from: packageURL.appendingPathComponent("photos_index.json"), key: key
            )
            let settings = try Self.readSettingsEntries(in: packageURL, key: key)

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
        let combined = try readUbiquitousData(at: url)
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(sealedBox, using: key)
    }

    // MARK: - iCloud file access

    /// A coordinated read: for a file iCloud has not downloaded yet, it waits for the download instead of
    /// failing. Blocks while it waits, so call it off the main actor.
    private nonisolated static func readUbiquitousData(at url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// iCloud keeps an item it has not downloaded yet as a hidden `.<name>.icloud` placeholder.
    private nonisolated static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    /// The item a placeholder stands for; any other URL is returned unchanged.
    private nonisolated static func logicalURL(for url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return url }
        return url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
    }

    private nonisolated static func ubiquitousItemExists(at url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholderURL(for: url).path)
    }

    // MARK: - Encryption key management

    /// For writing a backup: creates the key the first time there is none.
    private static func encryptionKeyCreatingIfNeeded() -> SymmetricKey? {
#if DEBUG
        if let override = testEncryptionKeyOverride { return override }
#endif
        return loadOrCreateKeychainKey()
    }

    /// For reading a backup: never creates a key. On a new device the key may not have arrived through
    /// iCloud Keychain yet; a key made here would sync over the real one and lock every backup for good.
    private static func existingEncryptionKey() -> SymmetricKey? {
#if DEBUG
        if let override = testEncryptionKeyOverride { return override }
#endif
        keychainLock.lock()
        defer { keychainLock.unlock() }
        return keyStore.readKey().map { SymmetricKey(data: $0) }
    }

    private static let keychainLock = NSLock()

    private static var keyStore: BackupKeyStore {
#if DEBUG
        if let testKeyStoreOverride { return testKeyStoreOverride }
#endif
        return KeychainBackupKeyStore()
    }

    private static func loadOrCreateKeychainKey() -> SymmetricKey? {
        keychainLock.lock()
        defer { keychainLock.unlock() }

        let store = keyStore
        if let data = store.readKey() {
            return SymmetricKey(data: data)
        }

        // Generate and store new key
        let newKey = SymmetricKey(size: .bits256)
        if store.addKey(newKey.withUnsafeBytes { Data($0) }) {
            return newKey
        }
        // Key was synced via iCloud Keychain between read and add — retry read
        return store.readKey().map { SymmetricKey(data: $0) }
    }

    private static var isOperationRunning = false
    private static var waitingOperations: [CheckedContinuation<Void, Never>] = []

    /// Runs backup and restore work one operation at a time. Launch, backgrounding, the scheduler and
    /// Settings all start them, and a backup running beside a restore could capture a half-restored store.
    /// Main-actor isolated, so checking and taking the turn cannot interleave.
    static func serialized<T>(_ operation: () async -> T) async -> T {
        if isOperationRunning {
            await withCheckedContinuation { waitingOperations.append($0) }
        } else {
            isOperationRunning = true
        }
        defer {
            if waitingOperations.isEmpty {
                isOperationRunning = false
            } else {
                // The turn passes straight to the next operation; the flag stays set.
                waitingOperations.removeFirst().resume()
            }
        }
        return await operation()
    }

    // MARK: - Backup discovery & retention

    private nonisolated static func backupRootURL() -> URL? {
#if DEBUG
        if let override = testBackupRootURLOverride { return override }
#endif
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jacek.measureme")?
            .appendingPathComponent("Documents/Backups", isDirectory: true)
    }

    private nonisolated static func now() -> Date {
#if DEBUG
        if let override = testNowOverride { return override() }
#endif
        return Date()
    }

    private nonisolated static func allBackupPackages(in rootURL: URL) -> [URL] {
        let fm = FileManager.default
        // Hidden files are listed on purpose: a backup not downloaded yet is a hidden placeholder.
        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let packages = contents
            .map(logicalURL(for:))
            .filter { $0.pathExtension == backupExtension }
        return Dictionary(packages.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
            .values
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

    private nonisolated static func enforceRetention(in rootURL: URL) {
        let packages = allBackupPackages(in: rootURL)
        guard packages.count > maxRetainedBackups else { return }

        let toDelete = packages.prefix(packages.count - maxRetainedBackups)
        for url in toDelete {
            removeUbiquitousItem(at: url)
        }
    }

    /// A backup that died partway leaves a `-wip` folder that retention does not see. Only old ones go:
    /// another device on the same account may be writing one right now.
    private nonisolated static func removeStaleWorkInProgress(in rootURL: URL, now: Date) {
        let suffix = ".\(backupExtension)-wip"
        guard let contents = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for url in contents.map(logicalURL(for:)) {
            let name = url.lastPathComponent
            guard name.hasPrefix("backup-"), name.hasSuffix(suffix),
                  let stamp = TimeInterval(name.dropFirst("backup-".count).dropLast(suffix.count)),
                  now.timeIntervalSince1970 - stamp > staleWorkInProgressAge else { continue }
            removeUbiquitousItem(at: url)
        }
    }

    private nonisolated static func removeUbiquitousItem(at url: URL) {
        let fm = FileManager.default
        if (try? fm.removeItem(at: url)) == nil {
            try? fm.removeItem(at: placeholderURL(for: url))
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

    @MainActor private static var notificationManagerForRestore: NotificationManager {
        #if DEBUG
        if let testNotificationManagerOverride { return testNotificationManagerOverride }
        #endif
        return .shared
    }

    @MainActor private static func captureSettings(customMetricIDs: [String]) -> [SettingsEntry] {
        let store = AppSettingsStore.shared
        var entries: [SettingsEntry] = []

        // Written explicitly for every definition (false included), so restoring never inherits a
        // stale "enabled" from a definition that happens to share an identifier on this device.
        for identifier in customMetricIDs {
            entries.append(SettingsEntry(
                key: AppSettingsKeys.Metrics.customEnabled(identifier),
                type: .bool, stringValue: nil, numberValue: nil,
                boolValue: store.bool(forKey: AppSettingsKeys.Metrics.customEnabled(identifier)),
                dataValue: nil
            ))
        }

        for key in AppSettingsBackupCatalog.includedKeys {
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
            } else if let strings = value as? [String] {
                entries.append(SettingsEntry(key: key, type: .stringArray, stringValue: nil, numberValue: nil, boolValue: nil, dataValue: nil, stringArrayValue: strings))
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
            case .stringArray:
                if let value = entry.stringArrayValue {
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
        /// Optional so backups written before the weekly rate was saved still decode.
        let commitmentWeeklyRate: Double?
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

    private struct PhotoFilePayload: Sendable {
        let fileID: String
        let imageData: Data
        let thumbnailData: Data?
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
        let customMetrics: [CodableCustomMetric]?
    }

    private struct CodableCustomMetric: Codable, Sendable {
        let identifier: String
        let name: String
        let unitLabel: String
        let sfSymbolName: String
        let minValue: Double?
        let maxValue: Double?
        let favorsDecrease: Bool
        let createdDate: Date
        let sortOrder: Int

        init(_ model: CustomMetricDefinition) {
            identifier = model.identifier
            name = model.name
            unitLabel = model.unitLabel
            sfSymbolName = model.sfSymbolName
            minValue = model.minValue
            maxValue = model.maxValue
            favorsDecrease = model.favorsDecrease
            createdDate = model.createdDate
            sortOrder = model.sortOrder
        }

        func makeModel() -> CustomMetricDefinition {
            let model = CustomMetricDefinition(
                name: name,
                unitLabel: unitLabel,
                sfSymbolName: sfSymbolName,
                minValue: minValue,
                maxValue: maxValue,
                favorsDecrease: favorsDecrease,
                sortOrder: sortOrder
            )
            model.identifier = identifier
            model.createdDate = createdDate
            return model
        }
    }

    private nonisolated static let customMetricsFileName = "custom_metrics.json"
    private nonisolated static let settingsListsFileName = "settings_lists.json"

    /// Scalar settings plus, when the backup has one, the list-valued settings kept in their own file.
    private nonisolated static func readSettingsEntries(in packageURL: URL, key: SymmetricKey) throws -> [SettingsEntry] {
        var entries: [SettingsEntry] = try readEncrypted(
            from: packageURL.appendingPathComponent("settings.json"), key: key
        )
        let listsURL = packageURL.appendingPathComponent(settingsListsFileName)
        if ubiquitousItemExists(at: listsURL) {
            entries += try readEncrypted(from: listsURL, key: key) as [SettingsEntry]
        }
        return entries
    }

    /// Built-in metrics are validated against `MetricKind`; user-defined ones by their `custom_` prefix
    /// (their definitions travel in the same backup).
    private nonisolated static func isRestorableKind(_ kindRaw: String) -> Bool {
        MetricKind(rawValue: kindRaw) != nil || kindRaw.hasPrefix("custom_")
    }

    struct SettingsEntry: Codable, Sendable {
        let key: String
        let type: ValueType
        let stringValue: String?
        let numberValue: Double?
        let boolValue: Bool?
        let dataValue: Data?
        /// Optional so backups written before arrays were supported still decode.
        var stringArrayValue: [String]? = nil

        enum ValueType: String, Codable, Sendable {
            case string, int, double, bool, data, stringArray
        }
    }
}

/// Where the backup encryption key lives: the synchronizable keychain in the app, an in-memory stand-in in tests.
protocol BackupKeyStore {
    func readKey() -> Data?
    /// `false` when the key could not be stored, including when one already exists.
    func addKey(_ data: Data) -> Bool
}

struct KeychainBackupKeyStore: BackupKeyStore {
    private let service = "com.jacek.measureme.icloud-backup"
    private let account = "encryption-key"

    func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func addKey(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
