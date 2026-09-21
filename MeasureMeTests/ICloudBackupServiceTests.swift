import XCTest
import SwiftData
import CryptoKit
import UserNotifications
@testable import MeasureMe

@MainActor
final class ICloudBackupServiceTests: XCTestCase {
    private var backupRootURL: URL!
    private var originalPremiumEntitlement: Any?
    /// Explicitly stored values (not registered defaults) of every key a backup or restore can touch.
    /// A restore writes ~80 settings into the real defaults, so without putting them back the next
    /// test - or the next launch on this simulator - inherits "Backup User", imperial units and so on.
    private var originalStoredSettings: [String: Any] = [:]
    private static let extraTouchedKeys = [
        AppSettingsKeys.Premium.entitlement,
        AppSettingsKeys.ICloudBackup.isEnabled,
        AppSettingsKeys.ICloudBackup.lastSuccessTimestamp,
        AppSettingsKeys.ICloudBackup.lastErrorMessage,
        AppSettingsKeys.ICloudBackup.autoRestoreCompleted,
        AppSettingsKeys.ICloudBackup.lastBackupSizeBytes,
        AppSettingsKeys.Onboarding.onboardingViewedICloudBackupOffer,
        AppSettingsKeys.Onboarding.onboardingSkippedICloudBackup
    ]

    private static var touchedKeys: [String] {
        AppSettingsBackupCatalog.includedKeys + extraTouchedKeys
    }

    /// The fixed keys above plus the per-custom-metric flags, whose names depend on the test's metric id.
    private static func isTouchedKey(_ key: String) -> Bool {
        touchedKeys.contains(key) || key.hasPrefix(AppSettingsKeys.Metrics.customEnabledPrefix)
    }

