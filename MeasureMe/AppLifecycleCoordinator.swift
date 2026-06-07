// AppLifecycleCoordinator.swift
//
// **AppLifecycleCoordinator**
// Centralized entry point for coordinating app startup, background work,
// and lifecycle-driven side effects.
//
// **Responsibilities:**
// - Orchestrating deferred post-launch work (storage protection, HealthKit, iCloud, widgets, watch)
// - Registering and scheduling `BGTaskScheduler` jobs (iCloud backup, AI notifications)
// - Flushing transient state when the app resigns active (widget writes, crash log buffer)
// - Owning the dependency-injection seam used by tests to stub scheduler/container behavior
//
// **Why a coordinator (not a class):**
// The work is a set of stateless side-effect entry points invoked from `MeasureMeApp`.
// A namespace enum keeps call sites readable (`AppLifecycleCoordinator.performDeferredStartup(...)`)
// and avoids requiring a shared instance whose lifetime would have to be reasoned about.
//
// **Threading:**
// `performDeferredStartup` and lifecycle callbacks that touch `ModelContainer` are
// `@MainActor`-isolated. Background-task handlers spawn detached `Task`s and hop to
// `MainActor` only when they need to touch UIKit or shared singletons.
//
import BackgroundTasks
import SwiftData
import UIKit

/// Coordinator for app-level lifecycle hooks (startup, background, willResignActive).
///
/// All methods are static — this is a namespace, not an injectable service.
/// `dependencies` is the only mutable surface and exists purely for test stubs.
enum AppLifecycleCoordinator {
    // MARK: - Constants

