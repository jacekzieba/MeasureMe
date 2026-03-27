import Foundation

enum AppSettingsKeys {
    static let settingsSchemaVersion = "settings_schema_version"

    enum Entry {
        static let pendingAppEntryAction = "pending_app_entry_action"
        static let pendingHealthKitSyncFromIntent = "pending_healthkit_sync_from_intent"
    }

    enum Profile {
        static let userName = "userName"
        static let userAge = "userAge"
        static let userGender = "userGender"
        static let manualHeight = "manualHeight"
        static let unitsSystem = "unitsSystem"
        static let legacyUnitsSystem = "units_system"
    }

    enum Home {
        static let showLastPhotosOnHome = "showLastPhotosOnHome"
        static let showMeasurementsOnHome = "showMeasurementsOnHome"
        static let showHealthMetricsOnHome = "showHealthMetricsOnHome"
        static let showStreakOnHome = "showStreakOnHome"
        static let homeLayoutSchemaVersion = "home_layout_schema_version"
        static let homeLayoutData = "home_layout_data"
        static let homePinnedAction = "home_pinned_action"
        static let homeTabScrollOffset = "home_tab_scroll_offset"
        static let homePhotoMetricSyncLastDate = "home_photo_metric_sync_last_date"
        static let homePhotoMetricSyncLastID = "home_photo_metric_sync_last_id"
        static let settingsOpenTrackedMeasurements = "settings_open_tracked_measurements"
        static let settingsOpenReminders = "settings_open_reminders"
        static let settingsOpenHomeSettings = "settings_open_home_settings"
    }

    enum Onboarding {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let onboardingSkippedHealthKit = "onboarding_skipped_healthkit"
        static let onboardingSkippedReminders = "onboarding_skipped_reminders"
        static let onboardingViewedICloudBackupOffer = "onboarding_viewed_icloud_backup_offer"
        static let onboardingSkippedICloudBackup = "onboarding_skipped_icloud_backup"
        static let onboardingChecklistShow = "onboarding_checklist_show"
        static let onboardingChecklistCollapsed = "onboarding_checklist_collapsed"
        static let onboardingChecklistHideCompleted = "onboarding_checklist_hide_completed"
        static let onboardingChecklistMetricsCompleted = "onboarding_checklist_metrics_completed"
        static let onboardingChecklistPremiumExplored = "onboarding_checklist_premium_explored"
        static let onboardingPrimaryGoal = "onboarding_primary_goal"
    }

    enum Health {
        static let isSyncEnabled = "isSyncEnabled"
        static let healthkitLastImport = "healthkit_last_import"
        static let healthkitSyncWeight = "healthkit_sync_weight"
        static let healthkitSyncBodyFat = "healthkit_sync_bodyFat"
        static let healthkitSyncHeight = "healthkit_sync_height"
        static let healthkitSyncLeanBodyMass = "healthkit_sync_leanBodyMass"
        static let healthkitSyncWaist = "healthkit_sync_waist"
        static let healthkitInitialHistoricalImport = "healthkit_initial_historical_import_v1"
        static let healthkitAnchorPrefix = "healthkit_anchor_"
        static let healthkitLastProcessedPrefix = "healthkit_last_processed_"
        static let healthIndicatorsV2Migrated = "health_indicators_v2_migrated"
    }

    enum Indicators {
        static let showWHtROnHome = "showWHtROnHome"
        static let showRFMOnHome = "showRFMOnHome"
        static let showBMIOnHome = "showBMIOnHome"
        static let showBodyFatOnHome = "showBodyFatOnHome"
        static let showLeanMassOnHome = "showLeanMassOnHome"
        static let showWHROnHome = "showWHROnHome"
        static let showWaistRiskOnHome = "showWaistRiskOnHome"
        static let showABSIOnHome = "showABSIOnHome"
        static let showBodyShapeScoreOnHome = "showBodyShapeScoreOnHome"
        static let showCentralFatRiskOnHome = "showCentralFatRiskOnHome"
        static let showConicityOnHome = "showConicityOnHome"
        static let showPhysiqueSWR = "showPhysiqueSWR"
        static let showPhysiqueCWR = "showPhysiqueCWR"
        static let showPhysiqueSHR = "showPhysiqueSHR"
        static let showPhysiqueHWR = "showPhysiqueHWR"
        static let showPhysiqueBWR = "showPhysiqueBWR"
        static let showPhysiqueWHtR = "showPhysiqueWHtR"
        static let showPhysiqueBodyFat = "showPhysiqueBodyFat"
        static let showPhysiqueRFM = "showPhysiqueRFM"
    }