    override func setUpWithError() throws {
        backupRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ICloudBackupServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupRootURL, withIntermediateDirectories: true)
        ICloudBackupService.testBackupRootURLOverride = backupRootURL
        ICloudBackupService.testNowOverride = nil
        ICloudBackupService.testEncryptionKeyOverride = SymmetricKey(size: .bits256)
        originalPremiumEntitlement = UserDefaults.standard.object(forKey: AppSettingsKeys.Premium.entitlement)
        let stored = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        originalStoredSettings = stored.filter { Self.isTouchedKey($0.key) }
        AppSettingsStore.shared.set(\.premium.premiumEntitlement, true)
        AppSettingsStore.shared.set(\.iCloudBackup.isEnabled, true)
        AppSettingsStore.shared.set(\.iCloudBackup.lastSuccessTimestamp, 0)
        AppSettingsStore.shared.set(\.iCloudBackup.lastErrorMessage, "")
        AppSettingsStore.shared.set(\.iCloudBackup.autoRestoreCompleted, false)
        AppSettingsStore.shared.set(\.onboarding.onboardingViewedICloudBackupOffer, true)
        AppSettingsStore.shared.set(\.onboarding.onboardingSkippedICloudBackup, false)
        AppSettingsStore.shared.set(\.profile.profilePhotoData, nil)
    }

    override func tearDownWithError() throws {
        ICloudBackupService.resetTestOverrides()
        AppSettingsStore.shared.set(\.profile.profilePhotoData, nil)
        if let originalPremiumEntitlement {
            UserDefaults.standard.set(originalPremiumEntitlement, forKey: AppSettingsKeys.Premium.entitlement)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.Premium.entitlement)
        }
        let storedNow = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        let keysToPutBack = Set(Self.touchedKeys).union(storedNow.keys.filter(Self.isTouchedKey))
        for key in keysToPutBack {
            if let original = originalStoredSettings[key] {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        AppSettingsStore.shared.reload()
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
        let profilePhotoData = Data([0xFA, 0xCE, 0x01])
        AppSettingsStore.shared.set("Backup User", forKey: AppSettingsKeys.Profile.userName)
        AppSettingsStore.shared.set("imperial", forKey: AppSettingsKeys.Profile.unitsSystem)
        AppSettingsStore.shared.set(profilePhotoData, forKey: AppSettingsKeys.Profile.profilePhotoData)
        seedSampleData(in: sourceContext)
        try sourceContext.save()

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_100) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        targetContext.insert(MetricSample(kind: .waist, value: 90, date: Date(timeIntervalSince1970: 100)))
        try targetContext.save()
        AppSettingsStore.shared.set("Other User", forKey: AppSettingsKeys.Profile.userName)
        AppSettingsStore.shared.set("metric", forKey: AppSettingsKeys.Profile.unitsSystem)
        AppSettingsStore.shared.removeObject(forKey: AppSettingsKeys.Profile.profilePhotoData)

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
        XCTAssertEqual(AppSettingsStore.shared.snapshot.profile.profilePhotoData, profilePhotoData)
    }

    /// Co sprawdza: Ustawienia uzytkownika spoza profilu (wyglad, HealthKit, AI, Face ID, kolejnosc metryk, uklad zdjec) wracaja po restore.
    /// Dlaczego: Backup gubil czesc ustawien, bo lista kluczy byla utrzymywana recznie i byla niepelna.
    /// Kryteria: Kazda wartosc po restore jest rowna tej z chwili backupu, nie tej ustawionej pozniej.
    func testRestoreBringsBackUserPreferencesOutsideProfile() async throws {
        let store = AppSettingsStore.shared
        let atBackup: [String: Any] = [
            AppSettingsKeys.Experience.appAppearance: AppAppearance.light.rawValue,
            AppSettingsKeys.Privacy.requireBiometricForPhotos: true,
            AppSettingsKeys.Health.isSyncEnabled: true,
            AppSettingsKeys.Health.healthkitSyncWeight: false,
            AppSettingsKeys.Notifications.aiWeeklyDigestEnabled: false,
            AppSettingsKeys.Notifications.aiDigestWeekday: 5,
            AppSettingsKeys.Notifications.perMetricSmartEnabled: false,
            AppSettingsKeys.Experience.hasCustomizedMetrics: true,
            "metrics_active_order": ["waist", "weight"],
            "home_key_metrics": ["waist"],
            "photos.gridLayoutMode": PhotoGridLayoutMode.compact.rawValue,
            "photos.overlayPose": "front",
            "photos.overlayOpacity": 0.65
        ]
        let afterBackup: [String: Any] = [
            AppSettingsKeys.Experience.appAppearance: AppAppearance.dark.rawValue,
            AppSettingsKeys.Privacy.requireBiometricForPhotos: false,
            AppSettingsKeys.Health.isSyncEnabled: false,
            AppSettingsKeys.Health.healthkitSyncWeight: true,
            AppSettingsKeys.Notifications.aiWeeklyDigestEnabled: true,
            AppSettingsKeys.Notifications.aiDigestWeekday: 2,
            AppSettingsKeys.Notifications.perMetricSmartEnabled: true,
            AppSettingsKeys.Experience.hasCustomizedMetrics: false,
            "metrics_active_order": ["weight"],
            "home_key_metrics": ["weight"],
            "photos.gridLayoutMode": PhotoGridLayoutMode.review.rawValue,
            "photos.overlayPose": "side",
            "photos.overlayOpacity": 0.2
        ]
        let originals = Dictionary(uniqueKeysWithValues: atBackup.keys.map { ($0, store.object(forKey: $0)) })
        addTeardownBlock { @MainActor in
            for (key, value) in originals { store.set(value, forKey: key) }
            store.reload()
        }

        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()
        for (key, value) in atBackup { store.set(value, forKey: key) }

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_200) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        for (key, value) in afterBackup { store.set(value, forKey: key) }

        let targetContext = ModelContext(try makeContainer())
        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)
        guard case .success = restoreResult else {
            return XCTFail("Expected successful restore result")
        }

        for (key, expected) in atBackup {
            XCTAssertEqual(
                store.object(forKey: key) as? NSObject,
                expected as? NSObject,
                "Setting \(key) was not restored from the backup"
            )
        }
    }

    /// Co sprawdza: Niestandardowe metryki (definicja, pomiary, cel, wlaczenie i kolejnosc) wracaja po restore.
    /// Dlaczego: Restore filtrowal wpisy przez MetricKind, wiec pomiary i cele custom byly po cichu gubione, a definicji nie bylo w backupie.
    /// Kryteria: Po restore w kontenerze docelowym jest dokladnie definicja z backupu, jej pomiar i cel, a ustawienia custom pasuja do backupu.
    func testRestoreBringsBackCustomMetricsWithDataAndSettings() async throws {
        let store = AppSettingsStore.shared
        let customID = "custom_TEST-WRIST"
        let enabledKey = "custom_metric_\(customID)_enabled"
        let orderKey = "custom_metrics_order"
        let originals = [enabledKey, orderKey, "custom_metric_custom_LOCAL_enabled"].map { ($0, store.object(forKey: $0)) }
        addTeardownBlock { @MainActor in
            for (key, value) in originals { store.set(value, forKey: key) }
            store.reload()
        }

        let sourceContext = ModelContext(try makeContainer())
        let definition = CustomMetricDefinition(
            name: "Wrist", unitLabel: "cm", sfSymbolName: "figure.wave",
            minValue: 10, maxValue: 30, favorsDecrease: true, sortOrder: 3
        )
        definition.identifier = customID
        definition.createdDate = Date(timeIntervalSince1970: 1_700_000_050)
        sourceContext.insert(definition)
        sourceContext.insert(MetricSample(kindRaw: customID, value: 16.5, date: Date(timeIntervalSince1970: 1_700_000_060)))
        sourceContext.insert(MetricGoal(kindRaw: customID, targetValue: 15, direction: .decrease, createdDate: Date(timeIntervalSince1970: 1_700_000_070)))
        seedSampleData(in: sourceContext)
        try sourceContext.save()
        store.set(true, forKey: enabledKey)
        store.set([customID], forKey: orderKey)

        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_300) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        let local = CustomMetricDefinition(name: "Local only", unitLabel: "kg")
        local.identifier = "custom_LOCAL"
        targetContext.insert(local)
        try targetContext.save()
        store.set(false, forKey: enabledKey)
        store.set(true, forKey: "custom_metric_custom_LOCAL_enabled")
        store.set(["custom_LOCAL"], forKey: orderKey)

        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)
        guard case .success = restoreResult else {
            return XCTFail("Expected successful restore result")
        }

        let definitions = try targetContext.fetch(FetchDescriptor<CustomMetricDefinition>())
        XCTAssertEqual(definitions.map(\.identifier), [customID], "Backup definitions replace the local ones")
        let restored = try XCTUnwrap(definitions.first)
        XCTAssertEqual(restored.name, "Wrist")
        XCTAssertEqual(restored.unitLabel, "cm")
        XCTAssertEqual(restored.sfSymbolName, "figure.wave")
        XCTAssertEqual(restored.minValue, 10)
        XCTAssertEqual(restored.maxValue, 30)
        XCTAssertTrue(restored.favorsDecrease)
        XCTAssertEqual(restored.sortOrder, 3)
        XCTAssertEqual(restored.createdDate, Date(timeIntervalSince1970: 1_700_000_050))

        let customSamples = try targetContext.fetch(FetchDescriptor<MetricSample>()).filter { $0.kindRaw == customID }
        XCTAssertEqual(customSamples.map(\.value), [16.5])
        let customGoals = try targetContext.fetch(FetchDescriptor<MetricGoal>()).filter { $0.kindRaw == customID }
        XCTAssertEqual(customGoals.map(\.targetValue), [15])
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricSample>()), 2, "Built-in sample restored next to the custom one")

        XCTAssertEqual(store.object(forKey: enabledKey) as? Bool, true)
        XCTAssertEqual(store.stringArray(forKey: orderKey), [customID])
    }

    /// Co sprawdza: Backup utworzony przed wprowadzeniem custom metryk (bez pliku definicji) nadal sie przywraca i nie kasuje lokalnych definicji.
    /// Dlaczego: Zmiana formatu backupu nie moze psuc starszych kopii.
    /// Kryteria: Restore konczy sie sukcesem, a lokalna definicja zostaje.
    func testRestoreFromBackupWithoutCustomMetricsFileKeepsLocalDefinitions() async throws {
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_310) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        // Simulate a backup written by an older build: no custom-metrics file in the package.
        let package = try XCTUnwrap(try backupPackages().first)
        try? FileManager.default.removeItem(at: package.appendingPathComponent("custom_metrics.json"))

        let targetContext = ModelContext(try makeContainer())
        let local = CustomMetricDefinition(name: "Local only", unitLabel: "kg")
        local.identifier = "custom_LOCAL"
        targetContext.insert(local)
        try targetContext.save()

        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)
        guard case .success = restoreResult else {
            return XCTFail("Old backups without custom metrics must still restore")
        }

        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<CustomMetricDefinition>()).map(\.identifier), ["custom_LOCAL"])
        XCTAssertEqual(try targetContext.fetchCount(FetchDescriptor<MetricSample>()), 1)
    }

    /// Co sprawdza: Backup zawierajacy wylacznie pomiary custom nie jest odrzucany jako uszkodzony.
    /// Dlaczego: Walidacja liczyla tylko wpisy z MetricKind, wiec taka kopia wygladala na pusta i konczyla sie invalidBackupSchema.
    /// Kryteria: Restore konczy sie sukcesem i przywraca pomiar.
    func testRestoreAcceptsBackupThatContainsOnlyCustomMetricSamples() async throws {
        let customID = "custom_TEST-ONLY"
        let sourceContext = ModelContext(try makeContainer())
        let definition = CustomMetricDefinition(name: "Steps", unitLabel: "steps")
        definition.identifier = customID
        sourceContext.insert(definition)
        sourceContext.insert(MetricSample(kindRaw: customID, value: 8000, date: Date(timeIntervalSince1970: 1_700_000_080)))
        try sourceContext.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_320) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)

        guard case .success = restoreResult else {
            return XCTFail("A backup of only custom samples is valid, got \(restoreResult)")
        }
        XCTAssertEqual(try targetContext.fetch(FetchDescriptor<MetricSample>()).map(\.value), [8000])
    }

    /// Co sprawdza: Tygodniowe tempo celu (commitmentWeeklyRate) wraca po restore, dla metryki wbudowanej i custom.
    /// Dlaczego: Pole nie bylo zapisywane w backupie, wiec po przywroceniu cel tracil zadeklarowane tempo.
    /// Kryteria: Po restore oba cele maja to samo tempo co w backupie; cel bez tempa nadal je ma nil.
    func testRestoreKeepsGoalWeeklyRate() async throws {
        let customID = "custom_TEST-RATE"
        let sourceContext = ModelContext(try makeContainer())
        let definition = CustomMetricDefinition(name: "Reps", unitLabel: "reps")
        definition.identifier = customID
        sourceContext.insert(definition)
        sourceContext.insert(MetricGoal(kind: .weight, targetValue: 75, direction: .decrease, commitmentWeeklyRate: 0.5))
        sourceContext.insert(MetricGoal(kind: .waist, targetValue: 80, direction: .decrease))
        sourceContext.insert(MetricGoal(kindRaw: customID, targetValue: 40, direction: .increase, commitmentWeeklyRate: 2.5))
        try sourceContext.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_330) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        let targetContext = ModelContext(try makeContainer())
        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(context: targetContext, isPremium: true)
        guard case .success = restoreResult else {
            return XCTFail("Expected successful restore result")
        }

        let rates = Dictionary(
            uniqueKeysWithValues: try targetContext.fetch(FetchDescriptor<MetricGoal>()).map { ($0.kindRaw, $0.commitmentWeeklyRate) }
        )
        XCTAssertEqual(rates[MetricKind.weight.rawValue] ?? nil, 0.5)
        XCTAssertEqual(rates[customID] ?? nil, 2.5)
        XCTAssertNil(rates[MetricKind.waist.rawValue] ?? nil, "A goal without a weekly rate must stay without one")
        XCTAssertEqual(rates.count, 3)
    }

    /// Co sprawdza: settings.json z nowego backupu dekoduje sie w starszym formacie, ktory zna tylko typy skalarne.
    /// Dlaczego: Starsza wersja aplikacji (np. na drugim urzadzeniu z tym samym iCloud) odrzuca caly plik, gdy trafi na nieznany typ wpisu, i restore sie nie udaje.
    /// Kryteria: Dekoder znajacy tylko string/int/double/bool/data czyta plik bez bledu, a tablice wracaja po restore z osobnego pliku.
    func testSettingsFileStaysReadableByBuildsThatKnowOnlyScalarTypes() async throws {
        let store = AppSettingsStore.shared
        store.set(["waist", "weight"], forKey: AppSettingsKeys.Metrics.activeOrder)
        let context = ModelContext(try makeContainer())
        seedSampleData(in: context)
        try context.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_340) }
        _ = await ICloudBackupService.createBackupNow(context: context, isPremium: true)

        let package = try XCTUnwrap(try backupPackages().first)
        let key = try XCTUnwrap(ICloudBackupService.testEncryptionKeyOverride)
        let sealed = try ChaChaPoly.SealedBox(combined: Data(contentsOf: package.appendingPathComponent("settings.json")))
        let plain = try ChaChaPoly.open(sealed, using: key)

        XCTAssertNoThrow(try JSONDecoder().decode([LegacySettingsEntry].self, from: plain))
    }

    /// Co sprawdza: Po restore przypomnienia z backupu sa faktycznie planowane w systemie powiadomien.
    /// Dlaczego: Restore odtwarzal liste przypomnien, ale nikt nie tworzyl z niej powiadomien, wiec nie dzialaly az do edycji w ustawieniach.
    /// Kryteria: Centrum powiadomien dostaje zadanie dla przypomnienia z backupu, mimo ze przed restore powiadomienia byly wylaczone.
    func testRestoreSchedulesTheRestoredReminders() async throws {
        let store = AppSettingsStore.shared
        let reminder = MeasurementReminder(id: "restored-1", date: Date(timeIntervalSince1970: 1_700_000_500), repeatRule: .daily)
        store.set(try JSONEncoder().encode([reminder]), forKey: AppSettingsKeys.Notifications.reminders)
        store.set(true, forKey: AppSettingsKeys.Notifications.notificationsEnabled)
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_350) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        // A fresh device: no reminders, notifications off.
        store.removeObject(forKey: AppSettingsKeys.Notifications.reminders)
        store.set(false, forKey: AppSettingsKeys.Notifications.notificationsEnabled)
        let center = RecordingNotificationCenter()
        ICloudBackupService.testNotificationManagerOverride = NotificationManager(center: center, settings: store)

        let restoreResult = await ICloudBackupService.restoreLatestBackupManually(
            context: ModelContext(try makeContainer()), isPremium: true
        )
        guard case .success = restoreResult else {
            return XCTFail("Expected successful restore result")
        }

        XCTAssertTrue(
            center.addedIdentifiers.contains("measurement_reminder_restored-1"),
            "Restored reminders must be scheduled, got \(center.addedIdentifiers)"
        )
    }

    /// Backs up with the notification switch set to `enabledInBackup`, then restores onto a device whose
    /// notification permission is `status`. Returns the fake center so the test can see what was asked of it.
    private func restoreOntoDevice(
        notificationsEnabledInBackup: Bool,
        permission status: UNAuthorizationStatus
    ) async throws -> RecordingNotificationCenter {
        let store = AppSettingsStore.shared
        store.set(notificationsEnabledInBackup, forKey: AppSettingsKeys.Notifications.notificationsEnabled)
        let sourceContext = ModelContext(try makeContainer())
        seedSampleData(in: sourceContext)
        try sourceContext.save()
        ICloudBackupService.testNowOverride = { Date(timeIntervalSince1970: 1_700_000_360) }
        _ = await ICloudBackupService.createBackupNow(context: sourceContext, isPremium: true)

        store.set(false, forKey: AppSettingsKeys.Notifications.notificationsEnabled)
        let center = RecordingNotificationCenter()
        center.status = status
        ICloudBackupService.testNotificationManagerOverride = NotificationManager(center: center, settings: store)
        let result = await ICloudBackupService.restoreLatestBackupManually(
            context: ModelContext(try makeContainer()), isPremium: true
        )
        guard case .success = result else {
            XCTFail("Expected successful restore result")
            return center
        }
        return center
    }

    /// Co sprawdza: Po restore na urzadzeniu, ktore nigdy nie pytalo o zgode, aplikacja prosi o zgode na powiadomienia.
    /// Dlaczego: Zgoda jest osobna dla kazdego urzadzenia; bez niej przywrocone przypomnienia sa zaplanowane, ale nigdy nie zadzwonia.
    /// Kryteria: Dokladnie jedna prosba, gdy backup mial powiadomienia wlaczone, a status to notDetermined.
    func testRestoreAsksForNotificationPermissionWhenItHasNeverBeenAsked() async throws {
        let center = try await restoreOntoDevice(notificationsEnabledInBackup: true, permission: .notDetermined)

        XCTAssertEqual(center.authorizationRequests, 1)
    }

    /// Co sprawdza: Restore nie pyta o zgode, gdy powiadomienia byly w backupie wylaczone albo odpowiedz jest juz znana.
    /// Dlaczego: Okno systemowe pojawia sie tylko tam, gdzie ma sens; odmowy nie wolno ponawiac.
    /// Kryteria: Zero prosb w trzech przypadkach.
    func testRestoreDoesNotAskForPermissionWhenItWouldNotHelp() async throws {
        let switchedOff = try await restoreOntoDevice(notificationsEnabledInBackup: false, permission: .notDetermined)
        XCTAssertEqual(switchedOff.authorizationRequests, 0, "Notifications were off in the backup")

        let denied = try await restoreOntoDevice(notificationsEnabledInBackup: true, permission: .denied)
        XCTAssertEqual(denied.authorizationRequests, 0, "A denial is not asked again")

        let granted = try await restoreOntoDevice(notificationsEnabledInBackup: true, permission: .authorized)
        XCTAssertEqual(granted.authorizationRequests, 0, "Already granted")
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
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
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

/// Records what would be handed to the system notification center.
private final class RecordingNotificationCenter: NotificationCenterClient {
    private(set) var addedIdentifiers: [String] = []
    var status: UNAuthorizationStatus = .authorized
    private(set) var authorizationRequests = 0

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return true
    }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func pendingRequestIdentifiers() async -> [String] { [] }
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        addedIdentifiers.append(request.identifier)
        completion(nil)
    }
    func add(_ request: UNNotificationRequest) async throws { addedIdentifiers.append(request.identifier) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

/// The settings entry as older builds decode it: no `stringArray` case.
private struct LegacySettingsEntry: Decodable {
    enum ValueType: String, Decodable { case string, int, double, bool, data }

    let key: String
    let type: ValueType
    let stringValue: String?
    let numberValue: Double?
    let boolValue: Bool?
    let dataValue: Data?
}

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
