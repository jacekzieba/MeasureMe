import Foundation

struct AppSettingsSnapshot: Sendable {
    struct Profile: Sendable {
        var userName: String
        var userAge: Int
        var userGender: String
        var manualHeight: Double
        var unitsSystem: String
    }

    struct Home: Sendable {
        var showLastPhotosOnHome: Bool
        var showMeasurementsOnHome: Bool
        var showHealthMetricsOnHome: Bool
        var showStreakOnHome: Bool
        var homePinnedActionRaw: String
        var homeTabScrollOffset: Double
        var homePhotoMetricSyncLastDate: Double
        var homePhotoMetricSyncLastID: String
        var settingsOpenTrackedMeasurements: Bool
        var settingsOpenReminders: Bool
        var settingsOpenHomeSettings: Bool
    }

    struct HomeLayout: Sendable {
        var layoutSchemaVersion: Int
        var layoutData: Data?
    }

    struct Onboarding: Sendable {
        var hasCompletedOnboarding: Bool
        var onboardingSkippedHealthKit: Bool
        var onboardingSkippedReminders: Bool
        var onboardingViewedICloudBackupOffer: Bool
        var onboardingSkippedICloudBackup: Bool
        var onboardingChecklistShow: Bool
        var onboardingChecklistCollapsed: Bool
        var onboardingChecklistHideCompleted: Bool
        var onboardingChecklistMetricsCompleted: Bool
        var onboardingChecklistPremiumExplored: Bool
        var onboardingPrimaryGoal: String
        /// v2: true after the post-onboarding activation screen has been seen/dismissed.
        /// Existing users who have already completed onboarding get this set to true via migration.
        var onboardingActivationCompleted: Bool = false
        /// v2: set to true by OnboardingActivationView (manual path) to trigger QuickAdd on HomeView appear.
        var activationTriggerQuickAdd: Bool = false
    }

    struct Health: Sendable {
        var isSyncEnabled: Bool
        var healthkitLastImport: Double
        var healthkitSyncWeight: Bool
        var healthkitSyncBodyFat: Bool
        var healthkitSyncHeight: Bool
        var healthkitSyncLeanBodyMass: Bool
        var healthkitSyncWaist: Bool
        var healthkitInitialHistoricalImport: Bool
        var healthIndicatorsV2Migrated: Bool
    }

    struct Indicators: Sendable {
        var showWHtROnHome: Bool
        var showRFMOnHome: Bool
        var showBMIOnHome: Bool
        var showBodyFatOnHome: Bool
        var showLeanMassOnHome: Bool
        var showWHROnHome: Bool
        var showWaistRiskOnHome: Bool
        var showABSIOnHome: Bool
        var showBodyShapeScoreOnHome: Bool
        var showCentralFatRiskOnHome: Bool
        var showConicityOnHome: Bool
        var showPhysiqueSWR: Bool
        var showPhysiqueCWR: Bool
        var showPhysiqueSHR: Bool
        var showPhysiqueHWR: Bool
        var showPhysiqueBWR: Bool
        var showPhysiqueWHtR: Bool
        var showPhysiqueBodyFat: Bool
        var showPhysiqueRFM: Bool
    }

    struct Experience: Sendable {
        var appAppearance: String
        var animationsEnabled: Bool
        var hapticsEnabled: Bool
        var appLanguage: String
        var quickAddHintDismissed: Bool
        var photosFilterTag: String
        var saveUnchangedQuickAdd: Bool
        var hasCustomizedMetrics: Bool
    }

    struct Premium: Sendable {
        var premiumEntitlement: Bool
        var premiumFirstLaunchDate: Double
        var premiumLastNagDate: Double
    }

    struct Diagnostics: Sendable {
        var diagnosticsLoggingEnabled: Bool
        var crashReporterHasUnreported: Bool
        var databaseEncryptionProtectionVersion: String?
    }

    struct Notifications: Sendable {
        var measurementRemindersData: Data?
        var notificationsEnabled: Bool
        var smartEnabled: Bool
        var smartDays: Int
        var smartTime: Double
        var lastLogDate: Double
        var lastPhotoDate: Double
        var photoRemindersEnabled: Bool
        var goalAchievedEnabled: Bool
        var importNotificationsEnabled: Bool
        var perMetricSmartEnabled: Bool
        var aiNotificationsEnabled: Bool
        var aiWeeklyDigestEnabled: Bool
        var aiTrendShiftEnabled: Bool
        var aiGoalMilestonesEnabled: Bool
        var aiRoundNumbersEnabled: Bool
        var aiConsistencyEnabled: Bool
        var aiDigestWeekday: Int
        var aiDigestTime: Double
        var aiLastSentTimestamps: Data?
        var aiMutedTypes: Data?
    }

