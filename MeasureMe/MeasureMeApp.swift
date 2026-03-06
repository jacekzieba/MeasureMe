import SwiftUI
import SwiftData
import UIKit

@main
struct MeasureMeApp: App {
    @AppSetting(\.experience.appLanguage) private var appLanguage: String = "system"
    @StateObject private var settingsStore = AppSettingsStore.shared
    @State private var startupState: StartupState = .loading
    @State private var startupLoadingState = StartupLoadingState(
        phase: .initializingStorage,
        progress: 0.08,
        statusKey: StartupLoadingPhase.initializingStorage.statusKey
    )
    @State private var startupAttemptID: Int = 0
    @State private var showCrashAlert = false
    private let isRunningXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private enum StartupState {
        case loading
        case ready(ModelContainer)
        case failed(message: String)
    }

    private enum StartupLoadingPhase {
        case initializingStorage
        case preparingData
        case finalizing

        var statusKey: String {
            switch self {
            case .initializingStorage:
                return "startup.loading.status.initializingStorage"
            case .preparingData:
                return "startup.loading.status.preparingData"
            case .finalizing:
                return "startup.loading.status.finalizing"
            }
        }
    }

    private struct StartupLoadingState {
        var phase: StartupLoadingPhase
        var progress: Double
        var statusKey: String
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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            CrashReporter.shared.install()
            Analytics.shared.setup()
            Analytics.shared.track(.appLaunched)
        }

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
                    StartupLoadingView(
                        statusKey: startupLoadingState.statusKey,
                        progress: startupLoadingState.progress
                    )
                    .transition(.opacity)
                case .ready(let container):
                    RootView()
                        .modelContainer(container)
                        .transition(.opacity)
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
            .environmentObject(settingsStore)
            .task(id: startupAttemptID) {
                await bootstrapApp()
            }
            .onAppear {
                if !AuditConfig.current.isEnabled, CrashReporter.shared.hasUnreportedCrash {
                    showCrashAlert = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                WidgetDataWriter.flushPendingWrites()
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
        resetStartupLoadingState()
        startupState = .loading

        do {
            updateStartupLoading(
                phase: .initializingStorage,
                targetProgress: 0.18,
                duration: 0.16
            )
            let containerSetupState = StartupInstrumentation.begin("CreatePersistentModelContainer")
            let container = try createPersistentModelContainer()
            StartupInstrumentation.end("CreatePersistentModelContainer", state: containerSetupState)
            updateStartupLoading(
                phase: .initializingStorage,
                targetProgress: 0.44,
                duration: 0.24
            )

            updateStartupLoading(
                phase: .preparingData,
                targetProgress: 0.58,
                duration: 0.22
            )
            let uiTestSetupState = StartupInstrumentation.begin("PrepareUITestData")
            try cleanUITestDataIfNeeded(container: container)
            try seedUITestDataIfNeeded(container: container)
            StartupInstrumentation.end("PrepareUITestData", state: uiTestSetupState)
            updateStartupLoading(
                phase: .preparingData,
                targetProgress: 0.78,
                duration: 0.24
            )

            updateStartupLoading(
                phase: .finalizing,
                targetProgress: 0.90,
                duration: 0.16
            )
            withAnimation(.easeOut(duration: 0.14)) {
                startupLoadingState.progress = 1.0
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                startupState = .ready(container)
            }
            StartupInstrumentation.event("FirstFrameReady")
            Analytics.shared.track(.appFirstFrameReady)
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

    @MainActor
    private func resetStartupLoadingState() {
        startupLoadingState = StartupLoadingState(
            phase: .initializingStorage,
            progress: 0.08,
            statusKey: StartupLoadingPhase.initializingStorage.statusKey
        )
    }

    @MainActor
    private func updateStartupLoading(
        phase: StartupLoadingPhase,
        targetProgress: Double,
        duration: Double
    ) {
        startupLoadingState.phase = phase
        startupLoadingState.statusKey = phase.statusKey
        let clampedTarget = min(max(targetProgress, 0.0), 1.0)
        let monotonicProgress = max(startupLoadingState.progress, clampedTarget)

        withAnimation(.easeOut(duration: duration)) {
            startupLoadingState.progress = monotonicProgress
        }
    }

    private func runDeferredStartupWork(container: ModelContainer) {
        guard !isRunningXCTest else { return }

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

        Task(priority: .background) {
            try? await Task.sleep(for: .milliseconds(600))
            let context = ModelContext(container)
            let units = settingsStore.snapshot.profile.unitsSystem
            WidgetDataWriter.writeAllAndReload(context: context, unitsSystem: units)
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
        let defaults = AppSettingsStore.shared
        let metricKeys = AppSettingsKeys.Metrics.allEnabledKeys
        let enabledByDefault: Set<String> = [
            AppSettingsKeys.Metrics.weightEnabled,
            AppSettingsKeys.Metrics.bodyFatEnabled,
            AppSettingsKeys.Metrics.leanBodyMassEnabled,
            AppSettingsKeys.Metrics.waistEnabled
        ]
        let indicatorKeysEnabledByDefault: [WritableKeyPath<AppSettingsSnapshot, Bool>] = [
            \.indicators.showWHtROnHome,
            \.indicators.showRFMOnHome,
            \.indicators.showBMIOnHome,
            \.indicators.showBodyFatOnHome,
            \.indicators.showLeanMassOnHome,
            \.indicators.showWHROnHome,
            \.indicators.showWaistRiskOnHome,
            \.indicators.showABSIOnHome,
            \.indicators.showBodyShapeScoreOnHome,
            \.indicators.showCentralFatRiskOnHome,
            \.indicators.showPhysiqueSWR,
            \.indicators.showPhysiqueCWR,
            \.indicators.showPhysiqueSHR,
            \.indicators.showPhysiqueHWR,
            \.indicators.showPhysiqueBWR,
            \.indicators.showPhysiqueWHtR,
            \.indicators.showPhysiqueBodyFat,
            \.indicators.showPhysiqueRFM
        ]

        if args.contains("-uiTestOnboardingMode") {
            defaults.set(\.onboarding.hasCompletedOnboarding, false)
            defaults.set(\.experience.appLanguage, "en")
            defaults.set(\.premium.premiumEntitlement, false)
            defaults.set(\.analytics.appleIntelligenceEnabled, true)
            defaults.set(\.onboarding.onboardingChecklistShow, true)
            defaults.set(\.home.homeTabScrollOffset, 0.0)
            for key in metricKeys {
                defaults.set(enabledByDefault.contains(key), forKey: key)
            }
            for keyPath in indicatorKeysEnabledByDefault {
                defaults.set(keyPath, true)
            }
        }

        guard args.contains("-uiTestMode") else { return }
        // Swizzle UIScrollView so every future instance has delaysContentTouches = false.
        // This lets XCTest synthesised taps reach SwiftUI's .buttonStyle(.plain) buttons
        // without the 150 ms hold that UIScrollView normally uses to distinguish tap vs scroll.
        UIScrollView.swizzleDelaysContentTouchesForUITesting()
        UIScrollView.appearance().delaysContentTouches = false
        defaults.set(\.onboarding.hasCompletedOnboarding, true)
        defaults.set(\.experience.appLanguage, "en")
        defaults.set(\.premium.premiumEntitlement, true)
        defaults.set(\.analytics.appleIntelligenceEnabled, true)
        defaults.set(\.onboarding.onboardingChecklistShow, false)
        defaults.set(\.home.homeTabScrollOffset, -20.0)
        defaults.set(\.home.showLastPhotosOnHome, true)
        defaults.set(\.home.showMeasurementsOnHome, true)
        defaults.set(\.home.showHealthMetricsOnHome, true)

        if args.contains("-uiTestNoActiveMetrics") {
            for key in metricKeys { defaults.set(false, forKey: key) }
        } else {
            for key in metricKeys {
                defaults.set(enabledByDefault.contains(key), forKey: key)
            }
        }
        for keyPath in indicatorKeysEnabledByDefault {
            defaults.set(keyPath, true)
        }
        if args.contains("-uiTestForceNonPremium") {
            defaults.set(\.premium.premiumEntitlement, false)
        }
        if args.contains("-uiTestPhysiqueSWROff") {
            defaults.set(\.indicators.showPhysiqueSWR, false)
        }
        if args.contains("-uiTestGenderNotSpecified") {
            defaults.set(\.profile.userGender, "notSpecified")
        } else if args.contains("-uiTestGenderMale") {
            defaults.set(\.profile.userGender, "male")
        } else if args.contains("-uiTestGenderFemale") {
            defaults.set(\.profile.userGender, "female")
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
        let forceNoActiveMetrics = args.contains("-uiTestNoActiveMetrics")
        let shouldSeedMeasurements = (args.contains("-uiTestSeedMeasurements") || isAuditMockMode)
            && !shouldSkipMeasurementSeed
            && !forceNoActiveMetrics
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

// MARK: - UI-Test: UIScrollView touch-delay swizzle

#if DEBUG
private extension UIScrollView {
    /// Swizzles `setDelaysContentTouches:` so every UIScrollView instance (including
    /// SwiftUI's internal one) always uses `delaysContentTouches = false` in UI-test
    /// builds.  Must be called once, before any scroll views are created.
    static func swizzleDelaysContentTouchesForUITesting() {
        let originalSel = #selector(setter: UIScrollView.delaysContentTouches)
        let swizzledSel = #selector(UIScrollView.uitest_setDelaysContentTouches(_:))
        guard
            let original = class_getInstanceMethod(UIScrollView.self, originalSel),
            let swizzled = class_getInstanceMethod(UIScrollView.self, swizzledSel)
        else { return }
        method_exchangeImplementations(original, swizzled)
    }

    /// After swizzling this IS the original `setDelaysContentTouches:` implementation;
    /// calling `self.uitest_setDelaysContentTouches(false)` inside our replacement
    /// therefore invokes the original with `false`, not our code again.
    @objc func uitest_setDelaysContentTouches(_ newValue: Bool) {
        uitest_setDelaysContentTouches(false)
    }
}
#endif
