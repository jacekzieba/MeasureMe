import XCTest
import SwiftData
import CryptoKit
@testable import MeasureMe

@MainActor
final class ICloudBackupServiceTests: XCTestCase {
    private var backupRootURL: URL!

    override func setUpWithError() throws {
        backupRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ICloudBackupServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupRootURL, withIntermediateDirectories: true)
        ICloudBackupService.testBackupRootURLOverride = backupRootURL
        ICloudBackupService.testNowOverride = nil
        ICloudBackupService.testEncryptionKeyOverride = SymmetricKey(size: .bits256)
        AppSettingsStore.shared.set(\.premium.premiumEntitlement, true)
        AppSettingsStore.shared.set(\.iCloudBackup.isEnabled, true)
        AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, 0)
        AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, false)
        AppSettingsStore.shared.set(\.onboarding.onboardingViewedICloudBackupOffer, true)
        AppSettingsStore.shared.set(\.onboarding.onboardingSkippedICloudBackup, false)
    }

    override func tearDownWithError() throws {
        ICloudBackupService.resetTestOverrides()
        if let backupRootURL {
            try? FileManager.default.removeItem(at: backupRootURL)
        }
    }

    func testCreateBackupWritesExpectedFiles() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        ICloudBackupService.testNowOverride = { fixedDate }

        let result = await ICloudBackupService.createBackupNow(context: context, isPremium: true)
        guard case .success(let manifest) = result else {
            return XCTFail("Expected successful backup result")
        }

        XCTAssertEqual(manifest.metricsCount, 1)
        XCTAssertEqual(manifest.goalsCount, 1)
        XCTAssertEqual(manifest.photosCount, 1)
        XCTAssertGreaterThan(manifest.settingsCount, 0)
        XCTAssertTrue(manifest.isEncrypted)

        let packages = try backupPackages()
        XCTAssertEqual(packages.count, 1)
        let package = try XCTUnwrap(packages.first)

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("metrics.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("goals.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("photos_index.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("settings.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("photos").path))

        // Manifest must be readable as plaintext, but only expose minimal metadata.
        let manifestData = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        XCTAssertEqual(manifestObject["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(manifestObject["createdAt"])
        XCTAssertEqual(manifestObject["isEncrypted"] as? Bool, true)
        XCTAssertNil(manifestObject["metricsCount"])
        XCTAssertNil(manifestObject["goalsCount"])
        XCTAssertNil(manifestObject["photosCount"])
        XCTAssertNil(manifestObject["settingsCount"])
        XCTAssertNil(manifestObject["sizeBytes"])

        // Data files must NOT be readable as plaintext JSON (they are encrypted).
        let metricsRaw = try Data(contentsOf: package.appendingPathComponent("metrics.json"))
        XCTAssertNil(try? JSONSerialization.jsonObject(with: metricsRaw))

        let encryptedPhotoFile = try XCTUnwrap(try firstPhotoDataFile(in: package))
        let encryptedPhotoBytes = try Data(contentsOf: encryptedPhotoFile)
        XCTAssertNotEqual(encryptedPhotoBytes, Data([1, 2, 3, 4, 5]))
        XCTAssertNotEqual(encryptedPhotoBytes, Data([9, 8, 7]))
    }

    func testCreateBackupFailsForNonPremiumUser() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()

        let result = await ICloudBackupService.createBackupNow(context: context, isPremium: false)
        guard case .failure(let error) = result else {
            return XCTFail("Expected premium-required failure")
        }

        XCTAssertEqual(error, .premiumRequired)
        XCTAssertEqual(try backupPackages().count, 0)
    }

    func testCreateBackupFailsWhenFeatureIsDisabled() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()
        AppSettingsStore.shared.set(\.iCloudBackup.isEnabled, false)

        let result = await ICloudBackupService.createBackupNow(context: context, isPremium: true)
        guard case .failure(let error) = result else {
            return XCTFail("Expected backup-disabled failure")
        }

        XCTAssertEqual(error, .backupDisabled)
        XCTAssertEqual(try backupPackages().count, 0)
        XCTAssertFalse(AppSettingsStore.shared.snapshot.iCloudBackup.isEnabled)
    }

    func testRestoreLatestBackupManuallyRestoresDataAndSettings() async throws {
        let sourceContext = ModelContext(try makeContainer())
        AppSettingsStore.shared.set("Backup User", forKey: AppSettingsKeys.Profile.userName)
        AppSettingsStore.shared.set("imperial", forKey: AppSettingsKeys.Profile.unitsSystem)
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_100) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        targetContext.insert(MetricSample(kind: .waist, value: 90, date: Date(timeIntervalSince1970: 100)))
        try targetContext.save()
        AppSettingsStore.shared.set("Other User", forKey: AppSettingsKeys.Profile.userName)
        AppSettingsStore.shared.set("metric", forKey: AppSettingsKeys.Profile.unitsSystem)

        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)
        guard case .success = restoreResult else {
            return XCTFail("Expected successful restore result")
        }

        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricSample>()), 1)
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricGoal>()), 1)
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<PhotoEntry>()), 1)
        let restoredPhoto = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<PhotoEntry>()).first)
        XCTAssertEqual(restoredPhoto.imageData, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(restoredPhoto.thumbnailData, Data([9, 8, 7]))

        for _ in 0..<50 where AppSettingsStore.shared.snapshot.profile.userName != "Backup User" {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(AppSettingsStore.shared.snapshot.profile.userName, "Backup User")
        XCTAssertEqual(AppSettingsStore.shared.snapshot.profile.unitsSystem, "imperial")
    }

    func testRestoreLatestBackupManuallyFailsForNonPremiumUser() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_101) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: false)
        guard case .failure(let error) = restoreResult else {
            return XCTFail("Expected premium-required failure")
        }

        XCTAssertEqual(error, .premiumRequired)
    }

    func testRetentionKeepsSevenLatestBackups() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()

        for index in 0..<8 {
            ICloudBackupService.testNowOverride = {
                Date(timeIntervalSince1970: 1_700_001_000 + TimeInterval(index))
            }
            _ = await ICloudBackupService.createBackupNow(context: context, isPremium: true)
        }

        let packages = try backupPackages()
        XCTAssertEqual(packages.count, 7)
    }

    func testRunScheduledBackupRespectsTwentyFourHourWindow() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()
        AppSettingsStore.shared.set(\.iCloudBackup.isEnabled, true)

        let now = Date(timeIntervalSince1970: 1_700_002_000)
        ICloudBackupService.testNowOverride = { now }

        AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, now.timeIntervalSince1970)
        await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: true)
        XCTAssertEqual(try backupPackages().count, 0)

        AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, now.addingTimeInterval(-90_000).timeIntervalSince1970)
        await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: true)
        XCTAssertEqual(try backupPackages().count, 1)
    }

    func testAutoRestoreRunsOnlyWhenStoreIsEmpty() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_003_000) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let nonEmptyContext = ModelContext(try makeContainer())
        nonEmptyContext.insert(MetricSample(kind: .waist, value: 99, date: .now))
        try nonEmptyContext.save()
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, false)
        let didRestoreNonEmpty = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: nonEmptyContext)
        XCTAssertFalse(didRestoreNonEmpty)

        let emptyContext = ModelContext(try makeContainer())
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, false)
        let didRestoreEmpty = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: emptyContext)
        XCTAssertTrue(didRestoreEmpty)
        XCTAssertEqual(try emptyContext.fetchCount(FetchDescriptor<MetricSample>()), 1)
    }

    func testAutoRestoreSkipsWithoutPremiumEntitlement() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_003_100) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        AppSettingsStore.shared.set(\.premium.premiumEntitlement, false)
        let emptyContext = ModelContext(try makeContainer())
        let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: emptyContext)

        XCTAssertFalse(didRestore)
        XCTAssertEqual(try emptyContext.fetchCount(FetchDescriptor<MetricSample>()), 0)
    }

    func testAutoRestoreSkipsWithoutBackupOptIn() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_003_200) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        AppSettingsStore.shared.set(\.onboarding.onboardingViewedICloudBackupOffer, false)
        let emptyContext = ModelContext(try makeContainer())
        let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: emptyContext)

        XCTAssertFalse(didRestore)
        XCTAssertEqual(try emptyContext.fetchCount(FetchDescriptor<MetricSample>()), 0)
    }

    func testAutoRestoreSkipsWhenStoreContainsOnlyPhotoEntries() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_003_300) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        targetContext.insert(
            PhotoEntry(
                imageData: Data([5, 4, 3]),
                thumbnailData: nil,
                date: Date(timeIntervalSince1970: 1_700_003_301),
                tags: [.wholeBody],
                linkedMetrics: []
            )
        )
        try targetContext.save()

        let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: targetContext)
        XCTAssertFalse(didRestore)
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<PhotoEntry>()), 1)
    }

    func testAutoRestoreSkipsWhenStoreContainsOnlyGoals() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_003_400) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        targetContext.insert(
            MetricGoal(
                kind: .waist,
                targetValue: 80,
                direction: .decrease,
                createdDate: Date(timeIntervalSince1970: 1_700_003_401)
            )
        )
        try targetContext.save()

        let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: targetContext)
        XCTAssertFalse(didRestore)
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricGoal>()), 1)
    }

    func testConcurrentAutoRestorePerformsOnlyOneRestore() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_003_500) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let sharedContainer = try makeContainer()
        let context = ModelContext(sharedContainer)
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, false)

        async let first = ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: context)
        async let second = ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: context)
        let results = await [first, second]

        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1)
        XCTAssertTrue(AppSettingsStore.shared.snapshot.iCloudBackup.autoRestoreCompleted)
    }

    func testAutoRestoreSkipsWhenAlreadyCompleted() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_004_000) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let emptyContext = ModelContext(try makeContainer())
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, true)
        let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: emptyContext)

        XCTAssertFalse(didRestore)
        XCTAssertEqual(try emptyContext.fetchCount(FetchDescriptor<MetricSample>()), 0)
    }

    func testManualRestoreReturnsNoBackupFoundWhenContainerIsEmpty() async throws {
        let context = ModelContext(try makeContainer())
        let result = await ICloudBackupService.restoreLatestBackupManually(context: context, isPremium: true)
        guard case .failure(let error) = result else {
            return XCTFail("Expected no-backup failure")
        }

        XCTAssertEqual(error, .noBackupFound)
    }

    func testRestoreFailsWithInvalidSchemaVersion() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_005_000) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        // Tamper: overwrite schemaVersion in the plaintext manifest.
        let package = try XCTUnwrap(try backupPackages().first)
        let manifestURL = package.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        json["schemaVersion"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)

        let targetContext = ModelContext(try makeContainer())
        let result = await ICloudBackupService.restoreLatestBackupManually(
            context: targetContext, isPremium: true
        )
        guard case .failure(let error) = result else {
            return XCTFail("Expected invalidBackupSchema failure")
        }
        XCTAssertEqual(error, .invalidBackupSchema)

        // Verify no data was deleted from target store (read-all-first guard).
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricSample>()), 0)
    }

    func testRestoreRejectsPayloadWithAllInvalidRawValues() async throws {
        // Create a valid backup first.
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_005_100) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        // Tamper: replace metrics.json with encrypted data containing invalid kindRaw.
        let package = try XCTUnwrap(try backupPackages().first)
        let key = try XCTUnwrap(ICloudBackupService.testEncryptionKeyOverride)

        let iso8601Encoder = JSONEncoder()
        iso8601Encoder.dateEncodingStrategy = .iso8601

        let corruptMetrics = [
            CodableMetricSampleStub(kindRaw: "invalid_metric_999", value: 80, date: Date())
        ]
        let encoded = try iso8601Encoder.encode(corruptMetrics)
        let sealed = try ChaChaPoly.seal(encoded, using: key)
        try sealed.combined.write(to: package.appendingPathComponent("metrics.json"))

        // Also corrupt goals.
        let corruptGoals = [
            CodableMetricGoalStub(kindRaw: "invalid_goal_999", targetValue: 70, directionRaw: "invalid_dir", createdDate: Date(), startValue: 80, startDate: Date())
        ]
        let goalEncoded = try iso8601Encoder.encode(corruptGoals)
        let goalSealed = try ChaChaPoly.seal(goalEncoded, using: key)
        try goalSealed.combined.write(to: package.appendingPathComponent("goals.json"))

        // Remove photos from the backup so totalRestorableItems == 0.
        let photosDir = package.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.removeItem(at: photosDir)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let emptyPhotos: [CodablePhotoEntryStub] = []
        let photosEncoded = try iso8601Encoder.encode(emptyPhotos)
        let photosSealed = try ChaChaPoly.seal(photosEncoded, using: key)
        try photosSealed.combined.write(to: package.appendingPathComponent("photos_index.json"))

        // Attempt restore — should fail with invalidBackupSchema.
        let targetContext = ModelContext(try makeContainer())
        targetContext.insert(MetricSample(kind: .waist, value: 88, date: Date(timeIntervalSince1970: 200)))
        try targetContext.save()

        let result = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)
        guard case .failure(let error) = result else {
            return XCTFail("Expected invalidBackupSchema failure for all-invalid payload")
        }
        XCTAssertEqual(error, .invalidBackupSchema)

        // Existing data must NOT have been deleted.
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricSample>()), 1)
    }

    // MARK: - Preflight restore

    func testPreflightRestoreReturnsManifestWithoutModifyingData() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_006_000) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        targetContext.insert(MetricSample(kind: .waist, value: 88, date: Date(timeIntervalSince1970: 200)))
        try targetContext.save()

        let result = await ICloudBackupService.preflightRestore(context: targetContext, isPremium: true)
        guard case .success(let manifest) = result else {
            return XCTFail("Expected successful preflight result")
        }

        XCTAssertEqual(manifest.metricsCount, 1)
        XCTAssertEqual(manifest.goalsCount, 1)
        XCTAssertEqual(manifest.photosCount, 1)
        XCTAssertGreaterThan(manifest.settingsCount, 0)
        XCTAssertEqual(manifest.schemaVersion, 1)

        // Target data must remain untouched.
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricSample>()), 1)
    }

    func testPreflightRestoreReturnsNoBackupFoundWhenEmpty() async throws {
        let context = ModelContext(try makeContainer())
        let result = await ICloudBackupService.preflightRestore(context: context, isPremium: true)
        guard case .failure(let error) = result else {
            return XCTFail("Expected no-backup failure")
        }
        XCTAssertEqual(error, .noBackupFound)
    }

    // MARK: - Backup size

    func testCreateBackupStoresPositiveSizeBytes() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_007_000) }
        let result = await ICloudBackupService.createBackupNow(context: context, isPremium: true)
        guard case .success(let manifest) = result else {
            return XCTFail("Expected successful backup result")
        }

        // Manifest should carry size.
        XCTAssertNotNil(manifest.sizeBytes)
        XCTAssertGreaterThan(manifest.sizeBytes ?? 0, 0)

        // AppSettings should be updated.
        let storedSize = AppSettingsStore.shared.snapshot.iCloudBackup.lastBackupSizeBytes
        XCTAssertGreaterThan(storedSize, 0)
    }

    // MARK: - Localized error messages

    func testAllBackupErrorCasesReturnNonEmptyLocalizedMessage() {
        let cases: [ICloudBackupService.BackupError] = [
            .premiumRequired,
            .backupDisabled,
            .noBackupFound,
            .invalidBackupSchema,
            .encryptionError,
            .fileSystemError("test detail"),
            .fileSystemError("iCloud container unavailable")
        ]
        for error in cases {
            XCTAssertFalse(error.localizedMessage.isEmpty, "localizedMessage empty for \(error)")
        }
    }

    // MARK: - Manifest backward compatibility

    func testManifestDecodesWithoutSizeBytes() throws {
        // Simulates a manifest written by an older app version (no sizeBytes field).
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2024-01-01T00:00:00Z",
            "metricsCount": 5,
            "goalsCount": 2,
            "photosCount": 1,
            "settingsCount": 3,
            "isEncrypted": true
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ICloudBackupManifest.self, from: Data(json.utf8))

        XCTAssertNil(manifest.sizeBytes)
        XCTAssertEqual(manifest.metricsCount, 5)
    }

    func testManifestDecodesWithSizeBytes() throws {
        let json = """
        {
            "schemaVersion": 1,
            "createdAt": "2024-01-01T00:00:00Z",
            "metricsCount": 5,
            "goalsCount": 2,
            "photosCount": 1,
            "settingsCount": 3,
            "isEncrypted": true,
            "sizeBytes": 123456
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ICloudBackupManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.sizeBytes, 123456)
    }

    func testPlaintextManifestOmitsSensitiveCountsAndSize() async throws {
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_008_000) }
        _ = await ICloudBackupService.createBackupNow(context: context, isPremium: true)

        let package = try XCTUnwrap(try backupPackages().first)
        let manifestURL = package.appendingPathComponent("manifest.json")
        let manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )

        XCTAssertEqual(Set(manifestObject.keys), ["schemaVersion", "createdAt", "isEncrypted"])
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedSampleData(in context: ModelContext) {
        context.insert(MetricSample(kind: .weight, value: 82.4, date: Date(timeIntervalSince1970: 1_700_000_001)))
        context.insert(
            MetricGoal(
                kind: .weight,
                targetValue: 79.0,
                direction: .decrease,
                createdDate: Date(timeIntervalSince1970: 1_700_000_010),
                startValue: 84.0,
                startDate: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        context.insert(
            PhotoEntry(
                imageData: Data([1, 2, 3, 4, 5]),
                thumbnailData: Data([9, 8, 7]),
                date: Date(timeIntervalSince1970: 1_700_000_100),
                tags: [.wholeBody],
                linkedMetrics: [MetricValueSnapshot(kind: .weight, value: 82.4, unit: "kg")]
            )
        )
    }

    private func backupPackages() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: backupRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "measuremebackup" }
    }

    private func firstPhotoDataFile(in package: URL) throws -> URL? {
        let photosDir = package.appendingPathComponent("photos", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(
            at: photosDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .first(where: { $0.lastPathComponent.hasSuffix(".dat") && !$0.lastPathComponent.contains("_thumb") })
    }
}

// MARK: - Test-only stubs matching the Codable shape used by ICloudBackupService

private struct CodableMetricSampleStub: Encodable {
    let kindRaw: String
    let value: Double
    let date: Date
}

private struct CodableMetricGoalStub: Encodable {
    let kindRaw: String
    let targetValue: Double
    let directionRaw: String
    let createdDate: Date
    let startValue: Double?
    let startDate: Date?
}

private struct CodablePhotoEntryStub: Encodable {
    let fileID: String
    let date: Date
    let tags: [String]
    let linkedMetrics: [CodableLinkedMetricStub]
    let hasThumbnail: Bool
}

private struct CodableLinkedMetricStub: Encodable {
    let metricRawValue: String
    let value: Double
    let unit: String
}
