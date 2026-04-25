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
