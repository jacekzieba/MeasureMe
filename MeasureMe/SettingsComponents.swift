import SwiftData
import SwiftUI
import UIKit

// MARK: - Settings Constants

fileprivate let settingsComponentsCardCornerRadius: CGFloat = 16
fileprivate let settingsComponentsRowInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

struct HealthSettingsSection: View {
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
    @AppSetting("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
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
            reconcileSyncStateWithSystemAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            reconcileSyncStateWithSystemAuthorization()
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
                    .tint(Color.appAccent)
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityLabel(AppLocalization.string("Sync with Apple Health"))
                    .accessibilityIdentifier("settings.health.sync.toggle")
            }
            .frame(minHeight: 44)
            
            Text(AppLocalization.string("health.last.import", lastImportText ?? "—"))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)

            if let syncStatusMessage {
                Text(syncStatusMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
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
                        .foregroundStyle(.secondary)
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
            .overlay(Color.white.opacity(0.12))
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
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

struct UnitsSettingsSection: View {
    @Binding var unitsSystem: String
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                SettingsCardHeader(title: AppLocalization.string("Units"), systemImage: "ruler")
                Picker(AppLocalization.string("Units"), selection: $unitsSystem) {
                    Text(AppLocalization.string("Metric")).tag("metric")
                    Text(AppLocalization.string("Imperial")).tag("imperial")
                }
                .pickerStyle(.segmented)
                .glassSegmentedControl(tint: Color.appAccent)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}

struct ProfileSettingsDetailView: View {
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                ProfileSettingsSection(
                    userName: $userName,
                    userGender: $userGender,
                    userAge: $userAge,
                    manualHeight: $manualHeight,
                    unitsSystem: $unitsSystem
                )
                ProfileStatsCard()
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct IndicatorsSettingsDetailView: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showBodyShapeScoreOnHome: Bool
    @Binding var showCentralFatRiskOnHome: Bool
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                IndicatorsSettingsSection(
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showWHROnHome: $showWHROnHome,
                    showWaistRiskOnHome: $showWaistRiskOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showABSIOnHome: $showABSIOnHome,
                    showBodyShapeScoreOnHome: $showBodyShapeScoreOnHome,
                    showCentralFatRiskOnHome: $showCentralFatRiskOnHome,
                    showPhysiqueSWR: $showPhysiqueSWR,
                    showPhysiqueCWR: $showPhysiqueCWR,
                    showPhysiqueSHR: $showPhysiqueSHR,
                    showPhysiqueHWR: $showPhysiqueHWR,
                    showPhysiqueBWR: $showPhysiqueBWR,
                    showPhysiqueWHtR: $showPhysiqueWHtR,
                    showPhysiqueBodyFat: $showPhysiqueBodyFat,
                    showPhysiqueRFM: $showPhysiqueRFM
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HealthIndicatorsSettingsDetailView: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showBodyShapeScoreOnHome: Bool
    @Binding var showCentralFatRiskOnHome: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HealthIndicatorsSettingsSection(
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showWHROnHome: $showWHROnHome,
                    showWaistRiskOnHome: $showWaistRiskOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showABSIOnHome: $showABSIOnHome,
                    showBodyShapeScoreOnHome: $showBodyShapeScoreOnHome,
                    showCentralFatRiskOnHome: $showCentralFatRiskOnHome
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Health indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct PhysiqueIndicatorsSettingsDetailView: View {
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                PhysiqueIndicatorsSettingsSection(
                    showPhysiqueSWR: $showPhysiqueSWR,
                    showPhysiqueCWR: $showPhysiqueCWR,
                    showPhysiqueSHR: $showPhysiqueSHR,
                    showPhysiqueHWR: $showPhysiqueHWR,
                    showPhysiqueBWR: $showPhysiqueBWR,
                    showPhysiqueWHtR: $showPhysiqueWHtR,
                    showPhysiqueBodyFat: $showPhysiqueBodyFat,
                    showPhysiqueRFM: $showPhysiqueRFM
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Physique indicators"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HomeSettingsDetailView: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    @Binding var showOnboardingChecklistOnHome: Bool
    @Binding var showStreakOnHome: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HomeSettingsSection(
                    showMeasurementsOnHome: $showMeasurementsOnHome,
                    showLastPhotosOnHome: $showLastPhotosOnHome,
                    showHealthMetricsOnHome: $showHealthMetricsOnHome,
                    showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome,
                    showStreakOnHome: $showStreakOnHome
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Home"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct ExperienceSettingsDetailView: View {
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.08)) {
                        SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "apple.haptics.and.music.note")
                        Toggle(isOn: $animationsEnabled) {
                            Text(AppLocalization.string("Animations"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: animationsEnabled) { _, _ in Haptics.selection() }
                        .frame(minHeight: 44)

                        SettingsRowDivider()

                        Toggle(isOn: $hapticsEnabled) {
                            Text(AppLocalization.string("Haptics"))
                        }
                        .tint(Color.appAccent)
                        .onChange(of: hapticsEnabled) { _, _ in Haptics.selection() }
                        .frame(minHeight: 44)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Animations and haptics"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct LanguageSettingsDetailView: View {
    @Binding var appLanguage: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("Language"), systemImage: "globe")
                        languageRow(title: AppLocalization.string("System"), value: "system")
                        SettingsRowDivider()
                        languageRow(title: AppLocalization.string("English"), value: "en")
                        SettingsRowDivider()
                        languageRow(title: AppLocalization.string("Polish"), value: "pl")
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Language"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func languageRow(title: String, value: String) -> some View {
        Button {
            appLanguage = value
            AppLocalization.reloadLanguage()
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.white)
                Spacer()
                languageAccessory(for: value)
                    .frame(width: 16, alignment: .trailing)
            }
            .padding(.trailing, 2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func languageAccessory(for value: String) -> some View {
        if appLanguage == value {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.appAccent)
        } else {
            Color.clear
        }
    }
}

struct DataSettingsDetailView: View {
    @AppSetting("analytics_enabled") private var analyticsEnabled: Bool = true
    let onExport: () -> Void
    let onImport: () -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                        Button(action: onExport) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "square.and.arrow.up")
                                Text(AppLocalization.string("Export data"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button(action: onImport) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "square.and.arrow.down")
                                Text(AppLocalization.string("Import data"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        HStack(alignment: .top, spacing: 12) {
                            GlassPillIcon(systemName: "chart.xyaxis.line")
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLocalization.string("Share anonymous analytics"))
                                Text(AppLocalization.string("Helps improve app quality and UX. No health values or personal data are sent."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Toggle("", isOn: $analyticsEnabled)
                                .labelsHidden()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .tint(Color.appAccent)
                        .onChange(of: analyticsEnabled) { _, _ in
                            Haptics.selection()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("settings.data.analytics.toggle")

                        SettingsRowDivider()

                        Button(action: onSeedDummyData) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "wand.and.stars")
                                Text(AppLocalization.string("Seed dummy data"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button(role: .destructive, action: onDeleteAll) {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "trash")
                                Text(AppLocalization.string("Delete all data"))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Data"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct AboutSettingsDetailView: View {
    @AppSetting("diagnostics_logging_enabled") private var diagnosticsLoggingEnabled: Bool = true
    @Environment(\.openURL) private var openURL
    let onReportBug: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("About"), systemImage: "info.circle")

                        Button {
                            openURL(LegalLinks.about)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "safari")
                                Text(AppLocalization.string("Website"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.featureRequest)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "lightbulb")
                                Text(AppLocalization.string("Feature request"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        SettingsRowDivider()

                        Button {
                            onReportBug()
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "ladybug")
                                Text(AppLocalization.string("Report a bug"))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Diagnostics"), systemImage: "exclamationmark.bubble")

                        NavigationLink {
                            CrashReportView()
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "exclamationmark.bubble")
                                Text(AppLocalization.string("Crash Reports"))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }

                        SettingsRowDivider()

                        HStack(alignment: .top, spacing: 12) {
                            GlassPillIcon(systemName: "doc.text")
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLocalization.string("Include diagnostic logs in crash reports"))
                                Text(AppLocalization.string("When enabled, recent app logs may be attached to reports you share."))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Toggle("", isOn: $diagnosticsLoggingEnabled)
                                .labelsHidden()
                                .frame(width: 52, alignment: .trailing)
                        }
                        .tint(Color.appAccent)
                        .onChange(of: diagnosticsLoggingEnabled) { _, _ in
                            Haptics.selection()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("settings.data.diagnostics.logging.toggle")
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.04)) {
                        SettingsCardHeader(title: AppLocalization.string("Credits"), systemImage: "heart")

                        Button {
                            openURL(URL(string: "https://icons8.com")!)
                        } label: {
                            HStack(spacing: 12) {
                                GlassPillIcon(systemName: "paintbrush")
                                Text(AppLocalization.string("Icons by Icons8"))
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("About"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct HealthSettingsDetailView: View {
    @Binding var isSyncEnabled: Bool
    let lastImportText: String?
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                HealthSettingsSection(
                    isSyncEnabled: $isSyncEnabled,
                    lastImportText: lastImportText,
                    hkWeight: $hkWeight,
                    hkBodyFat: $hkBodyFat,
                    hkHeight: $hkHeight,
                    hkLeanMass: $hkLeanMass,
                    hkWaist: $hkWaist
                )
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Health"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct UnitsSettingsDetailView: View {
    @Binding var unitsSystem: String

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                UnitsSettingsSection(unitsSystem: $unitsSystem)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Units"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct AIInsightsSettingsDetailView: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Binding var appleIntelligenceEnabled: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.cyan.opacity(0.22))
            List {
                Section {
                    SettingsCard(tint: Color.cyan.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("AI Insights"), systemImage: "sparkles")
                        if premiumStore.isPremium {
                            if AppleIntelligenceSupport.isAvailable() {
                                Toggle(isOn: $appleIntelligenceEnabled) {
                                    Text(AppLocalization.string("Enable AI Insights"))
                                }
                                .tint(Color.appAccent)
                                .onChange(of: appleIntelligenceEnabled) { _, _ in Haptics.selection() }
                                .frame(minHeight: 44)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AppLocalization.string("AI Insights aren’t available right now."))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                    NavigationLink {
                                        FAQView()
                                    } label: {
                                        Text(AppLocalization.string("Learn more in FAQ"))
                                            .font(AppTypography.captionEmphasis)
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(AppLocalization.string("Premium Edition required"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(AppLocalization.string("Unlock")) {
                                    premiumStore.presentPaywall(reason: .feature("AI Insights"))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.appAccent)
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(settingsComponentsRowInsets)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("AI Insights"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct ProfileSettingsSection: View {
    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String

    @State private var ageInput: String = ""
    @State private var heightInput: String = ""

    private var genderLabel: String {
        switch userGender {
        case "male":
            return AppLocalization.string("Male")
        case "female":
            return AppLocalization.string("Female")
        default:
            return AppLocalization.string("Not specified")
        }
    }

    private var heightUnitSymbol: String {
        MetricKind.height.unitSymbol(unitsSystem: unitsSystem)
    }
    
    var body: some View {
        Section {
            SettingsCard(tint: Color.white.opacity(0.08)) {
                SettingsCardHeader(title: AppLocalization.string("Profile"), systemImage: "person.crop.circle")

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "person.fill")
                        .frame(width: 60)
                    Text(AppLocalization.string("Name"))
                    Spacer()
                    TextField(AppLocalization.string("Add name"), text: $userName)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .foregroundStyle(userName.isEmpty ? .secondary : Color.appAccent)
                        .frame(minWidth: 120)
                }

                SettingsRowDivider()

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "figure.stand.dress.line.vertical.figure")
                        .frame(width: 60)
                    Text(AppLocalization.string("Gender"))
                    Spacer()
                    Menu {
                        Button(AppLocalization.string("Not specified")) { userGender = "notSpecified" }
                        Button(AppLocalization.string("Male")) { userGender = "male" }
                        Button(AppLocalization.string("Female")) { userGender = "female" }
                    } label: {
                        HStack(spacing: 6) {
                            Text(genderLabel)
                                .foregroundStyle(Color.appAccent)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                    .buttonStyle(.plain)
                }

                SettingsRowDivider()

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "calendar")
                        .frame(width: 60)
                    Text(AppLocalization.string("Age"))
                    Spacer()
                    TextField(AppLocalization.string("0"), text: $ageInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .foregroundStyle(ageInput.isEmpty ? .secondary : Color.appAccent)
                        .frame(minWidth: 48)
                    Text(AppLocalization.string("profile.unit.age"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: ageInput) { _, value in
                    let digits = value.filter(\.isNumber)
                    if digits != value {
                        ageInput = digits
                        return
                    }
                    userAge = Int(digits) ?? 0
                }
                .frame(minHeight: 44)

                SettingsRowDivider()

                HStack(spacing: 12) {
                    GlassPillIcon(systemName: "figure.stand")
                        .frame(width: 60)
                    Text(AppLocalization.string("Height"))
                    Spacer()
                    TextField(AppLocalization.string("0"), text: $heightInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(heightInput.isEmpty ? .secondary : Color.appAccent)
                        .frame(minWidth: 64)
                    Text(heightUnitSymbol)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: heightInput) { _, value in
                    let normalized = value.replacingOccurrences(of: ",", with: ".")
                    if normalized != value {
                        heightInput = normalized
                        return
                    }
                    guard let parsed = Double(normalized), parsed > 0 else {
                        manualHeight = 0
                        return
                    }
                    manualHeight = MetricKind.height.valueToMetric(fromDisplay: parsed, unitsSystem: unitsSystem)
                }
                .onChange(of: unitsSystem) { _, _ in
                    syncHeightInput()
                }
                .frame(minHeight: 44)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
        .onAppear {
            syncAgeInput()
            syncHeightInput()
        }
    }

    private func syncAgeInput() {
        ageInput = userAge > 0 ? "\(userAge)" : ""
    }

    private func syncHeightInput() {
        guard manualHeight > 0 else {
            heightInput = ""
            return
        }
        let displayValue = MetricKind.height.valueForDisplay(fromMetric: manualHeight, unitsSystem: unitsSystem)
        heightInput = unitsSystem == "imperial"
            ? String(format: "%.1f", displayValue)
            : String(format: "%.0f", displayValue)
    }
}

// MARK: - Profile Stats Card

struct ProfileStatsCard: View {
    @Query private var allSamples: [MetricSample]

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.08)) {
                SettingsCardHeader(
                    title: AppLocalization.string("Your Progress"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(allSamples.count)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.appAccent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel(AppLocalization.string("profile.stats.accessibility", allSamples.count))

                    Text(AppLocalization.string("total measurements"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsRowDivider()

                Text(motivationalPhrase)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private var motivationalPhrase: String {
        switch allSamples.count {
        case 0:
            return AppLocalization.string("profile.stats.phrase.0")
        case 1...10:
            return AppLocalization.string("profile.stats.phrase.1")
        case 11...50:
            return AppLocalization.string("profile.stats.phrase.2")
        case 51...100:
            return AppLocalization.string("profile.stats.phrase.3")
        case 101...250:
            return AppLocalization.string("profile.stats.phrase.4")
        case 251...500:
            return AppLocalization.string("profile.stats.phrase.5")
        case 501...1000:
            return AppLocalization.string("profile.stats.phrase.6")
        default:
            return AppLocalization.string("profile.stats.phrase.7")
        }
    }
}

struct HomeSettingsSection: View {
    @Binding var showMeasurementsOnHome: Bool
    @Binding var showLastPhotosOnHome: Bool
    @Binding var showHealthMetricsOnHome: Bool
    @Binding var showOnboardingChecklistOnHome: Bool
    @Binding var showStreakOnHome: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Home"), systemImage: "house.fill")
                Toggle(isOn: $showStreakOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "flame.fill")
                        Text(AppLocalization.string("Show streak on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showStreakOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showMeasurementsOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "chart.line.uptrend.xyaxis")
                        Text(AppLocalization.string("Show measurements on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showMeasurementsOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showLastPhotosOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "photo.on.rectangle")
                        Text(AppLocalization.string("Show photos on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showLastPhotosOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showHealthMetricsOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "heart.fill")
                        Text(AppLocalization.string("Show health summary on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showHealthMetricsOnHome) { _, _ in Haptics.selection() }
                SettingsRowDivider()
                Toggle(isOn: $showOnboardingChecklistOnHome) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "list.bullet.clipboard")
                        Text(AppLocalization.string("Show setup checklist on Home"))
                    }
                }
                .tint(Color.appAccent)
                .onChange(of: showOnboardingChecklistOnHome) { _, _ in Haptics.selection() }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }
}

struct IndicatorsSettingsSection: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showBodyShapeScoreOnHome: Bool
    @Binding var showCentralFatRiskOnHome: Bool
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    @State private var isHealthExpanded: Bool = false
    @State private var isPhysiqueExpanded: Bool = false

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Indicators"), systemImage: "slider.horizontal.3")

                disclosureRow(
                    title: AppLocalization.string("Health indicators"),
                    isExpanded: $isHealthExpanded
                ) {
                    healthIndicatorsContent
                }

                SettingsRowDivider()

                disclosureRow(
                    title: AppLocalization.string("Physique indicators"),
                    isExpanded: $isPhysiqueExpanded
                ) {
                    physiqueIndicatorsContent
                }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func disclosureRow<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.wrappedValue.toggle()
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .foregroundStyle(.white)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.top, 2)
            }
        }
    }

    private var healthIndicatorsContent: some View {
        Group {
            metricsGroupTitle("Core indicators")
            healthMetricToggle(AppLocalization.string("WHtR (Waist-to-Height Ratio)"), isOn: $showWHtROnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("RFM (Relative Fat Mass)"), isOn: $showRFMOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("BMI (Body Mass Index)"), isOn: $showBMIOnHome)

            metricsGroupTitle("Body composition")
            healthMetricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showBodyFatOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Lean Body Mass"), isOn: $showLeanMassOnHome)

            metricsGroupTitle("Fat distribution")
            healthMetricToggle(AppLocalization.string("Waist-to-Hip Ratio"), isOn: $showWHROnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Waist circumference"), isOn: $showWaistRiskOnHome)

            metricsGroupTitle("Risk signals")
            healthMetricToggle(AppLocalization.string("ABSI (technical)"), isOn: $showABSIOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Body Shape Risk"), isOn: $showBodyShapeScoreOnHome)
            rowDivider
            healthMetricToggle(AppLocalization.string("Central Fat Risk"), isOn: $showCentralFatRiskOnHome)
        }
    }

    private var physiqueIndicatorsContent: some View {
        Group {
            metricsGroupTitle("Proportion ratios")
            physiqueMetricToggle(AppLocalization.string("Shoulder-to-Waist Ratio"), isOn: $showPhysiqueSWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Chest-to-Waist Ratio"), isOn: $showPhysiqueCWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Hip-to-Waist Ratio"), isOn: $showPhysiqueHWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Bust-to-Waist Ratio"), isOn: $showPhysiqueBWR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Shoulder-to-Hip Ratio"), isOn: $showPhysiqueSHR)

            metricsGroupTitle("Hybrid metrics")
            physiqueMetricToggle(AppLocalization.string("Waist-Height Ratio"), isOn: $showPhysiqueWHtR)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showPhysiqueBodyFat)
            rowDivider
            physiqueMetricToggle(AppLocalization.string("Relative Fat Mass"), isOn: $showPhysiqueRFM)
        }
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthMetricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private func physiqueMetricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color(hex: "#14B8A6"))
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}

struct HealthIndicatorsSettingsSection: View {
    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showABSIOnHome: Bool
    @Binding var showBodyShapeScoreOnHome: Bool
    @Binding var showCentralFatRiskOnHome: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                SettingsCardHeader(title: AppLocalization.string("Health indicators"), systemImage: "heart.text.square.fill")
                VStack(spacing: 0) {
                    metricsGroupTitle("Core indicators")
                    metricToggle(AppLocalization.string("WHtR (Waist-to-Height Ratio)"), isOn: $showWHtROnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("RFM (Relative Fat Mass)"), isOn: $showRFMOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("BMI (Body Mass Index)"), isOn: $showBMIOnHome)

                    metricsGroupTitle("Body composition")
                    metricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showBodyFatOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Lean Body Mass"), isOn: $showLeanMassOnHome)

                    metricsGroupTitle("Fat distribution")
                    metricToggle(AppLocalization.string("Waist-to-Hip Ratio"), isOn: $showWHROnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Waist circumference"), isOn: $showWaistRiskOnHome)

                    metricsGroupTitle("Risk signals")
                    metricToggle(AppLocalization.string("ABSI (technical)"), isOn: $showABSIOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Body Shape Risk"), isOn: $showBodyShapeScoreOnHome)
                    rowDivider
                    metricToggle(AppLocalization.string("Central Fat Risk"), isOn: $showCentralFatRiskOnHome)
                }
                .padding(.top, 6)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color.appAccent)
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}

struct PhysiqueIndicatorsSettingsSection: View {
    @Binding var showPhysiqueSWR: Bool
    @Binding var showPhysiqueCWR: Bool
    @Binding var showPhysiqueSHR: Bool
    @Binding var showPhysiqueHWR: Bool
    @Binding var showPhysiqueBWR: Bool
    @Binding var showPhysiqueWHtR: Bool
    @Binding var showPhysiqueBodyFat: Bool
    @Binding var showPhysiqueRFM: Bool

    var body: some View {
        Section {
            SettingsCard(tint: Color(hex: "#14B8A6").opacity(0.16)) {
                SettingsCardHeader(title: AppLocalization.string("Physique indicators"), systemImage: "figure.strengthtraining.traditional")
                VStack(spacing: 0) {
                    metricsGroupTitle("Proportion ratios")
                    metricToggle(AppLocalization.string("Shoulder-to-Waist Ratio"), isOn: $showPhysiqueSWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Chest-to-Waist Ratio"), isOn: $showPhysiqueCWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Hip-to-Waist Ratio"), isOn: $showPhysiqueHWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Bust-to-Waist Ratio"), isOn: $showPhysiqueBWR)
                    rowDivider
                    metricToggle(AppLocalization.string("Shoulder-to-Hip Ratio"), isOn: $showPhysiqueSHR)

                    metricsGroupTitle("Hybrid metrics")
                    metricToggle(AppLocalization.string("Waist-Height Ratio"), isOn: $showPhysiqueWHtR)
                    rowDivider
                    metricToggle(AppLocalization.string("Body Fat Percentage"), isOn: $showPhysiqueBodyFat)
                    rowDivider
                    metricToggle(AppLocalization.string("Relative Fat Mass"), isOn: $showPhysiqueRFM)
                }
                .padding(.top, 6)
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowInsets(settingsComponentsRowInsets)
        .listRowBackground(Color.clear)
    }

    private func metricsGroupTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
        }
        .tint(Color(hex: "#14B8A6"))
        .onChange(of: isOn.wrappedValue) { _, _ in Haptics.selection() }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.vertical, 4)
    }
}

struct SettingsCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            content
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: AppRadius.md,
                tint: tint
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

struct SettingsCardHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#FCA311"))
            }
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
        }
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.24))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct SettingsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