    enum Experience {
        static let appAppearance = "appAppearance"
        static let animationsEnabled = "animationsEnabled"
        static let hapticsEnabled = "hapticsEnabled"
        static let appLanguage = "appLanguage"
        static let quickAddHintDismissed = "quickAddHintDismissed"
        static let photosFilterTag = "photos_filter_tag"
        static let saveUnchangedQuickAdd = "save_unchanged_quick_add"
        static let hasCustomizedMetrics = "has_customized_metrics"
    }

    enum Premium {
        static let entitlement = "premium_entitlement"
        static let firstLaunchDate = "premium_first_launch_date"
        static let lastNagDate = "premium_last_nag_date"
    }

    enum Diagnostics {
        static let diagnosticsLoggingEnabled = "diagnostics_logging_enabled"
        static let crashReporterHasUnreported = "crashreporter_has_unreported"
        static let databaseEncryptionProtectionVersion = "database_encryption_protection_applied_version"
    }

    enum Notifications {
        static let reminders = "measurement_reminders"
        static let notificationsEnabled = "measurement_notifications_enabled"
        static let smartEnabled = "measurement_smart_enabled"
        static let smartDays = "measurement_smart_days"
        static let smartTime = "measurement_smart_time"
        static let lastLogDate = "measurement_last_log_date"
        static let lastPhotoDate = "photo_last_log_date"
        static let photoRemindersEnabled = "measurement_photo_reminders_enabled"
        static let goalAchievedEnabled = "measurement_goal_achieved_enabled"
        static let importNotificationsEnabled = "measurement_import_notifications_enabled"
        static let goalAchievementPrefix = "goal_achieved_"
        static let perMetricSmartEnabled = "smart_per_metric_enabled"
        static let perMetricLastDates = "smart_per_metric_last_dates"
        static let detectedPatterns = "smart_detected_patterns"
        static let smartLastNotificationDate = "smart_last_notification_date"
        static let smartLastNotifiedMetric = "smart_last_notified_metric"
    }

    enum ICloudBackup {
        static let isEnabled = "icloud_backup_enabled"
        static let lastSuccessTimestamp = "icloud_backup_last_success_timestamp"
        static let lastErrorMessage = "icloud_backup_last_error_message"
        static let autoRestoreCompleted = "icloud_backup_auto_restore_completed"
        static let lastBackupSizeBytes = "icloud_backup_last_size_bytes"
    }

    enum Analytics {
        static let analyticsEnabled = "analytics_enabled"
        static let firstMetricAddedTracked = "analytics_first_metric_added_tracked"
        static let firstPhotoAddedTracked = "analytics_first_photo_added_tracked"
        static let appleIntelligenceEnabled = "apple_intelligence_enabled"
        static let onboardingGoalSelectionStatPrefix = "onboarding_goal_selection_stat_"
    }

    enum Metrics {
        static let weightEnabled = "metric_weight_enabled"
        static let bodyFatEnabled = "metric_bodyFat_enabled"
        static let heightEnabled = "metric_height_enabled"
        static let leanBodyMassEnabled = "metric_nonFatMass_enabled"
        static let waistEnabled = "metric_waist_enabled"
        static let neckEnabled = "metric_neck_enabled"
        static let shouldersEnabled = "metric_shoulders_enabled"
        static let bustEnabled = "metric_bust_enabled"
        static let chestEnabled = "metric_chest_enabled"
        static let leftBicepEnabled = "metric_leftBicep_enabled"
        static let rightBicepEnabled = "metric_rightBicep_enabled"
        static let leftForearmEnabled = "metric_leftForearm_enabled"
        static let rightForearmEnabled = "metric_rightForearm_enabled"
        static let hipsEnabled = "metric_hips_enabled"
        static let leftThighEnabled = "metric_leftThigh_enabled"
        static let rightThighEnabled = "metric_rightThigh_enabled"
        static let leftCalfEnabled = "metric_leftCalf_enabled"
        static let rightCalfEnabled = "metric_rightCalf_enabled"

        static let allEnabledKeys: [String] = [
            weightEnabled,
            bodyFatEnabled,
            heightEnabled,
            leanBodyMassEnabled,
            waistEnabled,
            neckEnabled,
            shouldersEnabled,
            bustEnabled,
            chestEnabled,
            leftBicepEnabled,
            rightBicepEnabled,
            leftForearmEnabled,
            rightForearmEnabled,
            hipsEnabled,
            leftThighEnabled,
            rightThighEnabled,
            leftCalfEnabled,
            rightCalfEnabled
        ]
    }
}
