/// Cel testow: Pilnuje, zeby kazde ustawienie z AppSettingsKeys mialo swiadoma decyzje: w backupie albo poza nim.
/// Dlaczego to wazne: Lista kluczy backupu byla pisana recznie i po cichu gubila nowe ustawienia (wyglad, HealthKit, AI, Face ID).
/// Kryteria zaliczenia: Nowy klucz bez decyzji wywala test z nazwa klucza; zaden klucz nie jest jednoczesnie w obu grupach.

import XCTest
@testable import MeasureMe

final class AppSettingsBackupCatalogTests: XCTestCase {
    /// Reads every `static let name = "value"` straight from the source, so a key added tomorrow is
    /// covered without anyone remembering to update a test list.
    private func declaredSettingKeys() throws -> [(name: String, value: String)] {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MeasureMe/SettingsStore/AppSettingsKeys.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"static let (\w+)\s*=\s*"([^"]+)""#)
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let name = Range(match.range(at: 1), in: source),
                  let value = Range(match.range(at: 2), in: source) else { return nil }
            return (String(source[name]), String(source[value]))
        }
    }

    func testEveryDeclaredSettingKeyHasABackupDecision() throws {
        let keys = try declaredSettingKeys()
        // Guards the scan itself: an empty or tiny result would make the check below vacuous.
        XCTAssertGreaterThan(keys.count, 100, "Could not read AppSettingsKeys.swift")

        let unclassified = keys.filter { AppSettingsBackupCatalog.classification(ofKey: $0.value) == nil }
        XCTAssertTrue(
            unclassified.isEmpty,
            "Add these keys to AppSettingsBackupCatalog (includedKeys or excludedKeys): "
                + unclassified.map { "\($0.name) = \($0.value)" }.joined(separator: ", ")
        )
    }

    func testNoKeyIsBothIncludedAndExcluded() {
        let overlap = AppSettingsBackupCatalog.includedKeySet.intersection(AppSettingsBackupCatalog.excludedKeys)
        XCTAssertTrue(overlap.isEmpty, "Keys in both buckets: \(overlap.sorted())")
    }

    func testIncludedKeysContainNoDuplicates() {
        let keys = AppSettingsBackupCatalog.includedKeys
        XCTAssertEqual(keys.count, Set(keys).count, "Duplicate keys in includedKeys")
    }

    func testEntitlementAndDeviceStateStayOutOfBackups() {
        XCTAssertEqual(AppSettingsBackupCatalog.classification(ofKey: AppSettingsKeys.Premium.entitlement), .excluded)
        XCTAssertEqual(AppSettingsBackupCatalog.classification(ofKey: AppSettingsKeys.Health.healthkitAnchorPrefix + "weight"), .excluded)
        XCTAssertEqual(AppSettingsBackupCatalog.classification(ofKey: AppSettingsKeys.ICloudBackup.lastSuccessTimestamp), .excluded)
    }
}
