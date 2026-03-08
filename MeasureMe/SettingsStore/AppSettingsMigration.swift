import Foundation

enum AppSettingsMigration {
    private static let currentSchemaVersion = 3

    static func applyIfNeeded(defaults: UserDefaults) {
        let schemaVersion = defaults.integer(forKey: AppSettingsKeys.settingsSchemaVersion)
        guard schemaVersion < currentSchemaVersion else { return }

        migrateUnitsSystemIfNeeded(defaults: defaults)
        migrateHomeLayoutIfNeeded(defaults: defaults)
        migrateHomePinnedActionIfNeeded(defaults: defaults)
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

    private static func migrateHomeLayoutIfNeeded(defaults: UserDefaults) {
        guard defaults.data(forKey: AppSettingsKeys.Home.homeLayoutData) == nil else { return }

        let settingsSnapshot = AppSettingsSnapshot.load(from: defaults)
        let layout = HomeLayoutSnapshot.defaultV1(using: settingsSnapshot)
        guard let encoded = try? JSONEncoder().encode(layout) else { return }

        defaults.set(HomeLayoutSnapshot.currentSchemaVersion, forKey: AppSettingsKeys.Home.homeLayoutSchemaVersion)
        defaults.set(encoded, forKey: AppSettingsKeys.Home.homeLayoutData)
    }

    private static func migrateHomePinnedActionIfNeeded(defaults: UserDefaults) {
        guard defaults.object(forKey: AppSettingsKeys.Home.homePinnedAction) == nil else { return }
        let shouldFinishSetup = defaults.object(forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow) as? Bool ?? true
        defaults.set(
            shouldFinishSetup ? HomePinnedAction.finishSetup.rawValue : HomePinnedAction.addMeasurement.rawValue,
            forKey: AppSettingsKeys.Home.homePinnedAction
        )
    }
}