    /// Background task identifier for scheduled iCloud backups.
    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist`.
    private static let backgroundBackupTaskID = "com.jacek.measureme.icloud-backup"

    /// Background task identifier for AI-driven notification refresh.
    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in `Info.plist`.
    private static let backgroundAINotificationsTaskID = "com.jacek.measureme.ai-notifications"

    // MARK: - Dependencies (test seam)

    /// Injectable closures used by lifecycle methods. Tests swap these to assert
    /// behavior without exercising real widgets, BG scheduler, or the file system.
    struct Dependencies {
        /// Flushes any debounced widget payload writes to disk.
        var flushPendingWidgetWrites: () -> Void = {
            WidgetDataWriter.flushPendingWrites()
        }
        /// Persists the in-memory crash log buffer to disk before the app suspends.
        var persistCrashLogBuffer: () -> Void = {
            CrashReporter.shared.persistLogBuffer()
        }
        /// Runs the user-configured scheduled iCloud backup, gated by Premium.
        var runScheduledBackup: @MainActor (ModelContainer) async -> Void = { container in
            let context = ModelContext(container)
            let isPremium = AppSettingsStore.shared.snapshot.premium.premiumEntitlement
            await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: isPremium)
        }
        /// Submits a `BGTaskRequest` to the system scheduler. Stubbed in tests.
        var submitBackgroundTaskRequest: (BGTaskRequest) throws -> Void = { request in
            try BGTaskScheduler.shared.submit(request)
        }
    }

    /// Process-wide dependency overrides. Reset by `resetDependencies()` in test setUp/tearDown.
    static var dependencies = Dependencies()

    /// Restores `dependencies` to production defaults. Call from test tearDown.
    static func resetDependencies() {
        dependencies = Dependencies()
    }

    // MARK: - Errors

    private enum LifecycleStorageError: LocalizedError {
        case applicationSupportDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportDirectoryUnavailable:
                return "Application Support directory is unavailable."
            }
        }
    }

    // MARK: - Deferred Startup

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

    /// Applies recommended file protection to the on-disk database.
    /// Priority: `.utility` — runs after first frame, no user-visible latency requirement.
    private static func scheduleDeferredStorageProtection() {
        Task(priority: .utility) {
            let storageProtectionState = StartupInstrumentation.begin("DeferredStorageProtection")
            DatabaseEncryption.applyRecommendedProtectionIfNeeded()
            StartupInstrumentation.end("DeferredStorageProtection", state: storageProtectionState)
        }
    }

    /// Configures HealthKit, schedules notifications, and processes any deferred
    /// intent-driven syncs. Sleeps 200 ms so the first frame has time to render
    /// before this `Task` competes for the main actor.
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

    /// Attempts to restore the latest iCloud backup. If a restore actually occurs,
    /// the localized message is forwarded to the caller so the UI can surface it.
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

    /// Refreshes widgets and pushes the current snapshot to the paired Apple Watch.
    /// Priority `.background` and 600 ms delay so it runs after the rest of startup work.
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

    /// Runs the scheduled iCloud backup and re-arms background tasks as needed.
    /// Sleeps 800 ms — the longest of the deferred phases — to ensure it runs last.
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

    /// Configures and activates `WatchSessionManager` so the paired watch receives
    /// a fresh `applicationContext` snapshot on launch.
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

    // MARK: - Foreground → Background Transition

    /// Flushes transient state when the app is about to leave the foreground.
    /// Widget writes and the crash log buffer are the two pieces of state that
    /// must not be lost when the system suspends the app.
    static func handleWillResignActive(container: ModelContainer?, isRunningXCTest: Bool) {
        // Always flush — these are cheap and matter even under test (in-memory).
        dependencies.flushPendingWidgetWrites()
        dependencies.persistCrashLogBuffer()

        // Skip scheduled backup in tests and when the model container is unavailable.
        guard !isRunningXCTest, let container else { return }
        Task(priority: .utility) {
            await dependencies.runScheduledBackup(container)
        }
    }

    // MARK: - Background Task Registration

    /// Registers handlers for the two `BGTaskScheduler` identifiers used by the app.
    /// Must be called from `application(_:didFinishLaunchingWithOptions:)` before
    /// the launch sequence returns, otherwise the system will not invoke the handlers.
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

    /// Schedules a daily iCloud backup (24h earliest begin) requiring network.
    static func scheduleBackgroundBackup() {
        let request = BGProcessingTaskRequest(identifier: backgroundBackupTaskID)
        request.requiresNetworkConnectivity = true
        // 24h = 86 400 s; this is a hint, the system decides the actual fire time.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 86_400)
        try? dependencies.submitBackgroundTaskRequest(request)
    }

    /// Schedules an AI-notification refresh every 6h (21 600 s) that does not
    /// require network — Apple Intelligence runs on-device.
    static func scheduleBackgroundAINotifications() {
        let request = BGProcessingTaskRequest(identifier: backgroundAINotificationsTaskID)
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 21_600)
        try? dependencies.submitBackgroundTaskRequest(request)
    }

    // MARK: - Background Task Handlers

    /// System-invoked handler for the iCloud backup background task.
    /// Wires the BGProcessingTask's expiration handler to cancel the in-flight
    /// `Task` so we don't run past the system's budget.
    private static func handleBackgroundBackup(task: BGProcessingTask) {
        let operation = Task {
            do {
                let container = try createBackgroundModelContainer()
                let context = ModelContext(container)
                let isPremium = AppSettingsStore.shared.snapshot.premium.premiumEntitlement
                await ICloudBackupService.runScheduledBackupIfNeeded(context: context, isPremium: isPremium)
            } catch {
                // Container creation failed; nothing to back up.
                // Swallowed: the next scheduled run will retry.
            }
        }
        task.expirationHandler = { operation.cancel() }
        Task {
            _ = await operation.result
            task.setTaskCompleted(success: true)
            let snapshot = AppSettingsStore.shared.snapshot
            if snapshot.premium.premiumEntitlement, snapshot.iCloudBackup.isEnabled {
                // Re-arm for the next day only when the user still has backup enabled.
                scheduleBackgroundBackup()
            }
        }
    }

    /// System-invoked handler for the AI notifications background task.
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

    // MARK: - Background Model Container

    /// Builds a fresh `ModelContainer` for use inside a background `BGProcessingTask`.
    ///
    /// Background tasks run without the app's main `ModelContainer` instance, so we
    /// build a minimal container scoped to the SwiftData models needed for backup
    /// and notification generation. CloudKit sync is explicitly disabled — the app
    /// uses its own iCloud backup flow instead.
    ///
    /// - Throws: `LifecycleStorageError.applicationSupportDirectoryUnavailable` when
    ///   the system cannot provide a writable Application Support directory.
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
