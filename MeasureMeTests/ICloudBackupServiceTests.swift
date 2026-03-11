import XCTest
import SwiftData
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
        AppSettingsStore.shared.set(\.iCloudBackup.isEnabled, true)
        AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, 0)
        AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, false)
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

        // Manifest must be readable as plaintext (not encrypted).
        let manifestData = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let storedManifest = try decoder.decode(ICloudBackupManifest.self, from: manifestData)
        XCTAssertEqual(storedManifest.schemaVersion, 1)
        XCTAssertEqual(storedManifest.createdAt, fixedDate)

        // Data files must NOT be readable as plaintext JSON (they are encrypted).
        let metricsRaw = try Data(contentsOf: package.appendingPathComponent("metrics.json"))
        XCTAssertNil(try? JSONSerialization.jsonObject(with: metricsRaw))
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

        for _ in 0..<50 where AppSettingsStore.shared.snapshot.profile.userName != "Backup User" {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(AppSettingsStore.shared.snapshot.profile.userName, "Backup User")
        XCTAssertEqual(AppSettingsStore.shared.snapshot.profile.unitsSystem, "imperial")
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

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
}
