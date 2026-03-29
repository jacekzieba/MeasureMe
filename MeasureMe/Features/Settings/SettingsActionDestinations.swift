import SwiftUI

struct SettingsDataDestinationView: View {
    @Binding var iCloudBackupEnabled: Bool
    @Binding var isBackingUp: Bool

    let isPremium: Bool
    let iCloudBackupLastSuccessText: String
    let iCloudBackupLastErrorText: String?
    let onExport: (SettingsExporter.ExportFormat, Date?) -> Void
    let onImport: () -> Void
    let onBackupNow: () -> Void
    let onRestoreLatestBackup: () -> Void
    let onPresentPremiumFeature: (String) -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    @State private var showExportFormatPicker = false
    @State private var showPDFRangeSheet = false

    var body: some View {
        DataSettingsDetailView(
            iCloudBackupEnabled: $iCloudBackupEnabled,
            isBackingUp: $isBackingUp,
            isPremium: isPremium,
            iCloudBackupLastSuccessText: iCloudBackupLastSuccessText,
            iCloudBackupLastErrorText: iCloudBackupLastErrorText,
            onExport: handleExportTap,
            onImport: handleImportTap,
            onBackupNow: handleBackupNowTap,
            onRestoreLatestBackup: handleRestoreLatestBackupTap,
            onUnlockICloudBackup: handleUnlockICloudBackupTap,
            onSeedDummyData: handleSeedDummyDataTap,
            onDeleteAll: handleDeleteAllTap
        )
        .confirmationDialog(
            AppLocalization.string("Export format"),
            isPresented: $showExportFormatPicker
        ) {
            Button("CSV") { onExport(.csv, nil) }
            Button("JSON") { onExport(.json, nil) }
            Button(AppLocalization.string("PDF Report")) { showPDFRangeSheet = true }
            Button(AppLocalization.string("Cancel"), role: .cancel) { }
        } message: {
            Text(AppLocalization.string("Choose an export format"))
        }
        .sheet(isPresented: $showPDFRangeSheet) {
            ExportPDFRangeSheet { startDate in
                onExport(.pdf, startDate)
            }
        }
    }

    private func handleExportTap() {
        Haptics.light()
        guard isPremium else {
            onPresentPremiumFeature("Data export")
            return
        }
        showExportFormatPicker = true
    }

    private func handleImportTap() {
        Haptics.light()
        SettingsDataActions.runPremiumAction(
            isPremium: isPremium,
            feature: "Data import",
            onAllowed: onImport,
            onLocked: onPresentPremiumFeature
        )
    }

    private func handleBackupNowTap() {
        Haptics.light()
        SettingsDataActions.runPremiumAction(
            isPremium: isPremium,
            feature: "iCloud Backup",
            onAllowed: onBackupNow,
            onLocked: onPresentPremiumFeature
        )
    }

    private func handleRestoreLatestBackupTap() {
        Haptics.light()
        SettingsDataActions.runPremiumAction(
            isPremium: isPremium,
            feature: "iCloud Backup",
            onAllowed: onRestoreLatestBackup,
            onLocked: onPresentPremiumFeature
        )
    }

    private func handleUnlockICloudBackupTap() {
        Haptics.light()
        onPresentPremiumFeature("iCloud Backup")
    }

    private func handleSeedDummyDataTap() {
        Haptics.light()
        onSeedDummyData()
    }

    private func handleDeleteAllTap() {
        Haptics.light()
        onDeleteAll()
    }
}

struct SettingsAboutDestinationView: View {
    let onReportBug: () -> Void

    var body: some View {
        AboutSettingsDetailView(onReportBug: handleReportBug)
    }

    private func handleReportBug() {
        Haptics.light()
        onReportBug()
    }
}
