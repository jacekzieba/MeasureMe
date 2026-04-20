import SwiftUI

struct DataSettingsDetailView: View {
    @AppSetting(\.analytics.analyticsEnabled) private var analyticsEnabled: Bool = true
    @AppSetting(\.privacy.requireBiometricForPhotos) private var requireBiometricForPhotos: Bool = false
    @AppSetting(\.iCloudBackup.lastBackupSizeBytes) private var lastBackupSizeBytes: Int64 = 0
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
                            Text(AppLocalization.string("Encrypted backup. Premium only."))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                            Text(iCloudBackupLastSuccessText)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if lastBackupSizeBytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: lastBackupSizeBytes, countStyle: .file))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                            if !isPremium {
                                Text(AppLocalization.string("Upgrade to Premium to enable encrypted iCloud backup and restore."))
                                    .font(AppTypography.captionEmphasis)
                                    .foregroundStyle(theme.accent)
                            } else if let iCloudBackupLastErrorText, !iCloudBackupLastErrorText.isEmpty {
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
                            .disabled(!isICloudAvailable || !isPremium)
                            .accessibilityLabel(AppLocalization.string("Automatic iCloud backup"))
                            .accessibilityValue(iCloudBackupEnabled ? AppLocalization.string("Enabled") : AppLocalization.string("Disabled"))
                            .accessibilityHint(AppLocalization.string("Turns encrypted iCloud backup on or off for your measurements and photos."))
                    }
                    .tint(theme.accent)
                    .onChange(of: iCloudBackupEnabled) { _, _ in
                        Haptics.selection()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("settings.data.icloud.toggle")

                    if !isPremium {
                        SettingsRowDivider()

                        Button(action: onUnlockICloudBackup) {
                            rowLabel(
                                systemName: "crown",
                                title: AppLocalization.string("Unlock in Premium"),
                                foreground: theme.accent
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.data.icloud.unlockPremium")
                    }

                    SettingsRowDivider()

                    Button(action: onBackupNow) {
                        HStack(spacing: 12) {
                            if isBackingUp {
                                ProgressView()
                                    .frame(width: 22, height: 22)
                            } else {
                                GlassPillIcon(systemName: "arrow.clockwise.icloud")
                            }
                            Text(AppLocalization.string("Back up now"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBackingUp || (isPremium && !isICloudAvailable))
                    .simultaneousGesture(TapGesture().onEnded {
                        guard !isPremium else { return }
                        onUnlockICloudBackup()
                    })
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
                    .disabled(isPremium && !isICloudAvailable)
                    .simultaneousGesture(TapGesture().onEnded {
                        guard !isPremium else { return }
                        onUnlockICloudBackup()
                    })
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
                            .accessibilityLabel(AppLocalization.string("Share anonymous analytics"))
                            .accessibilityValue(analyticsEnabled ? AppLocalization.string("Enabled") : AppLocalization.string("Disabled"))
                            .accessibilityHint(AppLocalization.string("Turns anonymous product analytics on or off."))
                    }
                    .tint(theme.accent)
                    .onChange(of: analyticsEnabled) { _, _ in
                        Haptics.selection()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("settings.data.analytics.toggle")

                    SettingsRowDivider()

                    HStack(alignment: .top, spacing: 12) {
                        GlassPillIcon(systemName: "faceid")
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string("Require Face ID to view photos"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                            Text(AppLocalization.string("Blurs progress photos until you unlock them."))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: $requireBiometricForPhotos)
                            .labelsHidden()
                            .frame(width: 52, alignment: .trailing)
                            .accessibilityLabel(AppLocalization.string("Require Face ID to view photos"))
                            .accessibilityValue(requireBiometricForPhotos ? AppLocalization.string("Enabled") : AppLocalization.string("Disabled"))
                    }
                    .tint(theme.accent)
                    .onChange(of: requireBiometricForPhotos) { _, _ in
                        Haptics.selection()
                        PhotoPrivacyGate.shared.lock()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("settings.data.photosPrivacy.toggle")

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
