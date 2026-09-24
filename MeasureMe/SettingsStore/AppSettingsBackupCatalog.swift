import Foundation

/// Decides which persisted settings travel with an iCloud backup.
///
/// The rule: a setting the person *chose* is backed up. State the app derived (timestamps,
/// counters, sync anchors, one-shot flags), entitlements, and anything that only makes sense on
/// one device stays out.
///
/// Every key in `AppSettingsKeys` must land in exactly one bucket. `AppSettingsBackupCatalogTests`
/// fails when a key is in neither, so a new setting cannot quietly miss the backup.
nonisolated enum AppSettingsBackupCatalog {
    enum Classification: Equatable {
        case included
        case excluded
    }

    static func classification(ofKey key: String) -> Classification? {
        if includedKeySet.contains(key) { return .included }
        if includedKeyPrefixes.contains(where: { key.hasPrefix($0) }) { return .included }
        if excludedKeys.contains(key) { return .excluded }
        if excludedKeyPrefixes.contains(where: { key.hasPrefix($0) }) { return .excluded }
        return nil
    }

    static let includedKeySet = Set(includedKeys)

    static let includedKeys: [String] = [
        // Profile
        AppSettingsKeys.Profile.userName,
        AppSettingsKeys.Profile.userAge,
        AppSettingsKeys.Profile.userGender,
        AppSettingsKeys.Profile.manualHeight,
        AppSettingsKeys.Profile.unitsSystem,
        AppSettingsKeys.Profile.profilePhotoData,

        // Home
        AppSettingsKeys.Home.showLastPhotosOnHome,
        AppSettingsKeys.Home.showMeasurementsOnHome,
        AppSettingsKeys.Home.showHealthMetricsOnHome,
        AppSettingsKeys.Home.showStreakOnHome,
        AppSettingsKeys.Home.homePinnedAction,
        AppSettingsKeys.Home.homeLayoutSchemaVersion,
        AppSettingsKeys.Home.homeLayoutData,
        AppSettingsKeys.Home.keyMetrics,

        // Onboarding choices and the flags that stop first-run screens from replaying
        AppSettingsKeys.Onboarding.hasCompletedOnboarding,
        AppSettingsKeys.Onboarding.onboardingPrimaryGoal,
        AppSettingsKeys.Onboarding.onboardingChecklistShow,
        AppSettingsKeys.Onboarding.onboardingChecklistCollapsed,
        AppSettingsKeys.Onboarding.onboardingChecklistHideCompleted,
        AppSettingsKeys.Onboarding.onboardingActivationCompleted,
        AppSettingsKeys.Onboarding.activationIsDismissed,

        // Health sync choices. `isSyncEnabled` is safe to restore on a new device:
        // `HealthKitManager.reconcileStoredSyncState()` switches it back off without authorization.
        AppSettingsKeys.Health.isSyncEnabled,
        AppSettingsKeys.Health.healthkitSyncWeight,
        AppSettingsKeys.Health.healthkitSyncBodyFat,
        AppSettingsKeys.Health.healthkitSyncHeight,
        AppSettingsKeys.Health.healthkitSyncLeanBodyMass,
        AppSettingsKeys.Health.healthkitSyncWaist,

        // Indicators
        AppSettingsKeys.Indicators.showWHtROnHome,
        AppSettingsKeys.Indicators.showRFMOnHome,
        AppSettingsKeys.Indicators.showBMIOnHome,
        AppSettingsKeys.Indicators.showBodyFatOnHome,
        AppSettingsKeys.Indicators.showLeanMassOnHome,
        AppSettingsKeys.Indicators.showWHROnHome,
        AppSettingsKeys.Indicators.showWaistRiskOnHome,
        AppSettingsKeys.Indicators.showABSIOnHome,
        AppSettingsKeys.Indicators.showBodyShapeScoreOnHome,
        AppSettingsKeys.Indicators.showCentralFatRiskOnHome,
        AppSettingsKeys.Indicators.showConicityOnHome,
        AppSettingsKeys.Indicators.showPhysiqueSWR,
        AppSettingsKeys.Indicators.showPhysiqueCWR,
        AppSettingsKeys.Indicators.showPhysiqueSHR,
        AppSettingsKeys.Indicators.showPhysiqueHWR,
        AppSettingsKeys.Indicators.showPhysiqueBWR,
        AppSettingsKeys.Indicators.showPhysiqueWHtR,
        AppSettingsKeys.Indicators.showPhysiqueBodyFat,
        AppSettingsKeys.Indicators.showPhysiqueRFM,

        // Experience
        AppSettingsKeys.Experience.appAppearance,
        AppSettingsKeys.Experience.animationsEnabled,
        AppSettingsKeys.Experience.hapticsEnabled,
        AppSettingsKeys.Experience.appLanguage,
        AppSettingsKeys.Experience.saveUnchangedQuickAdd,
        AppSettingsKeys.Experience.hasCustomizedMetrics,

        // Photos
        AppSettingsKeys.Photos.gridLayoutMode,
        AppSettingsKeys.Photos.overlayPose,
        AppSettingsKeys.Photos.overlayOpacity,

        // Privacy and diagnostics
        AppSettingsKeys.Privacy.requireBiometricForPhotos,
        AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled,

        // Notification preferences
        AppSettingsKeys.Notifications.reminders,
        AppSettingsKeys.Notifications.notificationsEnabled,
        AppSettingsKeys.Notifications.smartEnabled,
        AppSettingsKeys.Notifications.smartDays,
        AppSettingsKeys.Notifications.smartTime,
        AppSettingsKeys.Notifications.photoRemindersEnabled,
        AppSettingsKeys.Notifications.goalAchievedEnabled,
        AppSettingsKeys.Notifications.importNotificationsEnabled,
        AppSettingsKeys.Notifications.perMetricSmartEnabled,
        AppSettingsKeys.Notifications.aiNotificationsEnabled,
        AppSettingsKeys.Notifications.aiWeeklyDigestEnabled,
        AppSettingsKeys.Notifications.aiTrendShiftEnabled,
        AppSettingsKeys.Notifications.aiGoalMilestonesEnabled,
        AppSettingsKeys.Notifications.aiRoundNumbersEnabled,
        AppSettingsKeys.Notifications.aiConsistencyEnabled,
        AppSettingsKeys.Notifications.aiDigestWeekday,
        AppSettingsKeys.Notifications.aiDigestTime,
        AppSettingsKeys.Notifications.aiMutedTypes,

        // Analytics preferences
        AppSettingsKeys.Analytics.analyticsEnabled,
        AppSettingsKeys.Analytics.analyticsConsentDecided,
        AppSettingsKeys.Analytics.appleIntelligenceEnabled
    ] + AppSettingsKeys.Metrics.allEnabledKeys + [
        AppSettingsKeys.Metrics.activeOrder,
        AppSettingsKeys.Metrics.customOrder
    ]

    /// Keys built at runtime that are backed up anyway. `ICloudBackupService` writes one entry per
    /// custom metric it saves, so the set follows the definitions instead of a fixed list.
    static let includedKeyPrefixes: [String] = [
        AppSettingsKeys.Metrics.customEnabledPrefix
    ]

    static let excludedKeys: Set<String> = [
        // Migration bookkeeping and transient hand-offs
        AppSettingsKeys.settingsSchemaVersion,
        AppSettingsKeys.Entry.pendingAppEntryAction,
        AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent,
        AppSettingsKeys.Entry.pendingNavigationRoute,
        AppSettingsKeys.Profile.legacyUnitsSystem,

        // Home: scroll position, sync cursors, deep-link flags
        AppSettingsKeys.Home.homeTabScrollOffset,
        AppSettingsKeys.Home.homePhotoMetricSyncLastDate,
        AppSettingsKeys.Home.homePhotoMetricSyncLastID,
        AppSettingsKeys.Home.hasReviewedTrackedMetrics,
        AppSettingsKeys.Home.settingsOpenTrackedMeasurements,
        AppSettingsKeys.Home.settingsOpenReminders,
        AppSettingsKeys.Home.settingsOpenHomeSettings,
        AppSettingsKeys.Home.settingsOpenProfile,
        AppSettingsKeys.Home.settingsOpenHealth,

        // Onboarding progress on this device
        AppSettingsKeys.Onboarding.onboardingFlowVersion,
        AppSettingsKeys.Onboarding.onboardingSkippedHealthKit,
        AppSettingsKeys.Onboarding.onboardingSkippedReminders,
        AppSettingsKeys.Onboarding.onboardingViewedICloudBackupOffer,
        AppSettingsKeys.Onboarding.onboardingSkippedICloudBackup,
        AppSettingsKeys.Onboarding.onboardingChecklistMetricsCompleted,
        AppSettingsKeys.Onboarding.onboardingChecklistMetricsExplored,
        AppSettingsKeys.Onboarding.onboardingChecklistPremiumExplored,
        AppSettingsKeys.Onboarding.activationTriggerQuickAdd,
        AppSettingsKeys.Onboarding.activationCurrentTaskID,
        AppSettingsKeys.Onboarding.activationCompletedTaskIDs,
        AppSettingsKeys.Onboarding.activationSkippedTaskIDs,

        // HealthKit import state belongs to this device's Health database
        AppSettingsKeys.Health.healthkitLastImport,
        AppSettingsKeys.Health.healthkitInitialHistoricalImport,
        AppSettingsKeys.Health.healthIndicatorsV2Migrated,

        // Hints, filters and what's-new state
        AppSettingsKeys.Experience.quickAddHintDismissed,
        AppSettingsKeys.Experience.photosFilterTag,
        AppSettingsKeys.Experience.lastSeenWhatsNewVersion,

        // Entitlement comes from the App Store; nag timers are per device
        AppSettingsKeys.Premium.entitlement,
        AppSettingsKeys.Premium.firstLaunchDate,
        AppSettingsKeys.Premium.lastNagDate,
        AppSettingsKeys.Premium.lastAutomaticPromptDate,
        AppSettingsKeys.Premium.lastAutomaticPromptKind,

        // Crash reporting and storage protection are device state
        AppSettingsKeys.Diagnostics.crashReporterHasUnreported,
        AppSettingsKeys.Diagnostics.databaseEncryptionProtectionVersion,

        // Notification bookkeeping: what was sent and when
        AppSettingsKeys.Notifications.lastLogDate,
        AppSettingsKeys.Notifications.lastPhotoDate,
        AppSettingsKeys.Notifications.photoReminderStreak,
        AppSettingsKeys.Notifications.photoReminderNextFireDate,
        AppSettingsKeys.Notifications.perMetricLastDates,
        AppSettingsKeys.Notifications.detectedPatterns,
        AppSettingsKeys.Notifications.smartLastNotificationDate,
        AppSettingsKeys.Notifications.smartLastNotifiedMetric,
        AppSettingsKeys.Notifications.aiLastSentTimestamps,

        // The backup's own status describes this device's last run
        AppSettingsKeys.ICloudBackup.isEnabled,
        AppSettingsKeys.ICloudBackup.lastSuccessTimestamp,
        AppSettingsKeys.ICloudBackup.lastErrorMessage,
        AppSettingsKeys.ICloudBackup.autoRestoreCompleted,
        AppSettingsKeys.ICloudBackup.lastBackupSizeBytes,

        // Analytics milestone counters
        AppSettingsKeys.Analytics.firstMetricAddedTracked,
        AppSettingsKeys.Analytics.firstPhotoAddedTracked,
        AppSettingsKeys.Analytics.secondMetricAddedTracked,
        AppSettingsKeys.Analytics.secondPhotoAddedTracked,
        AppSettingsKeys.Analytics.firstCompareSessionTracked
    ]

    /// Keys built at runtime as `prefix + identifier`: per-metric anchors, per-goal flags, counters.
    static let excludedKeyPrefixes: [String] = [
        AppSettingsKeys.Health.healthkitAnchorPrefix,
        AppSettingsKeys.Health.healthkitLastProcessedPrefix,
        AppSettingsKeys.Premium.automaticPromptDismissalPrefix,
        AppSettingsKeys.Notifications.goalAchievementPrefix,
        AppSettingsKeys.Notifications.aiNotificationPrefix,
        AppSettingsKeys.Analytics.onboardingGoalSelectionStatPrefix
    ]
}
