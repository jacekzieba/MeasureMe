import SwiftUI
import UIKit

struct HealthSettingsSection: View {
    private let theme = FeatureTheme.health
    @Binding var isSyncEnabled: Bool
    let lastImportText: String?
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool

    @State private var authorizationTask: Task<Void, Never>?
    @State private var isMetricsExpanded: Bool = false
    @State private var syncStatusMessage: String?
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            SettingsCard(tint: theme.softTint) {
                SettingsCardHeader(title: AppLocalization.string("Health"), systemImage: "heart.fill")
                syncRow
                SettingsRowDivider()
                metricsRow
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
        .onDisappear {
            // Anuluj task przy znikaniu widoku, aby uniknąć wycieku pamięci
            authorizationTask?.cancel()
        }
        .onAppear {
            scheduleSyncStateReconciliation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            scheduleSyncStateReconciliation()
        }
    }

    private var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
    }

    private var syncRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                GlassPillIcon(systemName: "heart.fill")
                Text(AppLocalization.string("Sync with Apple Health"))
                Spacer()
                Toggle("", isOn: $isSyncEnabled)
                    .labelsHidden()
                    .tint(theme.accent)
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityLabel(AppLocalization.string("Sync with Apple Health"))
                    .accessibilityIdentifier("settings.health.sync.toggle")
            }
            .frame(minHeight: 44)

            Text(AppLocalization.string("health.last.import", lastImportText ?? "—"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColorRoles.textSecondary)
                .padding(.leading, 44)

            if let syncStatusMessage {
                Text(syncStatusMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.stateError)
                    .padding(.leading, 44)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.health.sync.error")
            }
        }
        .onChange(of: isSyncEnabled) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Haptics.selection()
            authorizationTask?.cancel()

            if newValue {
                syncStatusMessage = nil
                authorizationTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }

                    do {
                        try await HealthKitManager.shared.requestAuthorization()
                        syncStatusMessage = nil
                    } catch {
                        isSyncEnabled = false
                        syncStatusMessage = HealthKitManager.userFacingSyncErrorMessage(for: error)
                        AppLog.debug("⚠️ HealthKit authorization failed: \(error.localizedDescription)")
                        Haptics.error()
                    }
                }
            } else {
                HealthKitManager.shared.stopObservingHealthKitUpdates()
            }
        }
    }

    private func reconcileSyncStateWithSystemAuthorization() {
        guard isSyncEnabled else { return }
        if let syncError = HealthKitManager.shared.reconcileStoredSyncState() {
            isSyncEnabled = false
            syncStatusMessage = HealthKitManager.userFacingSyncErrorMessage(for: syncError)
        }
    }

    private func scheduleSyncStateReconciliation() {
        Task { @MainActor in
            reconcileSyncStateWithSystemAuthorization()
        }
    }

    private var metricsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
                Button {
                    isMetricsExpanded.toggle()
                } label: {
                HStack {
                    Text(AppLocalization.string("Synced data"))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isMetricsExpanded ? 180 : 0))
                        .foregroundStyle(AppColorRoles.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)

                if isMetricsExpanded {
                    VStack(spacing: 0) {
                    healthMetricRow(AppLocalization.string("metric.weight"), isOn: $hkWeight)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.bodyfat"), isOn: $hkBodyFat)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.height"), isOn: $hkHeight)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.leanbodymass"), isOn: $hkLeanMass)
                    rowDivider
                    healthMetricRow(AppLocalization.string("metric.waist"), isOn: $hkWaist)
                }
                .disabled(!isSyncEnabled)
                .onChange(of: hkWeight) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkBodyFat) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkHeight) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkLeanMass) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .onChange(of: hkWaist) { _, _ in HealthKitManager.shared.startObservingHealthKitUpdates() }
                .padding(.top, 6)
                }
            }
        }

    private var rowDivider: some View {
        Divider()
            .overlay(AppColorRoles.borderSubtle)
            .padding(.vertical, 4)
    }

    private func healthMetricRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
        Toggle("", isOn: isOn)
                .labelsHidden()
                .accessibilityLabel(title)
                .frame(width: 52, alignment: .trailing)
        }
        .tint(theme.accent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}
