import SwiftUI
import SwiftData
import UIKit
import BackgroundTasks

@main
struct MeasureMeApp: App {
    @UIApplicationDelegateAdaptor(MeasureMeAppDelegate.self) private var appDelegate
    @AppSetting(\.experience.appAppearance) private var appAppearance: String = AppAppearance.dark.rawValue
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
    @State private var autoRestoreMessage: String?
    private let isRunningXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private let isUITestMode = UITestArgument.isAnyTestMode
    private let isSettingsUITestMode = UITestArgument.isPresent(.openSettingsTab)
    private var isUnitTestHostMode: Bool { isRunningXCTest && !isUITestMode && !isSettingsUITestMode }

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

    private struct StartupStorageContextError: LocalizedError {
        let step: String
        let underlying: Error

        var errorDescription: String? {
            "Step '\(step)' failed: \(underlying.localizedDescription)"
        }
    }

    init() {
        AppRuntimeConfigurator.configureInitialServices(
            isRunningXCTest: isRunningXCTest,
            isUnitTestHostMode: isUnitTestHostMode,
            configureUITestDefaults: configureUITestDefaultsIfNeeded,
            registerBackgroundTasks: {
                AppLifecycleCoordinator.registerBackgroundTasks()
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnitTestHostMode {
                    UnitTestHostView()
                } else if isSettingsUITestMode {
                    SettingsUITestHostView()
                } else {
                    switch startupState {
                    case .loading:
                        StartupLoadingView(
                            statusKey: startupLoadingState.statusKey,
                            progress: startupLoadingState.progress
                        )
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
            }
            .environment(\.locale, appLocale)
            .environmentObject(settingsStore)
            .preferredColorScheme(resolvedAppearance.preferredColorScheme)
            .task(id: startupAttemptID) {
                guard !isSettingsUITestMode else { return }
                guard !isUnitTestHostMode else { return }
                await bootstrapApp()
            }
            .onChange(of: appAppearance) { _, _ in
                WidgetDataWriter.reloadAllTimelines()
            }
            .onAppear {
                if !AuditConfig.current.isEnabled, CrashReporter.shared.hasUnreportedCrash {
                    showCrashAlert = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                let container: ModelContainer?
                if case .ready(let readyContainer) = startupState {
                    container = readyContainer
                } else {
                    container = nil
                }
                AppLifecycleCoordinator.handleWillResignActive(
                    container: container,
                    isRunningXCTest: isRunningXCTest
                )
            }
            .alert(AppLocalization.string("Crash Detected"), isPresented: $showCrashAlert) {
                Button(AppLocalization.string("View Report")) {
                    CrashReporter.shared.markCrashReported()
                    // User can navigate to Settings -> Data -> Crash Reports
                }
                Button(AppLocalization.string("Dismiss"), role: .cancel) {
                    CrashReporter.shared.markCrashReported()
                }
            } message: {
                Text(AppLocalization.string("The app crashed last time. You can view and share the crash report in Settings → Data → Crash Reports."))
            }
            .alert(
                AppLocalization.string("iCloud Backup"),
                isPresented: Binding(
                    get: { autoRestoreMessage != nil },
                    set: { if !$0 { autoRestoreMessage = nil } }
                )
            ) {
                Button(AppLocalization.string("OK"), role: .cancel) {
                    autoRestoreMessage = nil
                }
            } message: {
                Text(autoRestoreMessage ?? "")
            }
        }
    }

    private var appLocale: Locale {
        AppLanguage.fromStoredValue(appLanguage).locale
    }

    private var resolvedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearance) ?? .system
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
            let container: ModelContainer
            do {
                container = try createPersistentModelContainer()
            } catch {
                throw StartupStorageContextError(step: "createPersistentModelContainer", underlying: error)
            }
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
            do {
                try cleanUITestDataIfNeeded(container: container)
                try seedUITestDataIfNeeded(container: container)
            } catch {
                throw StartupStorageContextError(step: "prepareUITestData", underlying: error)
            }
            StartupInstrumentation.end("PrepareUITestData", state: uiTestSetupState)
            updateStartupLoading(
                phase: .preparingData,
                targetProgress: 0.78,
                duration: 0.24
            )

            if isUITestMode {
                startupLoadingState.progress = 1.0
                startupState = .ready(container)
                StartupInstrumentation.event("FirstFrameReady")
                Analytics.shared.track(.appFirstFrameReady)
                runDeferredStartupWork(container: container)
                StartupInstrumentation.end("AppBootstrap", state: bootstrapState)
                return
            }

            updateStartupLoading(
                phase: .finalizing,
                targetProgress: 0.90,
                duration: 0.16
            )
            withAnimation(.easeOut(duration: 0.14)) {
                startupLoadingState.progress = 1.0
            }
            startupState = .ready(container)
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

        scheduleDeferredStorageProtection()
        scheduleDeferredHealthSetup(container: container)
        scheduleDeferredAutoRestore(container: container)
        scheduleDeferredWidgetRefresh(container: container)
        scheduleDeferredBackupMaintenance(container: container)
        scheduleDeferredWatchConnectivity(container: container)
    }

    private func scheduleDeferredStorageProtection() {
        Task(priority: .utility) {
            let storageProtectionState = StartupInstrumentation.begin("DeferredStorageProtection")
            DatabaseEncryption.applyRecommendedProtectionIfNeeded()
            StartupInstrumentation.end("DeferredStorageProtection", state: storageProtectionState)
        }
    }

    private func scheduleDeferredHealthSetup(container: ModelContainer) {
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(200))
            let healthSetupState = StartupInstrumentation.begin("DeferredHealthKitSetup")
            await MainActor.run {
                NotificationManager.shared.scheduleSmartIfNeeded(context: container.mainContext)
                NotificationManager.shared.scheduleAINotificationsIfNeeded(context: container.mainContext, trigger: .startup)
                HealthKitManager.shared.configure(modelContainer: container)
                _ = HealthKitManager.shared.reconcileStoredSyncState()
                HealthKitManager.shared.startObservingHealthKitUpdates()
            }
            await IntentDeferredHealthSyncProcessor.processPendingIfNeeded()
            StartupInstrumentation.end("DeferredHealthKitSetup", state: healthSetupState)
        }
    }

    private func scheduleDeferredAutoRestore(container: ModelContainer) {
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            let autoRestoreState = StartupInstrumentation.begin("DeferredICloudAutoRestore")
            let context = ModelContext(container)
            let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: context)
            if didRestore {
                await MainActor.run {
                    autoRestoreMessage = AppLocalization.string("Latest iCloud backup was restored automatically. Review your measurements and photos to confirm everything looks right.")
                }
            }
            StartupInstrumentation.end("DeferredICloudAutoRestore", state: autoRestoreState)
        }
    }

    private func scheduleDeferredWidgetRefresh(container: ModelContainer) {
        Task(priority: .background) {
            try? await Task.sleep(for: .milliseconds(600))
            let context = ModelContext(container)
            let units = settingsStore.snapshot.profile.unitsSystem
            WidgetDataWriter.writeAllAndReload(context: context, unitsSystem: units)
            await MainActor.run {
                WatchSessionManager.shared.sendApplicationContext()
            }
        }
    }

    private func scheduleDeferredBackupMaintenance(container: ModelContainer) {
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(800))
            let context = ModelContext(container)
            let isPremium = AppSettingsStore.shared.snapshot.premium.premiumEntitlement
            await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: isPremium)
            if isPremium, AppSettingsStore.shared.snapshot.iCloudBackup.isEnabled {
                AppLifecycleCoordinator.scheduleBackgroundBackup()
            }
            if AppSettingsStore.shared.snapshot.notifications.notificationsEnabled,
               AppSettingsStore.shared.snapshot.notifications.aiNotificationsEnabled {
                AppLifecycleCoordinator.scheduleBackgroundAINotifications()
            }
        }
    }

    private func scheduleDeferredWatchConnectivity(container: ModelContainer) {
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                WatchSessionManager.shared.configure(
                    container: container,
                    healthKit: HealthKitManager.shared
                )
                WatchSessionManager.shared.activate()
            }
        }
    }

    private func createPersistentModelContainer() throws -> ModelContainer {
        let isSettingsUITestMode = UITestArgument.isPresent(.openSettingsTab)

        if isUnitTestHostMode {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: MetricSample.self,
                MetricGoal.self,
                PhotoEntry.self,
                CustomMetricDefinition.self,
                configurations: configuration
            )
        }

        if isUITestMode {
            if isSettingsUITestMode {
                let schema = Schema([MetricSample.self, MetricGoal.self, CustomMetricDefinition.self])
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            }
            let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }

        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StartupStorageError.applicationSupportDirectoryUnavailable
        }
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let schema = Schema([
            MetricSample.self,
            MetricGoal.self,
            PhotoEntry.self,
            CustomMetricDefinition.self
        ])
        // App uses custom iCloud backup flow; disable SwiftData CloudKit sync to avoid
        // CloudKit schema constraints on local-only models.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard shouldAttemptStoreResetAfterContainerFailure else { throw error }
            AppLog.debug("⚠️ SwiftData container init failed. Attempting one-time store reset. Error: \(error)")
            try purgePersistentStoreFiles()
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    private var shouldAttemptStoreResetAfterContainerFailure: Bool {
        #if DEBUG
        true
        #elseif targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func purgePersistentStoreFiles() throws {
        let fileManager = FileManager.default
        let roots: [URL] = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for root in roots {
            guard let files = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in files where isLikelySwiftDataStore(url) {
                try? fileManager.removeItem(at: url)
                // If SwiftData uses SQLite sidecars, clean them as well.
                try? fileManager.removeItem(atPath: url.path + "-wal")
                try? fileManager.removeItem(atPath: url.path + "-shm")
            }
        }
    }

    private func isLikelySwiftDataStore(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "store" || ext == "sqlite" || ext == "db" { return true }
        return url.lastPathComponent.lowercased().contains("default.store")
    }

    private func configureUITestDefaultsIfNeeded() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let defaults = AppSettingsStore.shared
        let uiTestLanguage = requestedUITestLanguage(from: args) ?? "en"
        let metricKeys = AppSettingsKeys.Metrics.allEnabledKeys
        let shouldPrepareUITestTouchHandling = args.contains(UITestArgument.mode.rawValue) || args.contains(UITestArgument.onboardingMode.rawValue)
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

        if args.contains(UITestArgument.onboardingMode.rawValue) {
            defaults.set(\.onboarding.hasCompletedOnboarding, false)
            defaults.set(\.onboarding.onboardingFlowVersion, 0)
            defaults.set(\.experience.appAppearance, AppAppearance.dark.rawValue)
            defaults.set(\.experience.appLanguage, uiTestLanguage)
            defaults.set(\.premium.premiumEntitlement, false)
            defaults.set(\.iCloudBackup.isEnabled, false)
            defaults.set(\.onboarding.onboardingViewedICloudBackupOffer, false)
            defaults.set(\.onboarding.onboardingSkippedICloudBackup, false)
            defaults.set(\.analytics.appleIntelligenceEnabled, true)
            defaults.set(\.onboarding.onboardingChecklistShow, true)
            defaults.set(\.onboarding.activationCurrentTaskID, "")
            defaults.set(\.onboarding.activationCompletedTaskIDs, "")
            defaults.set(\.onboarding.activationSkippedTaskIDs, "")
            defaults.set(\.onboarding.activationIsDismissed, false)
            defaults.set(\.home.homeTabScrollOffset, 0.0)
            for key in metricKeys {
                defaults.set(enabledByDefault.contains(key), forKey: key)
            }
            for keyPath in indicatorKeysEnabledByDefault {
                defaults.set(keyPath, true)
            }
            if args.contains(UITestArgument.forcePremium.rawValue) {
                defaults.set(\.premium.premiumEntitlement, true)
            }
            if args.contains(UITestArgument.enableICloudBackup.rawValue) {
                defaults.set(\.iCloudBackup.isEnabled, true)
                defaults.set(\.onboarding.onboardingViewedICloudBackupOffer, true)
                defaults.set(\.onboarding.onboardingSkippedICloudBackup, false)
            }
        }

        if args.contains(UITestArgument.openSettingsTab.rawValue) {
            defaults.set(\.onboarding.hasCompletedOnboarding, true)
            defaults.set(\.experience.appLanguage, uiTestLanguage)
            defaults.set(\.home.settingsOpenTrackedMeasurements, false)
            defaults.set(\.home.settingsOpenReminders, false)
            defaults.set(\.home.settingsOpenHomeSettings, false)
            defaults.removeObject(forKey: AppSettingsKeys.Entry.pendingAppEntryAction)
            defaults.removeObject(forKey: AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent)
        }

        if shouldPrepareUITestTouchHandling {
            // SwiftUI buttons inside onboarding/home scroll views can miss XCTest taps
            // unless the default UIScrollView touch delay is disabled for UI tests.
            UIScrollView.swizzleDelaysContentTouchesForUITesting()
            UIScrollView.appearance().delaysContentTouches = false
        }

        guard args.contains(UITestArgument.mode.rawValue) else { return }
        defaults.removeObject(forKey: AppSettingsKeys.Home.homeLayoutData)
        defaults.set(\.homeLayout.layoutSchemaVersion, HomeLayoutSnapshot.currentSchemaVersion)
        defaults.set(\.onboarding.hasCompletedOnboarding, true)
        defaults.set(\.onboarding.onboardingFlowVersion, 1)
        defaults.set(\.experience.appAppearance, AppAppearance.dark.rawValue)
        defaults.set(\.experience.appLanguage, uiTestLanguage)
        defaults.set(\.premium.premiumEntitlement, true)
        defaults.set(\.iCloudBackup.isEnabled, false)
        defaults.set(\.onboarding.onboardingViewedICloudBackupOffer, false)
        defaults.set(\.onboarding.onboardingSkippedICloudBackup, false)
        defaults.set(\.analytics.appleIntelligenceEnabled, true)
        defaults.set(\.onboarding.onboardingChecklistShow, false)
        defaults.set(\.onboarding.onboardingChecklistMetricsCompleted, false)
        defaults.set(\.onboarding.onboardingChecklistPremiumExplored, false)
        defaults.set(\.onboarding.onboardingChecklistCollapsed, false)
        defaults.set(\.onboarding.onboardingSkippedReminders, false)
        defaults.set(\.onboarding.activationCurrentTaskID, "")
        defaults.set(\.onboarding.activationCompletedTaskIDs, "")
        defaults.set(\.onboarding.activationSkippedTaskIDs, "")
        defaults.set(\.onboarding.activationIsDismissed, true)
        defaults.set(\.home.homeTabScrollOffset, -20.0)
        defaults.set(\.home.showLastPhotosOnHome, true)
        defaults.set(\.home.showMeasurementsOnHome, true)
        defaults.set(\.home.showHealthMetricsOnHome, true)
        defaults.set(\.home.homePinnedActionRaw, "")
        defaults.removeObject(forKey: AppSettingsKeys.Entry.pendingAppEntryAction)
        defaults.removeObject(forKey: AppSettingsKeys.Entry.pendingHealthKitSyncFromIntent)
        defaults.set(\.profile.manualHeight, 180.0)

        if args.contains(UITestArgument.noActiveMetrics.rawValue) {
            for key in metricKeys { defaults.set(false, forKey: key) }
        } else {
            for key in metricKeys {
                defaults.set(enabledByDefault.contains(key), forKey: key)
            }
        }
        for keyPath in indicatorKeysEnabledByDefault {
            defaults.set(keyPath, true)
        }
        if args.contains(UITestArgument.forceNonPremium.rawValue) {
            defaults.set(\.premium.premiumEntitlement, false)
        }
        if args.contains(UITestArgument.enableICloudBackup.rawValue) {
            defaults.set(\.iCloudBackup.isEnabled, true)
            defaults.set(\.onboarding.onboardingViewedICloudBackupOffer, true)
            defaults.set(\.onboarding.onboardingSkippedICloudBackup, false)
        }
        if args.contains(UITestArgument.showChecklist.rawValue) {
            defaults.set(\.onboarding.onboardingChecklistShow, true)
        }
        if args.contains(UITestArgument.activationHub.rawValue) {
            defaults.set(\.onboarding.onboardingFlowVersion, 2)
            defaults.set(\.onboarding.onboardingPrimaryGoal, OnboardingPriority.improveHealth.rawValue)
            defaults.set(\.onboarding.onboardingChecklistShow, true)
            defaults.set(\.onboarding.activationCurrentTaskID, requestedActivationTask(from: args)?.rawValue ?? ActivationTask.initial.rawValue)
            defaults.set(\.onboarding.activationCompletedTaskIDs, "")
            defaults.set(\.onboarding.activationSkippedTaskIDs, "")
            defaults.set(\.onboarding.activationIsDismissed, false)
        }
        if args.contains(UITestArgument.checklistNeedsReminders.rawValue) {
            defaults.set(\.onboarding.onboardingSkippedReminders, true)
        }
        if let pinnedAction = requestedHomePinnedAction(from: args) {
            defaults.set(\.home.homePinnedActionRaw, pinnedAction.rawValue)
        }
        if let pendingAction = requestedPendingAppEntryAction(from: args) {
            defaults.set(pendingAction.rawValue, forKey: AppSettingsKeys.Entry.pendingAppEntryAction)
        }
        if args.contains(UITestArgument.physiqueSWROff.rawValue) {
            defaults.set(\.indicators.showPhysiqueSWR, false)
        }
        if args.contains(UITestArgument.genderNotSpecified.rawValue) {
            defaults.set(\.profile.userGender, "notSpecified")
        } else if args.contains(UITestArgument.genderMale.rawValue) {
            defaults.set(\.profile.userGender, "male")
        } else if args.contains(UITestArgument.genderFemale.rawValue) {
            defaults.set(\.profile.userGender, "female")
        }
        #endif
    }

    /// Removes all persisted data so each UI test starts from a clean state.
    private func cleanUITestDataIfNeeded(container: ModelContainer) throws {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let shouldClean = args.contains(UITestArgument.mode.rawValue)
            || args.contains(UITestArgument.onboardingMode.rawValue)
            || (AuditConfig.current.isEnabled && AuditConfig.current.useMockData)
        guard shouldClean else { return }
        if isUITestMode {
            return
        }

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
        let shouldSkipMeasurementSeed = args.contains(UITestArgument.skipMeasurementSeeding.rawValue)
        let forceNoActiveMetrics = args.contains(UITestArgument.noActiveMetrics.rawValue)
        let shouldSeedPhotoMetrics = args.contains(UITestArgument.seedPhotoMetrics.rawValue)
        let shouldSeedMeasurements = (args.contains(UITestArgument.seedMeasurements.rawValue) || isAuditMockMode)
            && !shouldSkipMeasurementSeed
            && !forceNoActiveMetrics
        let requestedPhotoCount = requestedUITestPhotoSeedCount(from: args)
        let effectivePhotoCount = requestedPhotoCount > 0 ? requestedPhotoCount : (isAuditMockMode ? 24 : 0)
        guard shouldSeedMeasurements || effectivePhotoCount > 0 else { return }

        let context = ModelContext(container)
        if args.contains(UITestArgument.activationHub.rawValue) {
            for sample in try context.fetch(FetchDescriptor<MetricSample>()) {
                context.delete(sample)
            }
            for photo in try context.fetch(FetchDescriptor<PhotoEntry>()) {
                context.delete(photo)
            }
        }

        if shouldSeedMeasurements {
            let existingCount = try context.fetchCount(FetchDescriptor<MetricSample>())
            if existingCount == 0 {
                let now = AppClock.now
                if !args.contains(UITestArgument.activationHub.rawValue) {
                    let older = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now
                    context.insert(MetricSample(kind: .weight, value: 82, date: older))
                }
                context.insert(MetricSample(kind: .weight, value: 80, date: now))
            }
        }

        if effectivePhotoCount > 0 {
            let existingPhotos = try context.fetchCount(FetchDescriptor<PhotoEntry>())
            if existingPhotos == 0 {
                seedUITestPhotos(
                    count: effectivePhotoCount,
                    into: context,
                    withLinkedMetrics: shouldSeedPhotoMetrics
                )
            }
        }

        try context.save()
        #endif
    }

    private func requestedUITestPhotoSeedCount(from args: [String]) -> Int {
        guard let seedFlagIndex = args.firstIndex(of: UITestArgument.seedPhotos.rawValue) else { return 0 }
        let nextIndex = args.index(after: seedFlagIndex)
        guard nextIndex < args.endIndex, let parsed = Int(args[nextIndex]), parsed > 0 else {
            return 12
        }
        return parsed
    }

    private func requestedUITestLanguage(from args: [String]) -> String? {
        if args.contains(UITestArgument.languagePL.rawValue) { return "pl" }
        if args.contains(UITestArgument.languageEN.rawValue) { return "en" }
        if args.contains(UITestArgument.languageSystem.rawValue) { return "system" }
        return nil
    }

    private func requestedHomePinnedAction(from args: [String]) -> HomePinnedAction? {
        guard let value = UITestArgument.value(for: .homePinnedAction, in: args) else { return nil }
        return HomePinnedAction(rawValue: value)
    }

    private func requestedPendingAppEntryAction(from args: [String]) -> AppEntryAction? {
        guard let value = UITestArgument.value(for: .pendingAppEntryAction, in: args) else { return nil }
        return AppEntryAction(rawValue: value)
    }

    private func requestedActivationTask(from args: [String]) -> ActivationTask? {
        guard let value = UITestArgument.value(for: .activationTask, in: args) else { return nil }
        return ActivationTask(rawValue: value)
    }

    private func seedUITestPhotos(count: Int, into context: ModelContext, withLinkedMetrics: Bool = false) {
        let safeCount = max(0, min(count, 300))
        let now = AppClock.now
        for idx in 0..<safeCount {
            let date = Calendar.current.date(byAdding: .day, value: -idx, to: now) ?? now
            let size = CGSize(width: 1280, height: 1706)
            guard let imageData = makeUITestImageData(index: idx, size: size) else { continue }
            let tags: [PhotoTag] = idx.isMultiple(of: 2) ? [.wholeBody] : [.waist]
            let linkedMetrics: [MetricValueSnapshot]
            if withLinkedMetrics {
                let weight = max(55, 82.0 - (Double(idx) * 0.08))
                let waist = max(60, 92.0 - (Double(idx) * 0.05))
                linkedMetrics = [
                    MetricValueSnapshot(kind: .weight, value: weight, unit: "kg"),
                    MetricValueSnapshot(kind: .waist, value: waist, unit: "cm")
                ]
            } else {
                linkedMetrics = []
            }
            context.insert(PhotoEntry(imageData: imageData, date: date, tags: tags, linkedMetrics: linkedMetrics))
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

private struct SettingsUITestHostView: View {
    @StateObject private var premiumStore = PremiumStore(startListener: false)
    @StateObject private var metricsStore = ActiveMetricsStore()
    @AppSetting(\.experience.appAppearance) private var appAppearance: String = AppAppearance.dark.rawValue

    var body: some View {
        NavigationStack {
            SettingsView()
        }
        .environmentObject(premiumStore)
        .environmentObject(metricsStore)
        .sheet(isPresented: $premiumStore.isPaywallPresented) {
            PremiumPaywallView()
                .environmentObject(premiumStore)
        }
        .onChange(of: premiumStore.isPaywallPresented) { _, isPresented in
            guard !isPresented else { return }
            premiumStore.handlePaywallDismissed()
        }
        .sheet(isPresented: $premiumStore.showPostPurchaseSetup) {
            PostPurchaseSetupView()
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: premiumStore.isPremium) { _, isPremium in
            guard isPremium else { return }
            guard UITestArgument.isPresent(.simulateTrialActivation) else { return }
            guard !premiumStore.isPaywallPresented else { return }
            if !premiumStore.showPostPurchaseSetup {
                premiumStore.showPostPurchaseSetup = true
            }
        }
        .overlay {
            if UITestArgument.isPresent(.simulateTrialActivation) && premiumStore.showPostPurchaseSetup {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        Text(AppLocalization.string("postpurchase.title"))
                            .font(AppTypography.displaySection)
                            .multilineTextAlignment(.center)

                        Button(AppLocalization.string("postpurchase.getstarted")) {
                            premiumStore.showPostPurchaseSetup = false
                        }
                        .buttonStyle(AppAccentButtonStyle())
                        .accessibilityIdentifier("postpurchase.getstarted")
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("postpurchase.sheet")
                }
            }
        }
        .modelContainer(for: [MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self], inMemory: true)
        .preferredColorScheme((AppAppearance(rawValue: appAppearance) ?? .system).preferredColorScheme)
        .accessibilityIdentifier("app.root.ready")
    }
}

private struct UnitTestHostView: View {
    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .accessibilityIdentifier("app.unit-test.host")
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
