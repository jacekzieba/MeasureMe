import BackgroundTasks
import SwiftData
import UIKit

enum AppLifecycleCoordinator {
    private static let backgroundBackupTaskID = "com.jacek.measureme.icloud-backup"
    private static let backgroundAINotificationsTaskID = "com.jacek.measureme.ai-notifications"

    struct Dependencies {
        var flushPendingWidgetWrites: () -> Void = {
            WidgetDataWriter.flushPendingWrites()
        }
        var persistCrashLogBuffer: () -> Void = {
            CrashReporter.shared.persistLogBuffer()
        }
        var runScheduledBackup: @MainActor (ModelContainer) async -> Void = { container in
            let context = ModelContext(container)
            let isPremium = AppSettingsStore.shared.snapshot.premium.premiumEntitlement
            await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: isPremium)
        }
        var submitBackgroundTaskRequest: (BGTaskRequest) throws -> Void = { request in
            try BGTaskScheduler.shared.submit(request)
        }
    }

    static var dependencies = Dependencies()

    static func resetDependencies() {
        dependencies = Dependencies()
    }

    private enum LifecycleStorageError: LocalizedError {
        case applicationSupportDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportDirectoryUnavailable:
                return "Application Support directory is unavailable."
            }
        }
    }

    /// Runs the post–first-frame deferred startup work that was previously scattered
    /// across multiple `Task {}` blocks inside `MeasureMeApp`. Each phase keeps its
    /// original priority, sleep, and `StartupInstrumentation` instrumentation so that
    /// runtime behavior is unchanged.
    ///
    /// - Parameters:
    ///   - container: The fully initialized `ModelContainer` for the running app.
    ///   - isRunningXCTest: Mirrors `MeasureMeApp.isRunningXCTest`; when `true` this
    ///     method is a no-op (matches the previous early-return in `runDeferredStartupWork`).
    ///   - settingsStore: Used to read the units system for widget refresh.
    ///   - onAutoRestoreCompleted: Invoked on the main actor when iCloud auto-restore
    ///     actually performed a restore, so the app can present the user-facing alert.
    @MainActor
    static func performDeferredStartup(
        container: ModelContainer,
        isRunningXCTest: Bool,
        settingsStore: AppSettingsStore,
        onAutoRestoreCompleted: @escaping @MainActor (String) -> Void
    ) {
        guard !isRunningXCTest else { return }

        scheduleDeferredStorageProtection()
        scheduleDeferredHealthSetup(container: container)
        scheduleDeferredAutoRestore(container: container, onAutoRestoreCompleted: onAutoRestoreCompleted)
        scheduleDeferredWidgetRefresh(container: container, settingsStore: settingsStore)
        scheduleDeferredBackupMaintenance(container: container)
        scheduleDeferredWatchConnectivity(container: container)
    }

    private static func scheduleDeferredStorageProtection() {
        Task(priority: .utility) {
            let storageProtectionState = StartupInstrumentation.begin("DeferredStorageProtection")
            DatabaseEncryption.applyRecommendedProtectionIfNeeded()
            StartupInstrumentation.end("DeferredStorageProtection", state: storageProtectionState)
        }
    }

    private static func scheduleDeferredHealthSetup(container: ModelContainer) {
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

    private static func scheduleDeferredAutoRestore(
        container: ModelContainer,
        onAutoRestoreCompleted: @escaping @MainActor (String) -> Void
    ) {
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            let autoRestoreState = StartupInstrumentation.begin("DeferredICloudAutoRestore")
            let context = ModelContext(container)
            let didRestore = await ICloudBackupService.restoreLatestBackupIfNeededOnStartup(context: context)
            if didRestore {
                await MainActor.run {
                    onAutoRestoreCompleted(AppLocalization.string("Latest iCloud backup was restored automatically. Review your measurements and photos to confirm everything looks right."))
                }
            }
            StartupInstrumentation.end("DeferredICloudAutoRestore", state: autoRestoreState)
        }
    }

    private static func scheduleDeferredWidgetRefresh(container: ModelContainer, settingsStore: AppSettingsStore) {
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

    private static func scheduleDeferredBackupMaintenance(container: ModelContainer) {
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

    private static func scheduleDeferredWatchConnectivity(container: ModelContainer) {
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

    static func handleWillResignActive(container: ModelContainer?, isRunningXCTest: Bool) {
        dependencies.flushPendingWidgetWrites()
        dependencies.persistCrashLogBuffer()

        guard !isRunningXCTest, let container else { return }
        Task(priority: .utility) {
            await dependencies.runScheduledBackup(container)
        }
    }

    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundBackupTaskID,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleBackgroundBackup(task: processingTask)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundAINotificationsTaskID,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleBackgroundAINotifications(task: processingTask)
        }
    }

    static func scheduleBackgroundBackup() {
        let request = BGProcessingTaskRequest(identifier: backgroundBackupTaskID)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 86_400)
        try? dependencies.submitBackgroundTaskRequest(request)
    }

    static func scheduleBackgroundAINotifications() {
        let request = BGProcessingTaskRequest(identifier: backgroundAINotificationsTaskID)
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 21_600)
        try? dependencies.submitBackgroundTaskRequest(request)
    }

    private static func handleBackgroundBackup(task: BGProcessingTask) {
        let operation = Task {
            do {
                let container = try createBackgroundModelContainer()
                let context = ModelContext(container)
                let isPremium = AppSettingsStore.shared.snapshot.premium.premiumEntitlement
                await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: isPremium)
            } catch {
                // Container creation failed; nothing to back up.
            }
        }
        task.expirationHandler = { operation.cancel() }
        Task {
            _ = await operation.result
            task.setTaskCompleted(success: true)
            let snapshot = AppSettingsStore.shared.snapshot
            if snapshot.premium.premiumEntitlement, snapshot.iCloudBackup.isEnabled {
                scheduleBackgroundBackup()
            }
        }
    }

    private static func handleBackgroundAINotifications(task: BGProcessingTask) {
        let operation = Task {
            do {
                let container = try createBackgroundModelContainer()
                let context = ModelContext(container)
                await MainActor.run {
                    NotificationManager.shared.scheduleAINotificationsIfNeeded(
                        context: context,
                        trigger: .backgroundRefresh
                    )
                }
            } catch {
                // Ignore background AI failures and retry later.
            }
        }
        task.expirationHandler = { operation.cancel() }
        Task {
            _ = await operation.result
            task.setTaskCompleted(success: true)
            let snapshot = AppSettingsStore.shared.snapshot
            if snapshot.notifications.notificationsEnabled,
               snapshot.notifications.aiNotificationsEnabled {
                scheduleBackgroundAINotifications()
            }
        }
    }

    private static func createBackgroundModelContainer() throws -> ModelContainer {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LifecycleStorageError.applicationSupportDirectoryUnavailable
        }
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
