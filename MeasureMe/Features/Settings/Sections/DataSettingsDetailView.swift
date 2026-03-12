import SwiftUI

struct DataSettingsDetailView: View {
    @AppSetting(\.analytics.analyticsEnabled) private var analyticsEnabled: Bool = true
    @AppSetting(\.iCloudBackup.lastBackupSizeBytes) private var lastBackupSizeBytes: Int64 = 0
    @Binding var iCloudBackupEnabled: Bool
    let iCloudBackupLastSuccessText: String
    let iCloudBackupLastErrorText: String?
    let onExport: () -> Void
    let onImport: () -> Void
    let onBackupNow: () -> Void
    let onRestoreLatestBackup: () -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    private let theme = FeatureTheme.settings

    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Data"), theme: .settings) {
            Section {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")

                    Button(action: onExport) {
                        rowLabel(systemName: "square.and.arrow.up", title: AppLocalization.string("Export data"))
                    }
                    .buttonStyle(.plain)

                    SettingsRowDivider()

                    Button(action: onImport) {
                        rowLabel(systemName: "square.and.arrow.down", title: AppLocalization.string("Import data"))
                    }
                    .buttonStyle(.plain)

                    SettingsRowDivider()

                    HStack(alignment: .top, spacing: 12) {
                        GlassPillIcon(systemName: "icloud")
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string("Automatic iCloud backup"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                            Text(iCloudBackupLastSuccessText)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if lastBackupSizeBytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: lastBackupSizeBytes, countStyle: .file))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                            if let iCloudBackupLastErrorText, !iCloudBackupLastErrorText.isEmpty {
                                Text(iCloudBackupLastErrorText)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !isICloudAvailable {
                                Text(AppLocalization.string("iCloud Drive is unavailable on this device."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: $iCloudBackupEnabled)
                            .labelsHidden()
                            .frame(width: 52, alignment: .trailing)
                            .disabled(!isICloudAvailable)
                    }
                    .tint(theme.accent)
                    .onChange(of: iCloudBackupEnabled) { _, _ in
                        Haptics.selection()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("settings.data.icloud.toggle")

                    SettingsRowDivider()

                    Button(action: onBackupNow) {
                        rowLabel(systemName: "arrow.clockwise.icloud", title: AppLocalization.string("Back up now"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isICloudAvailable)
                    .accessibilityIdentifier("settings.data.icloud.backupNow")

                    SettingsRowDivider()

                    Button(action: onRestoreLatestBackup) {
                        rowLabel(
                            systemName: "icloud.and.arrow.down",
                            title: AppLocalization.string("Restore from backup"),
                            foreground: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isICloudAvailable)
                    .accessibilityIdentifier("settings.data.icloud.restoreLatest")

                    SettingsRowDivider()

                    HStack(alignment: .top, spacing: 12) {
                        GlassPillIcon(systemName: "chart.xyaxis.line")
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string("Share anonymous analytics"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                            Text(AppLocalization.string("Helps improve app quality and UX. No health values or personal data are sent."))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: $analyticsEnabled)
                            .labelsHidden()
                            .frame(width: 52, alignment: .trailing)
                    }
                    .tint(theme.accent)
                    .onChange(of: analyticsEnabled) { _, _ in
                        Haptics.selection()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("settings.data.analytics.toggle")

                    SettingsRowDivider()

                    Button(action: onSeedDummyData) {
                        rowLabel(systemName: "wand.and.stars", title: AppLocalization.string("Seed dummy data"))
                    }
                    .buttonStyle(.plain)

                    SettingsRowDivider()

                    SettingsDestructiveRow(
                        title: AppLocalization.string("Delete all data"),
                        systemImage: "trash",
                        action: onDeleteAll
                    )
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func rowLabel(systemName: String, title: String, foreground: Color = AppColorRoles.textPrimary) -> some View {
        HStack(spacing: 12) {
            GlassPillIcon(systemName: systemName)
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(foreground)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
