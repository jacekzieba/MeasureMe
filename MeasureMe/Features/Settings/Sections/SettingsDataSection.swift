import SwiftUI

struct SettingsDataSection: View {
    @Binding var iCloudBackupEnabled: Bool
    @Binding var isBackingUp: Bool
    let isPremium: Bool
    let iCloudBackupLastSuccessText: String
    let iCloudBackupLastErrorText: String?
    let onExport: () -> Void
    let onImport: () -> Void
    let onBackupNow: () -> Void
    let onRestoreLatestBackup: () -> Void
    let onUnlockICloudBackup: () -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                NavigationLink {
                    DataSettingsDetailView(
                        iCloudBackupEnabled: $iCloudBackupEnabled,
                        isBackingUp: $isBackingUp,
                        isPremium: isPremium,
                        iCloudBackupLastSuccessText: iCloudBackupLastSuccessText,
                        iCloudBackupLastErrorText: iCloudBackupLastErrorText,
                        onExport: onExport,
                        onImport: onImport,
                        onBackupNow: onBackupNow,
                        onRestoreLatestBackup: onRestoreLatestBackup,
                        onUnlockICloudBackup: onUnlockICloudBackup,
                        onSeedDummyData: onSeedDummyData,
                        onDeleteAll: onDeleteAll
                    )
                } label: {
                    Text(AppLocalization.string("Open data settings"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
