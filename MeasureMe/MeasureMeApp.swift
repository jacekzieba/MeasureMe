//
//  MeasureMeApp.swift
//  MeasureMe
//
//  Created by Jacek Zięba on 26/01/2026.
//

import SwiftUI
import SwiftData

@main
struct MeasureMeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

<<<<<<< Updated upstream
=======
    init() {
        UserDefaults.standard.register(defaults: [
            "hasCompletedOnboarding": false,
            "userName": "",
            "userAge": 0,
            "metric_weight_enabled": true,
            "metric_waist_enabled": true,
            "metric_bodyFat_enabled": true,
            "metric_nonFatMass_enabled": true,
            "unitsSystem": "metric",
            "animationsEnabled": true,
            "hapticsEnabled": true,
            "save_unchanged_quick_add": false,
            "measurement_photo_reminders_enabled": true,
            "measurement_goal_achieved_enabled": true,
            "onboarding_skipped_healthkit": false,
            "onboarding_skipped_reminders": false,
            "onboarding_checklist_show": true,
            "onboarding_checklist_collapsed": false,
            "onboarding_checklist_hide_completed": false,
            "onboarding_checklist_metrics_completed": false,
            "onboarding_checklist_premium_explored": false,
            "settings_open_tracked_measurements": false,
            "settings_open_reminders": false,
            "appLanguage": "system",
            "healthkit_sync_weight": true,
            "healthkit_sync_bodyFat": true,
            "healthkit_sync_height": true,
            "healthkit_sync_leanBodyMass": true,
            "healthkit_sync_waist": true
        ])

        let segmentedFont = UIFont.systemFont(ofSize: 13, weight: .semibold).withMonospacedDigits()
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentedFont], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentedFont], for: .selected)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.appAccent)

        let navTitleBase = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let navLargeBase = UIFont.systemFont(ofSize: 34, weight: .bold)
        let navTitleFont = navTitleBase.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: navTitleBase.pointSize) } ?? navTitleBase
        let navLargeFont = navLargeBase.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: navLargeBase.pointSize) } ?? navLargeBase

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        navAppearance.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [.font: navTitleFont]
        navAppearance.largeTitleTextAttributes = [.font: navLargeFont]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = navAppearance
        navBar.scrollEdgeAppearance = navAppearance
        navBar.compactAppearance = navAppearance
        navBar.compactScrollEdgeAppearance = navAppearance
        navBar.titleTextAttributes = [.font: navTitleFont]
        navBar.largeTitleTextAttributes = [.font: navLargeFont]
        navBar.shadowImage = UIImage()

        NotificationManager.shared.scheduleSmartIfNeeded()
        HealthKitManager.shared.configure(modelContainer: sharedModelContainer)
        HealthKitManager.shared.startObservingHealthKitUpdates()
    }
    
    

>>>>>>> Stashed changes
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
