import SwiftUI

struct SettingsDataSection: View {
    @Binding var iCloudBackupEnabled: Bool
    let iCloudBackupLastSuccessText: String
    let iCloudBackupLastErrorText: String?
    let onExport: () -> Void
    let onImport: () -> Void
    let onBackupNow: () -> Void
    let onRestoreLatestBackup: () -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                NavigationLink {
                    DataSettingsDetailView(
                        iCloudBackupEnabled: $iCloudBackupEnabled,
                        iCloudBackupLastSuccessText: iCloudBackupLastSuccessText,
                        iCloudBackupLastErrorText: iCloudBackupLastErrorText,
                        onExport: onExport,
                        onImport: onImport,
                        onBackupNow: onBackupNow,
                        onRestoreLatestBackup: onRestoreLatestBackup,
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
