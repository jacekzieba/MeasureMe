import XCTest
@testable import MeasureMe

@MainActor
final class DatabaseEncryptionTests: XCTestCase {
    private var sqliteURL: URL!
    private var walURL: URL!
    private var shmURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let fileBase = "dbenc-test-\(UUID().uuidString).sqlite"
        sqliteURL = appSupport.appendingPathComponent(fileBase)
        walURL = URL(fileURLWithPath: sqliteURL.path + "-wal")
        shmURL = URL(fileURLWithPath: sqliteURL.path + "-shm")

        let markerData = Data("x".utf8)
        FileManager.default.createFile(atPath: sqliteURL.path, contents: markerData)
        FileManager.default.createFile(atPath: walURL.path, contents: markerData)
        FileManager.default.createFile(atPath: shmURL.path, contents: markerData)
    }

    override func tearDownWithError() throws {
        for url in [sqliteURL, walURL, shmURL] {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        sqliteURL = nil
        walURL = nil
        shmURL = nil
        try super.tearDownWithError()
    }

    func testApplyRecommendedProtection_ProtectsSqliteFileAndSidecars() throws {
        DatabaseEncryption.applyRecommendedProtection()

        let attrs = try FileManager.default.attributesOfItem(atPath: sqliteURL.path)
        let walAttrs = try FileManager.default.attributesOfItem(atPath: walURL.path)
        let shmAttrs = try FileManager.default.attributesOfItem(atPath: shmURL.path)

        if let fileProtection = attrs[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(fileProtection, DatabaseEncryption.protection)
        }
        if let walProtection = walAttrs[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(walProtection, DatabaseEncryption.protection)
        }
        if let shmProtection = shmAttrs[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(shmProtection, DatabaseEncryption.protection)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sqliteURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shmURL.path))
    }

    /// Co sprawdza: Ochrona plikow jest stosowana przy kazdym uruchomieniu.
    /// Dlaczego: Wczesniej pass wykonywal sie raz na wersje builda, wiec store utworzony
    ///   pozniej — czyli typowo na swiezej instalacji — zostawal bez ochrony do nastepnej
    ///   aktualizacji aplikacji.
    /// Kryteria: Wywolanie nie zapisuje juz odcisku wersji, wiec nic go nie zablokuje.
    func testApplyRecommendedProtectionIfNeeded_DoesNotGateOnBuildVersion() {
        let suiteName = "DatabaseEncryptionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettingsStore(defaults: defaults)

        DatabaseEncryption.applyRecommendedProtectionIfNeeded(settings: settings)

        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?[AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion],
            "The build-version gate is gone; recording a fingerprint would reintroduce it."
        )

        defaults.removePersistentDomain(forName: suiteName)
    }
}
