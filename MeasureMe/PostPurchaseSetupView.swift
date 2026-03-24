import SwiftUI

struct PostPurchaseSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppSetting(\.iCloudBackup.isEnabled) private var iCloudBackupEnabled: Bool = false

    @State private var notificationsToggle: Bool = false
    @State private var backupToggle: Bool = false
    @State private var isRequestingPermission = false

    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 240, tint: Color.yellow.opacity(0.14))

            VStack(spacing: 0) {
                header
                    .padding(.top, 32)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                VStack(spacing: 12) {
                    notificationsRow
                    backupRow
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(AppLocalization.string("postpurchase.getstarted"))
                        .font(AppTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppAccentButtonStyle())
                .accessibilityIdentifier("postpurchase.getstarted")
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .accessibilityIdentifier("postpurchase.sheet")
        .onAppear {
            notificationsToggle = NotificationManager.shared.notificationsEnabled
            backupToggle = iCloudBackupEnabled
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.appAccent)

            Text(AppLocalization.string("postpurchase.title"))
                .font(AppTypography.displayStatement)
                .foregroundStyle(AppColorRoles.textPrimary)
                .multilineTextAlignment(.center)

            Text(AppLocalization.string("postpurchase.subtitle"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var notificationsRow: some View {
        AppGlassCard(depth: .base, tint: AppColorRoles.surfacePrimary, contentPadding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(AppTypography.iconLarge)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("postpurchase.notifications.title"))
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string("postpurchase.notifications.subtitle"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $notificationsToggle)
                    .labelsHidden()
                    .disabled(isRequestingPermission)
                    .onChange(of: notificationsToggle) { _, newValue in
                        if newValue {
                            isRequestingPermission = true
                            Task { @MainActor in
                                let granted = await NotificationManager.shared.requestAuthorization()
                                if granted {
                                    NotificationManager.shared.notificationsEnabled = true
                                } else {
                                    notificationsToggle = false
                                    NotificationManager.shared.notificationsEnabled = false
                                }
                                isRequestingPermission = false
                            }
                        } else {
                            NotificationManager.shared.notificationsEnabled = false
                        }
                    }
            }
        }
    }

    private var backupRow: some View {
        AppGlassCard(depth: .base, tint: AppColorRoles.surfacePrimary, contentPadding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(AppTypography.iconLarge)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("postpurchase.backup.title"))
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(AppLocalization.string("postpurchase.backup.subtitle"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                    if !isICloudAvailable {
                        Text(AppLocalization.string("iCloud Drive is unavailable on this device."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Toggle("", isOn: $backupToggle)
                    .labelsHidden()
                    .disabled(!isICloudAvailable)
                    .onChange(of: backupToggle) { _, newValue in
                        iCloudBackupEnabled = newValue
                    }
            }
        }
    }
}
