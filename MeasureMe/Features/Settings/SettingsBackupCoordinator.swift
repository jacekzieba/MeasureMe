import Foundation
import SwiftData

@MainActor
enum SettingsBackupCoordinator {
    struct BackupResultState {
        let message: String
        let isSuccess: Bool
    }

    enum RestorePreflightState {
        case readyToRestoreImmediately
        case needsConflictConfirmation(String)
        case failed(String)
    }

    static func performBackupNow(
        context: ModelContext,
        isPremium: Bool,
        isBackupEnabled: Bool
    ) async -> BackupResultState {
        guard isBackupEnabled else {
            return BackupResultState(
                message: AppLocalization.string("Enable automatic iCloud backup first."),
                isSuccess: false
            )
        }

        let result = await ICloudBackupService.createBackupNow(context: context, isPremium: isPremium)
        switch result {
        case .success(let manifest):
            return BackupResultState(
                message: AppLocalization.string(
                    "Backup complete. %d measurements, %d goals, %d photos saved.",
                    manifest.metricsCount,
                    manifest.goalsCount,
                    manifest.photosCount
                ),
                isSuccess: true
            )
        case .failure(let error):
            return BackupResultState(message: error.localizedMessage, isSuccess: false)
        }
    }

    static func preflightRestore(
        context: ModelContext,
        isPremium: Bool
    ) async -> RestorePreflightState {
        let preflightResult = await ICloudBackupService.preflightRestore(context: context, isPremium: isPremium)
        switch preflightResult {
        case .success(let manifest):
            let localData = fetchLocalDataSummary(context: context)
            guard localData.hasExistingData else {
                return .readyToRestoreImmediately
            }
            return .needsConflictConfirmation(
                restoreConflictMessage(localData: localData, manifest: manifest)
            )
        case .failure(let error):
            return .failed(error.localizedMessage)
        }
    }

    static func performRestore(
        context: ModelContext,
        isPremium: Bool
    ) async -> BackupResultState {
        let result = await ICloudBackupService.restoreLatestBackupManually(context: context, isPremium: isPremium)
        switch result {
        case .success:
            return BackupResultState(
                message: AppLocalization.string("Data restored successfully from iCloud backup."),
                isSuccess: true
            )
        case .failure(let error):
            return BackupResultState(message: error.localizedMessage, isSuccess: false)
        }
    }

    private struct LocalDataSummary {
        let metrics: Int
        let goals: Int
        let photos: Int

        var hasExistingData: Bool {
            metrics > 0 || goals > 0 || photos > 0
        }
    }

    private static func fetchLocalDataSummary(context: ModelContext) -> LocalDataSummary {
        LocalDataSummary(
            metrics: (try? context.fetchCount(FetchDescriptor<MetricSample>())) ?? 0,
            goals: (try? context.fetchCount(FetchDescriptor<MetricGoal>())) ?? 0,
            photos: (try? context.fetchCount(FetchDescriptor<PhotoEntry>())) ?? 0
        )
    }

    private static func restoreConflictMessage(
        localData: LocalDataSummary,
        manifest: ICloudBackupManifest
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let backupDate = formatter.string(from: manifest.createdAt)

        return AppLocalization.string(
            "Your data: %d measurements, %d goals, %d photos.",
            localData.metrics,
            localData.goals,
            localData.photos
        ) + "\n" + AppLocalization.string(
            "Backup from %@ contains %d measurements, %d goals, %d photos.",
            backupDate,
            manifest.metricsCount,
            manifest.goalsCount,
            manifest.photosCount
        )
    }
}
