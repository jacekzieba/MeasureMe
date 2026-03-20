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

    func testApplyRecommendedProtectionIfNeeded_PersistsVersionFingerprint() {
        let suiteName = "DatabaseEncryptionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettingsStore(defaults: defaults)

        DatabaseEncryption.applyRecommendedProtectionIfNeeded(settings: settings)
        let first = settings.string(forKey: AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion)
        XCTAssertNotNil(first)

        DatabaseEncryption.applyRecommendedProtectionIfNeeded(settings: settings)
        let second = settings.string(forKey: AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion)
        XCTAssertEqual(first, second)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