    struct Analytics: Sendable {
        var analyticsEnabled: Bool
        var firstMetricAddedTracked: Bool
        var firstPhotoAddedTracked: Bool
        var appleIntelligenceEnabled: Bool
    }

    struct ICloudBackup: Sendable {
        var isEnabled: Bool
        var lastSuccessTimestamp: Double
        var lastErrorMessage: String
        var autoRestoreCompleted: Bool
        var lastBackupSizeBytes: Int64
    }

    struct InternalState: Sendable {
        var settingsSchemaVersion: Int
    }

    var profile: Profile
    var home: Home
    var homeLayout: HomeLayout
    var onboarding: Onboarding
    var health: Health
    var indicators: Indicators
    var experience: Experience
    var premium: Premium
    var diagnostics: Diagnostics
    var notifications: Notifications
    var analytics: Analytics
    var iCloudBackup: ICloudBackup
    var internalState: InternalState

    static let registeredDefaults: [String: Any] = [
        AppSettingsKeys.Onboarding.hasCompletedOnboarding: false,
        AppSettingsKeys.Profile.userName: "",
        AppSettingsKeys.Profile.userAge: 0,
        AppSettingsKeys.Metrics.weightEnabled: true,
        AppSettingsKeys.Metrics.waistEnabled: true,
        AppSettingsKeys.Metrics.bodyFatEnabled: true,
        AppSettingsKeys.Metrics.leanBodyMassEnabled: true,
        AppSettingsKeys.Profile.unitsSystem: "metric",
        AppSettingsKeys.Experience.appAppearance: AppAppearance.dark.rawValue,
        AppSettingsKeys.Experience.animationsEnabled: true,
        AppSettingsKeys.Experience.hapticsEnabled: true,
        AppSettingsKeys.Experience.saveUnchangedQuickAdd: false,
        AppSettingsKeys.Notifications.photoRemindersEnabled: true,
        AppSettingsKeys.Notifications.goalAchievedEnabled: true,
        AppSettingsKeys.Notifications.importNotificationsEnabled: true,
        AppSettingsKeys.Notifications.perMetricSmartEnabled: true,
        AppSettingsKeys.Notifications.aiNotificationsEnabled: true,
        AppSettingsKeys.Notifications.aiWeeklyDigestEnabled: true,
        AppSettingsKeys.Notifications.aiTrendShiftEnabled: true,
        AppSettingsKeys.Notifications.aiGoalMilestonesEnabled: true,
        AppSettingsKeys.Notifications.aiRoundNumbersEnabled: true,
        AppSettingsKeys.Notifications.aiConsistencyEnabled: true,
        AppSettingsKeys.Notifications.aiDigestWeekday: 1,
        AppSettingsKeys.Onboarding.onboardingSkippedHealthKit: false,
        AppSettingsKeys.Onboarding.onboardingSkippedReminders: false,
        AppSettingsKeys.Onboarding.onboardingViewedICloudBackupOffer: false,
        AppSettingsKeys.Onboarding.onboardingSkippedICloudBackup: false,
        AppSettingsKeys.Onboarding.onboardingChecklistShow: true,
        AppSettingsKeys.Onboarding.onboardingChecklistCollapsed: false,
        AppSettingsKeys.Onboarding.onboardingChecklistHideCompleted: false,
        AppSettingsKeys.Onboarding.onboardingChecklistMetricsCompleted: false,
        AppSettingsKeys.Onboarding.onboardingChecklistPremiumExplored: false,
        AppSettingsKeys.Home.settingsOpenTrackedMeasurements: false,
        AppSettingsKeys.Home.settingsOpenReminders: false,
        AppSettingsKeys.Home.homeLayoutSchemaVersion: HomeLayoutSnapshot.currentSchemaVersion,
        AppSettingsKeys.Experience.appLanguage: "system",
        AppSettingsKeys.Analytics.analyticsEnabled: true,
        AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled: true,
        AppSettingsKeys.Health.healthkitSyncWeight: true,
        AppSettingsKeys.Health.healthkitSyncBodyFat: true,
        AppSettingsKeys.Health.healthkitSyncHeight: true,
        AppSettingsKeys.Health.healthkitSyncLeanBodyMass: true,
        AppSettingsKeys.Health.healthkitSyncWaist: true,
        AppSettingsKeys.Home.showStreakOnHome: true,
        AppSettingsKeys.Notifications.smartEnabled: false,
        AppSettingsKeys.Health.healthIndicatorsV2Migrated: false,
        AppSettingsKeys.Indicators.showConicityOnHome: true,
        AppSettingsKeys.Analytics.appleIntelligenceEnabled: true,
        AppSettingsKeys.ICloudBackup.isEnabled: false,
        AppSettingsKeys.ICloudBackup.autoRestoreCompleted: false,
        AppSettingsKeys.Onboarding.onboardingActivationCompleted: false,
        AppSettingsKeys.Onboarding.activationTriggerQuickAdd: false
    ]

