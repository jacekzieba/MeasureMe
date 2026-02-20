import SwiftUI
import SwiftData
import UIKit

@main
struct MeasureMeApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @State private var startupState: StartupState = .loading
    @State private var startupAttemptID: Int = 0
    @State private var showCrashAlert = false

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
        // Zainstaluj crash reporter jako pierwszy krok
        CrashReporter.shared.install()

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
            "diagnostics_logging_enabled": true,
            "healthkit_sync_weight": true,
            "healthkit_sync_bodyFat": true,
            "healthkit_sync_height": true,
            "healthkit_sync_leanBodyMass": true,
            "healthkit_sync_waist": true
        ])
        configureUITestDefaultsIfNeeded()

        let segmentedFont = UIFont.systemFont(ofSize: 13, weight: .semibold).withMonospacedDigits()
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentedFont, .foregroundColor: UIColor.white], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentedFont, .foregroundColor: UIColor.black], for: .selected)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.appAccent)

        // Select all text when any TextField gains focus (avoids "080" problem)
        NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil, queue: .main
        ) { notification in
            if let textField = notification.object as? UITextField {
                DispatchQueue.main.async { textField.selectAll(nil) }
            }
        }

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
            .onAppear {
                if !AuditConfig.current.isEnabled, CrashReporter.shared.hasUnreportedCrash {
                    showCrashAlert = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                CrashReporter.shared.persistLogBuffer()
            }
            .alert(AppLocalization.string("Crash Detected"), isPresented: $showCrashAlert) {
                Button(AppLocalization.string("View Report")) {
                    CrashReporter.shared.markCrashReported()
                    // Uzytkownik moze przejsc do Ustawienia -> Dane -> Raporty awarii
                }
                Button(AppLocalization.string("Dismiss"), role: .cancel) {
                    CrashReporter.shared.markCrashReported()
                }
            } message: {
                Text(AppLocalization.string("The app crashed last time. You can view and share the crash report in Settings → Data → Crash Reports."))
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
        let bootstrapState = StartupInstrumentation.begin("AppBootstrap")
        startupState = .loading

        do {
            let containerSetupState = StartupInstrumentation.begin("CreatePersistentModelContainer")
            let container = try createPersistentModelContainer()
            StartupInstrumentation.end("CreatePersistentModelContainer", state: containerSetupState)

            let uiTestSetupState = StartupInstrumentation.begin("PrepareUITestData")
            try cleanUITestDataIfNeeded(container: container)
            try seedUITestDataIfNeeded(container: container)
            StartupInstrumentation.end("PrepareUITestData", state: uiTestSetupState)

            startupState = .ready(container)
            StartupInstrumentation.event("FirstFrameReady")
            runDeferredStartupWork(container: container)
            StartupInstrumentation.end("AppBootstrap", state: bootstrapState)
        } catch {
            let message = AppLocalization.string(
                "Could not start the app because local storage failed to initialize. Please retry. Error: %@",
                error.localizedDescription
            )
            AppLog.debug("❌ App startup failed: \(error)")
            startupState = .failed(message: message)
            StartupInstrumentation.end("AppBootstrap", state: bootstrapState)
        }
    }

    private func runDeferredStartupWork(container: ModelContainer) {
        Task(priority: .utility) {
            let storageProtectionState = StartupInstrumentation.begin("DeferredStorageProtection")
            DatabaseEncryption.applyRecommendedProtectionIfNeeded()
            StartupInstrumentation.end("DeferredStorageProtection", state: storageProtectionState)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            let healthSetupState = StartupInstrumentation.begin("DeferredHealthKitSetup")
            NotificationManager.shared.scheduleSmartIfNeeded()
            HealthKitManager.shared.configure(modelContainer: container)
            _ = HealthKitManager.shared.reconcileStoredSyncState()
            HealthKitManager.shared.startObservingHealthKitUpdates()
            StartupInstrumentation.end("DeferredHealthKitSetup", state: healthSetupState)
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
        let defaults = UserDefaults.standard
        let metricKeys = [
            "metric_weight_enabled", "metric_bodyFat_enabled", "metric_height_enabled",
            "metric_nonFatMass_enabled", "metric_waist_enabled", "metric_neck_enabled",
            "metric_shoulders_enabled", "metric_bust_enabled", "metric_chest_enabled",
            "metric_leftBicep_enabled", "metric_rightBicep_enabled",
            "metric_leftForearm_enabled", "metric_rightForearm_enabled",
            "metric_hips_enabled", "metric_leftThigh_enabled", "metric_rightThigh_enabled",
            "metric_leftCalf_enabled", "metric_rightCalf_enabled"
        ]
        let enabledByDefault: Set<String> = [
            "metric_weight_enabled", "metric_bodyFat_enabled",
            "metric_nonFatMass_enabled", "metric_waist_enabled"
        ]

        if args.contains("-uiTestOnboardingMode") {
            defaults.set(false, forKey: "hasCompletedOnboarding")
            defaults.set("en", forKey: "appLanguage")
            defaults.set(false, forKey: "premium_entitlement")
            defaults.set(true, forKey: "apple_intelligence_enabled")
            defaults.set(true, forKey: "onboarding_checklist_show")
            defaults.set(0.0, forKey: "home_tab_scroll_offset")
            for key in metricKeys {
                defaults.set(enabledByDefault.contains(key), forKey: key)
            }
        }

        guard args.contains("-uiTestMode") else { return }
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set("en", forKey: "appLanguage")
        defaults.set(true, forKey: "premium_entitlement")
        defaults.set(true, forKey: "apple_intelligence_enabled")
        defaults.set(false, forKey: "onboarding_checklist_show")
        defaults.set(-20.0, forKey: "home_tab_scroll_offset")

        if args.contains("-uiTestNoActiveMetrics") {
            for key in metricKeys { defaults.set(false, forKey: key) }
        } else {
            for key in metricKeys {
                defaults.set(enabledByDefault.contains(key), forKey: key)
            }
        }
        #endif
    }

    /// Usuwa wszystkie utrwalone dane, aby kazdy test UI startowal od czystego stanu.
    private func cleanUITestDataIfNeeded(container: ModelContainer) throws {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let shouldClean = args.contains("-uiTestMode")
            || args.contains("-uiTestOnboardingMode")
            || (AuditConfig.current.isEnabled && AuditConfig.current.useMockData)
        guard shouldClean else { return }

        let context = ModelContext(container)
        try context.fetch(FetchDescriptor<MetricSample>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MetricGoal>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PhotoEntry>()).forEach { context.delete($0) }
        try context.save()
        #endif
    }

    private func seedUITestDataIfNeeded(container: ModelContainer) throws {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let isAuditMockMode = AuditConfig.current.isEnabled && AuditConfig.current.useMockData
        let shouldSkipMeasurementSeed = args.contains("-uiTestSkipMeasurementSeeding")
        let shouldSeedMeasurements = (args.contains("-uiTestSeedMeasurements") || isAuditMockMode) && !shouldSkipMeasurementSeed
        let requestedPhotoCount = requestedUITestPhotoSeedCount(from: args)
        let effectivePhotoCount = requestedPhotoCount > 0 ? requestedPhotoCount : (isAuditMockMode ? 24 : 0)
        guard shouldSeedMeasurements || effectivePhotoCount > 0 else { return }

        let context = ModelContext(container)
        if shouldSeedMeasurements {
            let existingCount = try context.fetchCount(FetchDescriptor<MetricSample>())
            if existingCount == 0 {
                let now = AppClock.now
                let older = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
                context.insert(MetricSample(kind: .weight, value: 82, date: older))
                context.insert(MetricSample(kind: .weight, value: 80, date: now))
            }
        }

        if effectivePhotoCount > 0 {
            let existingPhotos = try context.fetchCount(FetchDescriptor<PhotoEntry>())
            if existingPhotos == 0 {
                seedUITestPhotos(count: effectivePhotoCount, into: context)
            }
        }

        try context.save()
        #endif
    }

    private func requestedUITestPhotoSeedCount(from args: [String]) -> Int {
        guard let seedFlagIndex = args.firstIndex(of: "-uiTestSeedPhotos") else { return 0 }
        let nextIndex = args.index(after: seedFlagIndex)
        guard nextIndex < args.endIndex, let parsed = Int(args[nextIndex]), parsed > 0 else {
            return 12
        }
        return parsed
    }

    private func seedUITestPhotos(count: Int, into context: ModelContext) {
        let safeCount = max(0, min(count, 300))
        let now = AppClock.now
        for idx in 0..<safeCount {
            let date = Calendar.current.date(byAdding: .day, value: -idx, to: now) ?? now
            let size = CGSize(width: 1280, height: 1706)
            guard let imageData = makeUITestImageData(index: idx, size: size) else { continue }
            let tags: [PhotoTag] = idx.isMultiple(of: 2) ? [.wholeBody] : [.waist]
            context.insert(PhotoEntry(imageData: imageData, date: date, tags: tags, linkedMetrics: []))
        }
    }

    private func makeUITestImageData(index: Int, size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let hue = CGFloat((index % 12)) / 12.0
            UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let insetRect = CGRect(x: 60, y: 60, width: size.width - 120, height: size.height - 120)
            UIColor.white.withAlphaComponent(0.28).setFill()
            UIBezierPath(roundedRect: insetRect, cornerRadius: 44).fill()

            let label = "UI TEST \(index + 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = label.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            label.draw(in: textRect, withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.84)
    }
}
