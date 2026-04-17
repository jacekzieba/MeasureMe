import Foundation

enum AppSettingsMigration {
    private static let currentSchemaVersion = 6

    static func applyIfNeeded(defaults: UserDefaults) {
        let schemaVersion = defaults.integer(forKey: AppSettingsKeys.settingsSchemaVersion)
        guard schemaVersion < currentSchemaVersion else { return }

        migrateUnitsSystemIfNeeded(defaults: defaults)
        migrateHomeLayoutIfNeeded(defaults: defaults)
        migrateHomePinnedActionIfNeeded(defaults: defaults)
        migrateActivationCompletedIfNeeded(defaults: defaults)
        migrateOnboardingFlowVersionIfNeeded(defaults: defaults)
        migrateActivationStateIfNeeded(defaults: defaults)
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
        var layout = HomeLayoutSnapshot.defaultV1(using: settingsSnapshot)
        if defaults.object(forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow) != nil {
            layout.setVisibility(defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow), for: .activationHub)
        }
        guard let encoded = try? JSONEncoder().encode(layout) else { return }

        defaults.set(HomeLayoutSnapshot.currentSchemaVersion, forKey: AppSettingsKeys.Home.homeLayoutSchemaVersion)
        defaults.set(encoded, forKey: AppSettingsKeys.Home.homeLayoutData)
    }

    /// Existing users who already completed the old onboarding must have
    /// onboardingActivationCompleted = true so they never see the v2 activation screen.
    private static func migrateActivationCompletedIfNeeded(defaults: UserDefaults) {
        let activationKey = AppSettingsKeys.Onboarding.onboardingActivationCompleted
        guard defaults.object(forKey: activationKey) == nil else { return }
        let hasCompleted = defaults.bool(forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding)
        if hasCompleted {
            defaults.set(true, forKey: activationKey)
        }
    }

    private static func migrateHomePinnedActionIfNeeded(defaults: UserDefaults) {
        if let currentRaw = defaults.string(forKey: AppSettingsKeys.Home.homePinnedAction),
           currentRaw == "finishSetup" {
            let comparePhotosUnlocked = defaults.double(forKey: AppSettingsKeys.Notifications.lastPhotoDate) > 0
            defaults.set(
                comparePhotosUnlocked ? HomePinnedAction.comparePhotos.rawValue : HomePinnedAction.addMeasurement.rawValue,
                forKey: AppSettingsKeys.Home.homePinnedAction
            )
            return
        }

        guard defaults.object(forKey: AppSettingsKeys.Home.homePinnedAction) == nil else { return }
        defaults.set(HomePinnedAction.addMeasurement.rawValue, forKey: AppSettingsKeys.Home.homePinnedAction)
    }

    private static func migrateOnboardingFlowVersionIfNeeded(defaults: UserDefaults) {
        let versionKey = AppSettingsKeys.Onboarding.onboardingFlowVersion
        guard defaults.object(forKey: versionKey) == nil else { return }

        let hasCompleted = defaults.bool(forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding)
        defaults.set(hasCompleted ? 1 : 0, forKey: versionKey)
    }

    private static func migrateActivationStateIfNeeded(defaults: UserDefaults) {
        guard defaults.bool(forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding) else { return }

        if defaults.object(forKey: AppSettingsKeys.Onboarding.activationCurrentTaskID) == nil {
            defaults.set("", forKey: AppSettingsKeys.Onboarding.activationCurrentTaskID)
        }
        if defaults.object(forKey: AppSettingsKeys.Onboarding.activationCompletedTaskIDs) == nil {
            defaults.set("", forKey: AppSettingsKeys.Onboarding.activationCompletedTaskIDs)
        }
        if defaults.object(forKey: AppSettingsKeys.Onboarding.activationSkippedTaskIDs) == nil {
            defaults.set("", forKey: AppSettingsKeys.Onboarding.activationSkippedTaskIDs)
        }
        if defaults.object(forKey: AppSettingsKeys.Onboarding.activationIsDismissed) == nil {
            defaults.set(true, forKey: AppSettingsKeys.Onboarding.activationIsDismissed)
        }

        defaults.set(false, forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow)
    }
}