    static func load(from defaults: UserDefaults) -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            profile: .init(
                userName: defaults.string(forKey: AppSettingsKeys.Profile.userName) ?? "",
                userAge: defaults.integer(forKey: AppSettingsKeys.Profile.userAge),
                userGender: defaults.string(forKey: AppSettingsKeys.Profile.userGender) ?? "notSpecified",
                manualHeight: defaults.double(forKey: AppSettingsKeys.Profile.manualHeight),
                unitsSystem: defaults.string(forKey: AppSettingsKeys.Profile.unitsSystem) ?? "metric"
            ),
            home: .init(
                showLastPhotosOnHome: defaults.object(forKey: AppSettingsKeys.Home.showLastPhotosOnHome) as? Bool ?? true,
                showMeasurementsOnHome: defaults.object(forKey: AppSettingsKeys.Home.showMeasurementsOnHome) as? Bool ?? true,
                showHealthMetricsOnHome: defaults.object(forKey: AppSettingsKeys.Home.showHealthMetricsOnHome) as? Bool ?? true,
                showStreakOnHome: defaults.object(forKey: AppSettingsKeys.Home.showStreakOnHome) as? Bool ?? true,
                homePinnedActionRaw: defaults.string(forKey: AppSettingsKeys.Home.homePinnedAction) ?? "",
                homeTabScrollOffset: defaults.double(forKey: AppSettingsKeys.Home.homeTabScrollOffset),
                homePhotoMetricSyncLastDate: defaults.double(forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastDate),
                homePhotoMetricSyncLastID: defaults.string(forKey: AppSettingsKeys.Home.homePhotoMetricSyncLastID) ?? "",
                settingsOpenTrackedMeasurements: defaults.bool(forKey: AppSettingsKeys.Home.settingsOpenTrackedMeasurements),
                settingsOpenReminders: defaults.bool(forKey: AppSettingsKeys.Home.settingsOpenReminders),
                settingsOpenHomeSettings: defaults.bool(forKey: AppSettingsKeys.Home.settingsOpenHomeSettings)
            ),
            homeLayout: .init(
                layoutSchemaVersion: max(defaults.integer(forKey: AppSettingsKeys.Home.homeLayoutSchemaVersion), HomeLayoutSnapshot.currentSchemaVersion),
                layoutData: defaults.data(forKey: AppSettingsKeys.Home.homeLayoutData)
            ),
            onboarding: .init(
                hasCompletedOnboarding: defaults.bool(forKey: AppSettingsKeys.Onboarding.hasCompletedOnboarding),
                onboardingSkippedHealthKit: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingSkippedHealthKit),
                onboardingSkippedReminders: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingSkippedReminders),
                onboardingViewedICloudBackupOffer: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingViewedICloudBackupOffer),
                onboardingSkippedICloudBackup: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingSkippedICloudBackup),
                onboardingChecklistShow: defaults.object(forKey: AppSettingsKeys.Onboarding.onboardingChecklistShow) as? Bool ?? true,
                onboardingChecklistCollapsed: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingChecklistCollapsed),
                onboardingChecklistHideCompleted: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingChecklistHideCompleted),
                onboardingChecklistMetricsCompleted: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingChecklistMetricsCompleted),
                onboardingChecklistPremiumExplored: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingChecklistPremiumExplored),
                onboardingPrimaryGoal: defaults.string(forKey: AppSettingsKeys.Onboarding.onboardingPrimaryGoal) ?? "",
                onboardingActivationCompleted: defaults.bool(forKey: AppSettingsKeys.Onboarding.onboardingActivationCompleted),
                activationTriggerQuickAdd: defaults.bool(forKey: AppSettingsKeys.Onboarding.activationTriggerQuickAdd)
            ),
            health: .init(
                isSyncEnabled: defaults.bool(forKey: AppSettingsKeys.Health.isSyncEnabled),
                healthkitLastImport: defaults.double(forKey: AppSettingsKeys.Health.healthkitLastImport),
                healthkitSyncWeight: defaults.object(forKey: AppSettingsKeys.Health.healthkitSyncWeight) as? Bool ?? true,
                healthkitSyncBodyFat: defaults.object(forKey: AppSettingsKeys.Health.healthkitSyncBodyFat) as? Bool ?? true,
                healthkitSyncHeight: defaults.object(forKey: AppSettingsKeys.Health.healthkitSyncHeight) as? Bool ?? true,
                healthkitSyncLeanBodyMass: defaults.object(forKey: AppSettingsKeys.Health.healthkitSyncLeanBodyMass) as? Bool ?? true,
                healthkitSyncWaist: defaults.object(forKey: AppSettingsKeys.Health.healthkitSyncWaist) as? Bool ?? true,
                healthkitInitialHistoricalImport: defaults.bool(forKey: AppSettingsKeys.Health.healthkitInitialHistoricalImport),
                healthIndicatorsV2Migrated: defaults.bool(forKey: AppSettingsKeys.Health.healthIndicatorsV2Migrated)
            ),
            indicators: .init(
                showWHtROnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showWHtROnHome) as? Bool ?? true,
                showRFMOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showRFMOnHome) as? Bool ?? true,
                showBMIOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showBMIOnHome) as? Bool ?? true,
                showBodyFatOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showBodyFatOnHome) as? Bool ?? true,
                showLeanMassOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showLeanMassOnHome) as? Bool ?? true,
                showWHROnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showWHROnHome) as? Bool ?? true,
                showWaistRiskOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showWaistRiskOnHome) as? Bool ?? true,
                showABSIOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showABSIOnHome) as? Bool ?? true,
                showBodyShapeScoreOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showBodyShapeScoreOnHome) as? Bool ?? true,
                showCentralFatRiskOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showCentralFatRiskOnHome) as? Bool ?? true,
                showConicityOnHome: defaults.object(forKey: AppSettingsKeys.Indicators.showConicityOnHome) as? Bool ?? true,
                showPhysiqueSWR: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueSWR) as? Bool ?? true,
                showPhysiqueCWR: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueCWR) as? Bool ?? true,
                showPhysiqueSHR: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueSHR) as? Bool ?? true,
                showPhysiqueHWR: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueHWR) as? Bool ?? true,
                showPhysiqueBWR: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueBWR) as? Bool ?? true,
                showPhysiqueWHtR: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueWHtR) as? Bool ?? true,
                showPhysiqueBodyFat: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueBodyFat) as? Bool ?? true,
                showPhysiqueRFM: defaults.object(forKey: AppSettingsKeys.Indicators.showPhysiqueRFM) as? Bool ?? true
            ),
            experience: .init(
                appAppearance: defaults.string(forKey: AppSettingsKeys.Experience.appAppearance) ?? AppAppearance.dark.rawValue,
                animationsEnabled: defaults.object(forKey: AppSettingsKeys.Experience.animationsEnabled) as? Bool ?? true,
                hapticsEnabled: defaults.object(forKey: AppSettingsKeys.Experience.hapticsEnabled) as? Bool ?? true,
                appLanguage: defaults.string(forKey: AppSettingsKeys.Experience.appLanguage) ?? "system",
                quickAddHintDismissed: defaults.bool(forKey: AppSettingsKeys.Experience.quickAddHintDismissed),
                photosFilterTag: defaults.string(forKey: AppSettingsKeys.Experience.photosFilterTag) ?? "",
                saveUnchangedQuickAdd: defaults.bool(forKey: AppSettingsKeys.Experience.saveUnchangedQuickAdd),
                hasCustomizedMetrics: defaults.bool(forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)
            ),
            premium: .init(
                premiumEntitlement: defaults.bool(forKey: AppSettingsKeys.Premium.entitlement),
                premiumFirstLaunchDate: defaults.double(forKey: AppSettingsKeys.Premium.firstLaunchDate),
                premiumLastNagDate: defaults.double(forKey: AppSettingsKeys.Premium.lastNagDate)
            ),
            diagnostics: .init(
                diagnosticsLoggingEnabled: defaults.object(forKey: AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled) as? Bool ?? true,
                crashReporterHasUnreported: defaults.bool(forKey: AppSettingsKeys.Diagnostics.crashReporterHasUnreported),
                databaseEncryptionProtectionVersion: defaults.string(forKey: AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion)
            ),
            notifications: .init(
                measurementRemindersData: defaults.data(forKey: AppSettingsKeys.Notifications.reminders),
                notificationsEnabled: defaults.bool(forKey: AppSettingsKeys.Notifications.notificationsEnabled),
                smartEnabled: defaults.bool(forKey: AppSettingsKeys.Notifications.smartEnabled),
                smartDays: max(defaults.integer(forKey: AppSettingsKeys.Notifications.smartDays), 0),
                smartTime: defaults.double(forKey: AppSettingsKeys.Notifications.smartTime),
                lastLogDate: defaults.double(forKey: AppSettingsKeys.Notifications.lastLogDate),
                lastPhotoDate: defaults.double(forKey: AppSettingsKeys.Notifications.lastPhotoDate),
                photoRemindersEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.photoRemindersEnabled) as? Bool ?? true,
                goalAchievedEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.goalAchievedEnabled) as? Bool ?? true,
                importNotificationsEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.importNotificationsEnabled) as? Bool ?? true,
                perMetricSmartEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.perMetricSmartEnabled) as? Bool ?? true,
                aiNotificationsEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.aiNotificationsEnabled) as? Bool ?? true,
                aiWeeklyDigestEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.aiWeeklyDigestEnabled) as? Bool ?? true,
                aiTrendShiftEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.aiTrendShiftEnabled) as? Bool ?? true,
                aiGoalMilestonesEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.aiGoalMilestonesEnabled) as? Bool ?? true,
                aiRoundNumbersEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.aiRoundNumbersEnabled) as? Bool ?? true,
                aiConsistencyEnabled: defaults.object(forKey: AppSettingsKeys.Notifications.aiConsistencyEnabled) as? Bool ?? true,
                aiDigestWeekday: max(defaults.integer(forKey: AppSettingsKeys.Notifications.aiDigestWeekday), 1),
                aiDigestTime: defaults.double(forKey: AppSettingsKeys.Notifications.aiDigestTime),
                aiLastSentTimestamps: defaults.data(forKey: AppSettingsKeys.Notifications.aiLastSentTimestamps),
                aiMutedTypes: defaults.data(forKey: AppSettingsKeys.Notifications.aiMutedTypes)
            ),
            analytics: .init(
                analyticsEnabled: defaults.object(forKey: AppSettingsKeys.Analytics.analyticsEnabled) as? Bool ?? true,
                firstMetricAddedTracked: defaults.bool(forKey: AppSettingsKeys.Analytics.firstMetricAddedTracked),
                firstPhotoAddedTracked: defaults.bool(forKey: AppSettingsKeys.Analytics.firstPhotoAddedTracked),
                appleIntelligenceEnabled: defaults.object(forKey: AppSettingsKeys.Analytics.appleIntelligenceEnabled) as? Bool ?? true
            ),
            iCloudBackup: .init(
                isEnabled: defaults.bool(forKey: AppSettingsKeys.ICloudBackup.isEnabled),
                lastSuccessTimestamp: defaults.double(forKey: AppSettingsKeys.ICloudBackup.lastSuccessTimestamp),
                lastErrorMessage: defaults.string(forKey: AppSettingsKeys.ICloudBackup.lastErrorMessage) ?? "",
                autoRestoreCompleted: defaults.bool(forKey: AppSettingsKeys.ICloudBackup.autoRestoreCompleted),
                lastBackupSizeBytes: Int64(defaults.integer(forKey: AppSettingsKeys.ICloudBackup.lastBackupSizeBytes))
            ),
            internalState: .init(
                settingsSchemaVersion: defaults.integer(forKey: AppSettingsKeys.settingsSchemaVersion)
            )
        )
    }
}
