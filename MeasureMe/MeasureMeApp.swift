import SwiftUI
import SwiftData
import UIKit

@main
struct MeasureMeApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @State private var startupState: StartupState = .loading
    @State private var startupAttemptID: Int = 0

    private enum StartupState {
        case loading
        case ready(ModelContainer)
        case failed(message: String)
    }

    private enum StartupStorageError: LocalizedError {
        case applicationSupportDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportDirectoryUnavailable:
                return "Application Support directory is unavailable."
            }
        }
    }

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
        configureUITestDefaultsIfNeeded()

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
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch startupState {
                case .loading:
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.appAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.ignoresSafeArea())
                case .ready(let container):
                    RootView()
                        .modelContainer(container)
                case .failed(let message):
                    StartupErrorView(
                        message: message,
                        onRetry: {
                            startupAttemptID += 1
                        }
                    )
                }
            }
            .environment(\.locale, appLocale)
            .task(id: startupAttemptID) {
                await bootstrapApp()
            }
        }
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

    @MainActor
    private func bootstrapApp() async {
        startupState = .loading

        do {
            let container = try createPersistentModelContainer()
            try seedUITestDataIfNeeded(container: container)
            DatabaseEncryption.applyRecommendedProtection()

            NotificationManager.shared.scheduleSmartIfNeeded()
            HealthKitManager.shared.configure(modelContainer: container)
            _ = HealthKitManager.shared.reconcileStoredSyncState()
            HealthKitManager.shared.startObservingHealthKitUpdates()

            startupState = .ready(container)
        } catch {
            let message = AppLocalization.string(
                "Could not start the app because local storage failed to initialize. Please retry. Error: %@",
                error.localizedDescription
            )
            AppLog.debug("❌ App startup failed: \(error)")
            startupState = .failed(message: message)
        }
    }

    private func createPersistentModelContainer() throws -> ModelContainer {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StartupStorageError.applicationSupportDirectoryUnavailable
        }
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let schema = Schema([
            MetricSample.self,
            MetricGoal.self,
            PhotoEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func configureUITestDefaultsIfNeeded() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTestMode") else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set("en", forKey: "appLanguage")
        defaults.set(true, forKey: "premium_entitlement")
        defaults.set(true, forKey: "apple_intelligence_enabled")
        defaults.set(false, forKey: "onboarding_checklist_show")
        defaults.set(-20.0, forKey: "home_tab_scroll_offset")
        #endif
    }

    private func seedUITestDataIfNeeded(container: ModelContainer) throws {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTestSeedMeasurements") else { return }

        let context = ModelContext(container)
        let existingCount = try context.fetchCount(FetchDescriptor<MetricSample>())
        if existingCount > 0 {
            return
        }

        let now = Date()
        let older = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
        context.insert(MetricSample(kind: .weight, value: 82, date: older))
        context.insert(MetricSample(kind: .weight, value: 80, date: now))
        try context.save()
        #endif
    }
}
