import SwiftUI
import SwiftData
import UIKit

@main
struct MeasureMeApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    // Konfiguracja kontenera modeli SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WaistMeasurement.self,
            MetricSample.self,
            MetricGoal.self,
            PhotoEntry.self  // ✅ DODANE!
        ])
        // Primary persistent configuration
        let configuration = ModelConfiguration(schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            DatabaseEncryption.applyRecommendedProtection()
            return container
        } catch {
            // Fallback to an in-memory store so the app can still launch, and log the error
            AppLog.debug("⚠️ Failed to create persistent ModelContainer: \(error). Falling back to in-memory store.")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("❌ Failed to create even an in-memory ModelContainer: \(error)")
            }
        }
    }()

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
    
    

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, appLocale)
        }
        .modelContainer(sharedModelContainer)
    }

    private var appLocale: Locale {
        switch appLanguage {
        case "pl":
            return Locale(identifier: "pl")
        case "en":
            return Locale(identifier: "en")
        default:
            return Locale.current
        }
    }
}
