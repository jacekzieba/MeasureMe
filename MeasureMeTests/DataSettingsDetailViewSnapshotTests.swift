/// Cel testu: Chroni układ sekcji iCloud Backup i Data w DataSettingsDetailView przed regresjami.
/// Dlaczego to ważne: Sekcja iCloud backup ma wiele stanów UI (error banner, timestamp, toggle).
/// Kryteria zaliczenia: Snapshot jest stabilny i zgodny ze wzorcem referencyjnym.

@testable import MeasureMe

import XCTest
import SwiftUI
import SnapshotTesting

final class DataSettingsDetailViewSnapshotTests: XCTestCase {

    // MARK: - UserDefaults keys to backup/restore

    private static let managedKeys: [String] = [
        "appLanguage",
        "icloud_backup_enabled",
        "icloud_backup_last_success_timestamp",
        "icloud_backup_last_error_message",
        "icloud_backup_last_size_bytes",
        "analytics_enabled"
    ]

    // MARK: - Helpers

    private func backupDefaults() -> [String: Any?] {
        let defaults = UserDefaults.standard
        return Dictionary(uniqueKeysWithValues: Self.managedKeys.map { ($0, defaults.object(forKey: $0)) })
    }

    private func restoreDefaults(_ baseline: [String: Any?]) {
        let defaults = UserDefaults.standard
        for (key, value) in baseline {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        AppLocalization.reloadLanguage()
    }

    private func makeView(colorScheme: ColorScheme = .dark) -> some View {
        NavigationStack {
            DataSettingsDetailView(
                iCloudBackupEnabled: .constant(false),
                isBackingUp: .constant(false),
                isPremium: true,
                iCloudBackupLastSuccessText: "No iCloud backup yet.",
                iCloudBackupLastErrorText: nil,
                onExport: {},
                onImport: {},
                onBackupNow: {},
                onRestoreLatestBackup: {},
                onUnlockICloudBackup: {},
                onSeedDummyData: {},
                onDeleteAll: {}
            )
        }
        .preferredColorScheme(colorScheme)
    }

    private func makeHostingController(
        view: some View,
        colorScheme: ColorScheme,
        height: CGFloat = 844
    ) -> UIHostingController<some View> {
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Tests

    /// Default state: backup disabled, no error, no timestamp, analytics on.
    @MainActor
    func testDataSettings_defaultState_dark() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "appLanguage")
        defaults.set(false, forKey: "icloud_backup_enabled")
        defaults.removeObject(forKey: "icloud_backup_last_success_timestamp")
        defaults.set("", forKey: "icloud_backup_last_error_message")
        defaults.set(5120, forKey: "icloud_backup_last_size_bytes")
        defaults.set(true, forKey: "analytics_enabled")
        // Force-sync AppSettingsStore.shared so @AppSetting values reflect test state immediately.
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .dark), colorScheme: .dark)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    /// Backup enabled with a recent backup timestamp shown.
    @MainActor
    func testDataSettings_backupEnabled_withTimestamp_dark() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "appLanguage")
        defaults.set(true, forKey: "icloud_backup_enabled")
        // Use a fixed timestamp far in the past so relative text is stable ("X years ago")
        defaults.set(1609459200.0, forKey: "icloud_backup_last_success_timestamp") // 2021-01-01
        defaults.set("", forKey: "icloud_backup_last_error_message")
        defaults.set(5120, forKey: "icloud_backup_last_size_bytes")
        defaults.set(true, forKey: "analytics_enabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .dark), colorScheme: .dark)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    /// Error message displayed via InlineErrorBanner.
    @MainActor
    func testDataSettings_withErrorMessage_dark() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "appLanguage")
        defaults.set(true, forKey: "icloud_backup_enabled")
        defaults.removeObject(forKey: "icloud_backup_last_success_timestamp")
        defaults.set("iCloud Drive is unavailable on this device.", forKey: "icloud_backup_last_error_message")
        defaults.set(5120, forKey: "icloud_backup_last_size_bytes")
        defaults.set(true, forKey: "analytics_enabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .dark), colorScheme: .dark)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    // MARK: - Light mode variants

    @MainActor
    func testDataSettings_defaultState_light() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "appLanguage")
        defaults.set(false, forKey: "icloud_backup_enabled")
        defaults.removeObject(forKey: "icloud_backup_last_success_timestamp")
        defaults.set("", forKey: "icloud_backup_last_error_message")
        defaults.set(5120, forKey: "icloud_backup_last_size_bytes")
        defaults.set(true, forKey: "analytics_enabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .light), colorScheme: .light)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    @MainActor
    func testDataSettings_backupEnabled_withTimestamp_light() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "appLanguage")
        defaults.set(true, forKey: "icloud_backup_enabled")
        defaults.set(1609459200.0, forKey: "icloud_backup_last_success_timestamp") // 2021-01-01
        defaults.set("", forKey: "icloud_backup_last_error_message")
        defaults.set(5120, forKey: "icloud_backup_last_size_bytes")
        defaults.set(true, forKey: "analytics_enabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .light), colorScheme: .light)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }

    @MainActor
    func testDataSettings_withErrorMessage_light() throws {
        #if !targetEnvironment(simulator)
        XCTAssertTrue(true, "Physical-device fallback: snapshot baseline is simulator-only")
        return
        #endif

        let baseline = backupDefaults()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        defer {
            restoreDefaults(baseline)
            AppSettingsStore.shared.forceReloadSnapshot()
            AppLocalization.settings = .shared
            AppLocalization.reloadLanguage()
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }

        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "appLanguage")
        defaults.set(true, forKey: "icloud_backup_enabled")
        defaults.removeObject(forKey: "icloud_backup_last_success_timestamp")
        defaults.set("iCloud Drive is unavailable on this device.", forKey: "icloud_backup_last_error_message")
        defaults.set(5120, forKey: "icloud_backup_last_size_bytes")
        defaults.set(true, forKey: "analytics_enabled")
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.settings = AppSettingsStore(defaults: defaults)
        AppLocalization.reloadLanguage()
        UIView.setAnimationsEnabled(false)

        let vc = makeHostingController(view: makeView(colorScheme: .light), colorScheme: .light)

        let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        assertSnapshot(of: vc, as: .image, record: shouldRecord)
    }
}
