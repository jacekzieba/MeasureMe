import Foundation

enum AppSettingsMigration {
    private static let currentSchemaVersion = 1

    static func applyIfNeeded(defaults: UserDefaults) {
        let schemaVersion = defaults.integer(forKey: AppSettingsKeys.settingsSchemaVersion)
        guard schemaVersion < currentSchemaVersion else { return }

        migrateUnitsSystemIfNeeded(defaults: defaults)
        defaults.set(currentSchemaVersion, forKey: AppSettingsKeys.settingsSchemaVersion)
    }

    private static func migrateUnitsSystemIfNeeded(defaults: UserDefaults) {
        guard let legacy = defaults.string(forKey: AppSettingsKeys.Profile.legacyUnitsSystem),
              !legacy.isEmpty else {
            defaults.removeObject(forKey: AppSettingsKeys.Profile.legacyUnitsSystem)
            return
        }

        let current = defaults.string(forKey: AppSettingsKeys.Profile.unitsSystem)
        if current == nil || current == "metric" {
            defaults.set(legacy, forKey: AppSettingsKeys.Profile.unitsSystem)
        }
        defaults.removeObject(forKey: AppSettingsKeys.Profile.legacyUnitsSystem)
    }
}
