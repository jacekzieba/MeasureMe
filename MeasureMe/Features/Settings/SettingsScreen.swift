import SwiftUI
import SwiftData
import HealthKit
import UIKit

/// **SettingsView**
/// Widok ustawień aplikacji. Odpowiada za:
/// - Włączanie/wyłączanie synchronizacji z HealthKit
/// - Wybór systemu jednostek (metryczny/imperialny)
/// - Nawigację do zarządzania śledzonymi metrykami
/// - Sekcję informacyjną "About"
///
/// **Optymalizacje wydajności:**
/// - Autoryzacja HealthKit uruchamiana asynchronicznie z opóźnieniem
/// - Task anulowany przy znikaniu widoku, aby uniknąć memory leaks
/// - Brak blokowania głównego wątku podczas żądania uprawnień
struct SettingsView: View {
    // MARK: - Constants
    private static let settingsRowInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var premiumStore: PremiumStore
    @AppSetting("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppSetting("unitsSystem") private var unitsSystem: String = "metric"
    @AppSetting("showLastPhotosOnHome") private var showLastPhotosOnHome: Bool = true
    @AppSetting("showMeasurementsOnHome") private var showMeasurementsOnHome: Bool = true
    @AppSetting("showHealthMetricsOnHome") private var showHealthMetricsOnHome: Bool = true
    @AppSetting("showStreakOnHome") private var showStreakOnHome: Bool = true
    @AppSetting("onboarding_checklist_show") private var showOnboardingChecklistOnHome: Bool = true
    @AppSetting("settings_open_tracked_measurements") private var settingsOpenTrackedMeasurements: Bool = false
    @AppSetting("settings_open_reminders") private var settingsOpenReminders: Bool = false
    @AppSetting("animationsEnabled") private var animationsEnabled: Bool = true
    @AppSetting("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppSetting("userName") private var userName: String = ""
    @AppSetting("appLanguage") private var appLanguage: String = "system"
    
    // Core Metrics visibility
    @AppSetting("showWHtROnHome") private var showWHtROnHome: Bool = true
    @AppSetting("showRFMOnHome") private var showRFMOnHome: Bool = true
    @AppSetting("showBMIOnHome") private var showBMIOnHome: Bool = true
    
    // Body Composition visibility
    @AppSetting("showBodyFatOnHome") private var showBodyFatOnHome: Bool = true
    @AppSetting("showLeanMassOnHome") private var showLeanMassOnHome: Bool = true
    
    // Risk Indicators visibility
    @AppSetting("showWHROnHome") private var showWHROnHome: Bool = true
    @AppSetting("showWaistRiskOnHome") private var showWaistRiskOnHome: Bool = true
    @AppSetting("showABSIOnHome") private var showABSIOnHome: Bool = true
    @AppSetting("showBodyShapeScoreOnHome") private var showBodyShapeScoreOnHome: Bool = true
    @AppSetting("showCentralFatRiskOnHome") private var showCentralFatRiskOnHome: Bool = true

    // Physique indicators visibility
    @AppSetting("showPhysiqueSWR") private var showPhysiqueSWR: Bool = true
    @AppSetting("showPhysiqueCWR") private var showPhysiqueCWR: Bool = true
    @AppSetting("showPhysiqueSHR") private var showPhysiqueSHR: Bool = true
    @AppSetting("showPhysiqueHWR") private var showPhysiqueHWR: Bool = true
    @AppSetting("showPhysiqueBWR") private var showPhysiqueBWR: Bool = true
    @AppSetting("showPhysiqueWHtR") private var showPhysiqueWHtR: Bool = true
    @AppSetting("showPhysiqueBodyFat") private var showPhysiqueBodyFat: Bool = true
    @AppSetting("showPhysiqueRFM") private var showPhysiqueRFM: Bool = true
    
    @AppSetting("userGender") private var userGender: String = "notSpecified"
    @AppSetting("manualHeight") private var manualHeight: Double = 0.0
    @AppSetting("userAge") private var userAge: Int = 0
    @AppSetting("healthkit_last_import") private var lastHealthImportTimestamp: Double = 0.0
    @AppSetting("apple_intelligence_enabled") private var appleIntelligenceEnabled: Bool = true
    
    @AppSetting("healthkit_sync_weight") private var hkWeight: Bool = true
    @AppSetting("healthkit_sync_bodyFat") private var hkBodyFat: Bool = true
    @AppSetting("healthkit_sync_height") private var hkHeight: Bool = true
    @AppSetting("healthkit_sync_leanBodyMass") private var hkLeanMass: Bool = true
    @AppSetting("healthkit_sync_waist") private var hkWaist: Bool = true

    @State private var scrollOffset: CGFloat = 0
    @State private var shareItems: [Any] = []
    @State private var shareSubject: String? = nil
    @State private var isPresentingShareSheet = false
    @State private var isExporting = false
    @State private var exportMessage: String = ""
    @State private var showDeleteAllDataConfirm = false
    @State private var showDeleteAllDataResult = false
    @State private var deleteAllDataResultMessage = ""
    @State private var showImportPicker = false
    @State private var showImportStrategyAlert = false
    @State private var pendingImportURLs: [URL] = []
    @State private var isImporting = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    @State private var showSeedDummyDataConfirm = false
    @State private var showSeedDummyDataResult = false
    @State private var seedDummyDataResultMessage = ""
    @State private var navigateToTrackedMeasurements: Bool = false
    @State private var navigateToReminders: Bool = false
    @State private var settingsSearchQuery: String = ""
    
    private var lastImportText: String? {
        guard lastHealthImportTimestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: lastHealthImportTimestamp)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var isSearchingSettings: Bool {
        !settingsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var settingsSearchItems: [SettingsSearchItem] {
        SettingsSearchCatalog.items
    }

    private var filteredSettingsSearchItems: [SettingsSearchItem] {
        let query = settingsSearchQuery
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return settingsSearchItems }
        return settingsSearchItems.filter { item in
            if item.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(query) {
                return true
            }
            if item.subtitle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(query) {
                return true
            }
            return item.keywords.contains {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(query)
            }
        }
    }

    @ViewBuilder private var settingsSections: some View {

                if !premiumStore.isPremium {
                    Section {
                        SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                            HStack(spacing: 10) {
                                Image("BrandButton")
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .accessibilityHidden(true)

                                Text(AppLocalization.string("Unlock all features"))
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                // Utrzymuje optyczne wycentrowanie tytulu, gdy logo zostaje po lewej.
                                Color.clear
                                    .frame(width: 44, height: 44)
                            }

                            Button {
                                premiumStore.presentPaywall(reason: .settings)
                            } label: {
                                Text(AppLocalization.string("What is in The Premium Edition?"))
                            }
                            .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                            .accessibilityHint(AppLocalization.string("View Premium options"))
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(Self.settingsRowInsets)
                }

                SettingsAISection(
                    isPremium: premiumStore.isPremium,
                    isAppleIntelligenceAvailable: AppleIntelligenceSupport.isAvailable(),
                    appleIntelligenceEnabled: $appleIntelligenceEnabled,
                    onUnlock: {
                        premiumStore.presentPaywall(reason: .feature("AI Insights"))
                    }
                )
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.08)) {
                        SettingsCardHeader(title: AppLocalization.string("Profile"), systemImage: "person.crop.circle")
                        NavigationLink {
                            ProfileSettingsDetailView(
                                userName: $userName,
                                userGender: $userGender,
                                userAge: $userAge,
                                manualHeight: $manualHeight,
                                unitsSystem: $unitsSystem
                            )
                        } label: {
                            Text(AppLocalization.string("Open profile settings"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Metrics"), systemImage: "list.bullet.clipboard")
                        NavigationLink {
                            TrackedMeasurementsView()
                        } label: {
                            Text(AppLocalization.string("Tracked measurements"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Indicators"), systemImage: "slider.horizontal.3")
                        NavigationLink {
                            IndicatorsSettingsDetailView(
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
                        } label: {
                            Text(AppLocalization.string("Choose health and physique indicators"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                HealthSettingsSection(
                    isSyncEnabled: $isSyncEnabled,
                    lastImportText: lastImportText,
                    hkWeight: $hkWeight,
                    hkBodyFat: $hkBodyFat,
                    hkHeight: $hkHeight,
                    hkLeanMass: $hkLeanMass,
                    hkWaist: $hkWaist
                )
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("Notifications"), systemImage: "bell.badge")
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Text(AppLocalization.string("Manage reminders"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Home"), systemImage: "house.fill")
                        NavigationLink {
                            HomeSettingsDetailView(
                                showMeasurementsOnHome: $showMeasurementsOnHome,
                                showLastPhotosOnHome: $showLastPhotosOnHome,
                                showHealthMetricsOnHome: $showHealthMetricsOnHome,
                                showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome,
                                showStreakOnHome: $showStreakOnHome
                            )
                        } label: {
                            Text(AppLocalization.string("Open Home settings"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                UnitsSettingsSection(unitsSystem: $unitsSystem)
                    .listRowBackground(Color.clear)
                    .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.08)) {
                        SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "apple.haptics.and.music.note")
                        NavigationLink {
                            ExperienceSettingsDetailView(
                                animationsEnabled: $animationsEnabled,
                                hapticsEnabled: $hapticsEnabled
                            )
                        } label: {
                            Text(AppLocalization.string("Open animation and haptics settings"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("Language"), systemImage: "globe")
                        NavigationLink {
                            LanguageSettingsDetailView(
                                appLanguage: $appLanguage
                            )
                        } label: {
                            Text(AppLocalization.string("App language"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                SettingsDataSection(
                    onExport: {
                        Haptics.light()
                        SettingsDataActions.runPremiumAction(
                            isPremium: premiumStore.isPremium,
                            feature: "Data export",
                            onAllowed: { exportMetricsCSV() },
                            onLocked: { premiumStore.presentPaywall(reason: .feature($0)) }
                        )
                    },
                    onImport: {
                        Haptics.light()
                        SettingsDataActions.runPremiumAction(
                            isPremium: premiumStore.isPremium,
                            feature: "Data import",
                            onAllowed: { showImportPicker = true },
                            onLocked: { premiumStore.presentPaywall(reason: .feature($0)) }
                        )
                    },
                    onSeedDummyData: {
                        Haptics.light()
                        showSeedDummyDataConfirm = true
                    },
                    onDeleteAll: {
                        Haptics.light()
                        showDeleteAllDataConfirm = true
                    }
                )
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("FAQ"), systemImage: "questionmark.circle")
                        NavigationLink {
                            FAQView()
                        } label: {
                            Text(AppLocalization.string("Read frequently asked questions"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("App"), systemImage: "iphone.gen3.sizes")

                        if premiumStore.isPremium {
                            NavigationLink {
                                PremiumBenefitsInfoView()
                            } label: {
                                appSectionRowLabel(
                                    title: AppLocalization.string("settings.app.subscription.active"),
                                    subtitle: AppLocalization.string("settings.app.subscription.view.benefits"),
                                    trailingSymbol: nil
                                )
                            }
                            .buttonStyle(.plain)

                            SettingsRowDivider()
                        }

                        Button {
                            Task { await premiumStore.restorePurchases() }
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("Restore purchases"),
                                trailingSymbol: "arrow.clockwise.circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.termsOfUse)
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("Terms of Use"),
                                trailingSymbol: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.privacyPolicy)
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("Privacy Policy"),
                                trailingSymbol: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.accessibility)
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("Accessibility"),
                                trailingSymbol: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)

                Section {
                    SettingsCard(tint: Color.white.opacity(0.07)) {
                        SettingsCardHeader(title: AppLocalization.string("About"), systemImage: "info.circle")
                        NavigationLink {
                            AboutSettingsDetailView(
                                onReportBug: {
                                    Haptics.light()
                                    exportDiagnosticsJSON()
                                }
                            )
                        } label: {
                            Text(AppLocalization.string("About MeasureMe"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(Self.settingsRowInsets)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(
                    topHeight: 380,
                    scrollOffset: scrollOffset,
                    tint: Color.cyan.opacity(0.22)
                )
                .ignoresSafeArea(edges: .top)
                
                // Zawartość
                List {
                ScreenTitleHeader(title: AppLocalization.string("Settings"), topPadding: 0, bottomPadding: 4)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if isSearchingSettings {
                    Section {
                        if filteredSettingsSearchItems.isEmpty {
                            Text(AppLocalization.string("No matching settings"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                        } else {
                            ForEach(filteredSettingsSearchItems) { item in
                                NavigationLink {
                                    settingsSearchDestination(for: item.route)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(AppTypography.bodyEmphasis)
                                            .foregroundStyle(.white)
                                        Text(item.subtitle)
                                            .font(AppTypography.caption)
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .appHitTarget()
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(Self.settingsRowInsets)
                } else {
                    settingsSections
                }
            }
            .tint(Color.appAccent)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SettingsScrollOffsetKey.self,
                        value: proxy.frame(in: .named("settingsScroll")).minY
                    )
                }
                .allowsHitTesting(false)
            }
            .coordinateSpace(name: "settingsScroll")
            .onPreferenceChange(SettingsScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .scrollContentBackground(.hidden) // Ukryj domyślne tło List
            .onAppear {
                schedulePendingDeepLinksHandling()
            }
            .onChange(of: settingsOpenTrackedMeasurements) { _, _ in
                schedulePendingDeepLinksHandling()
            }
            .onChange(of: settingsOpenReminders) { _, _ in
                schedulePendingDeepLinksHandling()
            }
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowSeparatorTint(.clear)
            .listSectionSeparatorTint(.clear)
            .applyNoScrollContentInsetsIfAvailable()
            .searchable(
                text: $settingsSearchQuery,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: AppLocalization.string("Search Settings")
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(scrollOffset < -16 ? .visible : .hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingShareSheet) {
                ShareSheet(items: shareItems, subject: shareSubject)
            }
            .alert(AppLocalization.string("Delete all data"), isPresented: $showDeleteAllDataConfirm) {
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Delete all data"), role: .destructive) {
                    deleteAllUserData()
                }
            } message: {
                Text(AppLocalization.string("This removes all measurements, goals, photos, reminders, and imported HealthKit data stored in MeasureMe on this device. Apple Health records are not deleted and can be re-imported if sync is enabled again."))
            }
            .alert(AppLocalization.string("Delete all data"), isPresented: $showDeleteAllDataResult) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(deleteAllDataResultMessage)
            }
            .alert(AppLocalization.string("Seed dummy data"), isPresented: $showSeedDummyDataConfirm) {
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Seed dummy data")) {
                    seedDummyData()
                }
            } message: {
                Text(AppLocalization.string("This will add realistic sample measurements for recent weeks. Existing data will remain unchanged."))
            }
            .alert(AppLocalization.string("Seed dummy data"), isPresented: $showSeedDummyDataResult) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(seedDummyDataResultMessage)
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    pendingImportURLs = urls
                    showImportStrategyAlert = true
                case .failure(let error):
                    importResultMessage = AppLocalization.string("Could not open file: ") + error.localizedDescription
                    showImportResult = true
                }
            }
            .confirmationDialog(
                AppLocalization.string("Import data"),
                isPresented: $showImportStrategyAlert,
                titleVisibility: .visible
            ) {
                Button(AppLocalization.string("Merge (keep existing data)")) {
                    performImport(urls: pendingImportURLs, strategy: .merge)
                }
                Button(AppLocalization.string("Replace (delete existing data)"), role: .destructive) {
                    performImport(urls: pendingImportURLs, strategy: .replace)
                }
                Button(AppLocalization.string("Cancel"), role: .cancel) {
                    pendingImportURLs = []
                }
            } message: {
                Text(AppLocalization.string("How should MeasureMe handle existing data?"))
            }
            .alert(AppLocalization.string("Import complete"), isPresented: $showImportResult) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(importResultMessage)
            }
            if isExporting {
                exportOverlay
            }
            }
            .navigationDestination(isPresented: $navigateToTrackedMeasurements) {
                TrackedMeasurementsView()
            }
            .navigationDestination(isPresented: $navigateToReminders) {
                NotificationSettingsView()
            }
        }
    }

    // MARK: - Exports

    @ViewBuilder
    private func appSectionRowLabel(
        title: String,
        subtitle: String? = nil,
        trailingSymbol: String? = nil,
        trailingColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.66))
                }
            }

            Spacer(minLength: 8)

            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trailingColor)
                    .frame(width: 18, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func exportMetricsCSV() {
        exportMessage = AppLocalization.string("Preparing data export...")
        isExporting = true
        Task {
            let out = await SettingsExporter.exportMetrics(context: modelContext, unitsSystem: unitsSystem)
            shareItems = out.items
            shareSubject = out.subject
            isExporting = false
            isPresentingShareSheet = !out.items.isEmpty
        }
    }

    private func exportDiagnosticsJSON() {
        exportMessage = AppLocalization.string("Generating diagnostics...")
        isExporting = true
        Task {
            let out = await SettingsExporter.exportDiagnostics(
                context: modelContext,
                isSyncEnabled: isSyncEnabled,
                lastHealthImportTimestamp: lastHealthImportTimestamp
            )
            shareItems = out.items
            shareSubject = out.subject
            isExporting = false
            isPresentingShareSheet = !out.items.isEmpty
        }
    }

    private func handlePendingDeepLinks() {
        if settingsOpenTrackedMeasurements {
            settingsOpenTrackedMeasurements = false
            navigateToTrackedMeasurements = true
        }

        if settingsOpenReminders {
            settingsOpenReminders = false
            navigateToReminders = true
        }
    }

    private func schedulePendingDeepLinksHandling() {
        DispatchQueue.main.async {
            handlePendingDeepLinks()
        }
    }

    private func deleteAllUserData() {
        Task { @MainActor in
            await performDeleteAllUserData()
        }
    }

    private func seedDummyData() {
        Task { @MainActor in
            await performSeedDummyData()
        }
    }

    @MainActor
    private func performDeleteAllUserData() async {
        do {
            HealthKitManager.shared.stopObservingHealthKitUpdates()
            isSyncEnabled = false

            try deleteAllEntities(of: MetricSample.self)
            try deleteAllEntities(of: MetricGoal.self)
            try deleteAllEntities(of: PhotoEntry.self)
            try modelContext.save()

            await NotificationManager.shared.resetAllData()

            clearHealthKitSyncMetadata()
            clearUserDataDefaults()

            ImageCache.shared.removeAll()
            try await DiskImageCache.shared.removeAll()

            deleteAllDataResultMessage = AppLocalization.string("All local app data has been deleted.")
            showDeleteAllDataResult = true
            Haptics.success()
        } catch {
            AppLog.debug("⚠️ Failed to delete all app data: \(error)")
            deleteAllDataResultMessage = AppLocalization.string("Could not delete all data. Please try again.")
            showDeleteAllDataResult = true
            Haptics.error()
        }
    }

    @MainActor
    private func performSeedDummyData() async {
        do {
            let existing = (try? modelContext.fetch(FetchDescriptor<MetricSample>())) ?? []
            var existingKeys = Set<String>()
            for sample in existing {
                existingKeys.insert(metricSampleSeedKey(kindRaw: sample.kindRaw, date: sample.date))
            }

            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: AppClock.now)
            let dayOffsets = stride(from: 56, through: 0, by: -4).map { $0 }
            var inserted = 0

            for (step, offset) in dayOffsets.enumerated() {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday),
                      let timestamp = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else {
                    continue
                }

                for kind in MetricKind.allCases {
                    guard let value = seededMetricValue(for: kind, step: step) else { continue }
                    let key = metricSampleSeedKey(kindRaw: kind.rawValue, date: timestamp)
                    guard !existingKeys.contains(key) else { continue }
                    modelContext.insert(MetricSample(kind: kind, value: value, date: timestamp))
                    existingKeys.insert(key)
                    inserted += 1
                }
            }

            try modelContext.save()

            if userGender == "notSpecified" {
                userGender = "male"
            }
            if userAge <= 0 {
                userAge = 29
            }
            if manualHeight <= 0 {
                manualHeight = 180
            }

            seedDummyDataResultMessage = String(
                format: AppLocalization.string("Dummy data added: %d measurements."),
                inserted
            )
            showSeedDummyDataResult = true
            Haptics.success()
        } catch {
            AppLog.debug("⚠️ Failed to seed dummy data: \(error)")
            seedDummyDataResultMessage = AppLocalization.string("Could not seed dummy data. Please try again.")
            showSeedDummyDataResult = true
            Haptics.error()
        }
    }

    private func seededMetricValue(for kind: MetricKind, step: Int) -> Double? {
        let s = Double(step)
        switch kind {
        case .weight:
            return 92.0 - (0.35 * s)
        case .bodyFat:
            return 27.0 - (0.28 * s)
        case .height:
            return 180.0
        case .leanBodyMass:
            return 66.0 + (0.08 * s)
        case .waist:
            return 101.0 - (0.45 * s)
        case .neck:
            return 40.0 - (0.03 * s)
        case .shoulders:
            return 118.0 + (0.12 * s)
        case .bust:
            return 96.0 + (0.05 * s)
        case .chest:
            return 103.0 + (0.11 * s)
        case .leftBicep:
            return 33.0 + (0.10 * s)
        case .rightBicep:
            return 33.2 + (0.10 * s)
        case .leftForearm:
            return 28.0 + (0.05 * s)
        case .rightForearm:
            return 28.1 + (0.05 * s)
        case .hips:
            return 106.0 - (0.20 * s)
        case .leftThigh:
            return 60.0 - (0.07 * s)
        case .rightThigh:
            return 60.3 - (0.07 * s)
        case .leftCalf:
            return 38.0 + (0.03 * s)
        case .rightCalf:
            return 38.2 + (0.03 * s)
        }
    }

    private func metricSampleSeedKey(kindRaw: String, date: Date) -> String {
        "\(kindRaw)_\(Int(date.timeIntervalSince1970))"
    }

    private func deleteAllEntities<T: PersistentModel>(of type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let objects = try modelContext.fetch(descriptor)
        for object in objects {
            modelContext.delete(object)
        }
    }

    private func clearHealthKitSyncMetadata() {
        let defaults = AppSettingsStore.shared
        defaults.set(false, forKey: "isSyncEnabled")
        defaults.removeObject(forKey: "healthkit_last_import")
        defaults.removeObject(forKey: "healthkit_initial_historical_import_v1")

        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("healthkit_anchor_") || key.hasPrefix("healthkit_last_processed_") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func clearUserDataDefaults() {
        let defaults = AppSettingsStore.shared
        defaults.removeObject(forKey: "userName")
        defaults.removeObject(forKey: "userAge")
        defaults.removeObject(forKey: "userGender")
        defaults.removeObject(forKey: "manualHeight")
        defaults.removeObject(forKey: "measurement_reminders")
        defaults.removeObject(forKey: "measurement_last_log_date")
        defaults.removeObject(forKey: "photo_last_log_date")
        defaults.removeObject(forKey: "diagnostics_logging_enabled")
    }

    @ViewBuilder
    private func settingsSearchDestination(for route: SettingsSearchRoute) -> some View {
        switch route {
        case .profile:
            ProfileSettingsDetailView(
                userName: $userName,
                userGender: $userGender,
                userAge: $userAge,
                manualHeight: $manualHeight,
                unitsSystem: $unitsSystem
            )
        case .metrics:
            TrackedMeasurementsView()
        case .indicators:
            IndicatorsSettingsDetailView(
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
        case .physiqueIndicators:
            PhysiqueIndicatorsSettingsDetailView(
                showPhysiqueSWR: $showPhysiqueSWR,
                showPhysiqueCWR: $showPhysiqueCWR,
                showPhysiqueSHR: $showPhysiqueSHR,
                showPhysiqueHWR: $showPhysiqueHWR,
                showPhysiqueBWR: $showPhysiqueBWR,
                showPhysiqueWHtR: $showPhysiqueWHtR,
                showPhysiqueBodyFat: $showPhysiqueBodyFat,
                showPhysiqueRFM: $showPhysiqueRFM
            )
        case .health:
            HealthSettingsDetailView(
                isSyncEnabled: $isSyncEnabled,
                lastImportText: lastImportText,
                hkWeight: $hkWeight,
                hkBodyFat: $hkBodyFat,
                hkHeight: $hkHeight,
                hkLeanMass: $hkLeanMass,
                hkWaist: $hkWaist
            )
        case .notifications:
            NotificationSettingsView()
        case .home:
            HomeSettingsDetailView(
                showMeasurementsOnHome: $showMeasurementsOnHome,
                showLastPhotosOnHome: $showLastPhotosOnHome,
                showHealthMetricsOnHome: $showHealthMetricsOnHome,
                showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome,
                showStreakOnHome: $showStreakOnHome
            )
        case .aiInsights:
            AIInsightsSettingsDetailView(appleIntelligenceEnabled: $appleIntelligenceEnabled)
        case .units:
            UnitsSettingsDetailView(unitsSystem: $unitsSystem)
        case .experience:
            ExperienceSettingsDetailView(
                animationsEnabled: $animationsEnabled,
                hapticsEnabled: $hapticsEnabled
            )
        case .language:
            LanguageSettingsDetailView(appLanguage: $appLanguage)
        case .data:
            DataSettingsDetailView(
                onExport: {
                    Haptics.light()
                    if premiumStore.isPremium {
                        exportMetricsCSV()
                    } else {
                        premiumStore.presentPaywall(reason: .feature("Data export"))
                    }
                },
                onImport: {
                    Haptics.light()
                    if premiumStore.isPremium {
                        showImportPicker = true
                    } else {
                        premiumStore.presentPaywall(reason: .feature("Data import"))
                    }
                },
                onSeedDummyData: {
                    Haptics.light()
                    showSeedDummyDataConfirm = true
                },
                onDeleteAll: {
                    Haptics.light()
                    showDeleteAllDataConfirm = true
                }
            )
        case .faq:
            FAQView()
        case .about:
            AboutSettingsDetailView(
                onReportBug: {
                    Haptics.light()
                    exportDiagnosticsJSON()
                }
            )
        }
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.appAccent)
                Text(exportMessage)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Import logic

    private func performImport(urls: [URL], strategy: SettingsImporter.Strategy) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            let msg = await SettingsImporter.importData(urls: urls, strategy: strategy, context: modelContext)
            importResultMessage = msg
            isImporting = false
            pendingImportURLs = []
            showImportResult = true
            Haptics.success()
        }
    }
}
