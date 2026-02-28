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
                    Group {

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

                SettingsHealthSection(
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
                handlePendingDeepLinks()
            }
            .onChange(of: settingsOpenTrackedMeasurements) { _, _ in
                handlePendingDeepLinks()
            }
            .onChange(of: settingsOpenReminders) { _, _ in
                handlePendingDeepLinks()
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

    private struct MetricSampleSnapshot: Sendable {
        let kindRaw: String
        let value: Double
        let date: Date
    }

    private struct MetricCSVRowSnapshot: Sendable {
        let kindRaw: String           // MetricKind.rawValue — klucz do importu
        let metricTitle: String       // englishTitle — czytelna etykieta (zawsze EN)
        let metricValue: Double       // wartość w jednostkach bazowych (kg/cm/%)
        let metricUnit: String        // jednostka bazowa (kg/cm/%)
        let displayValue: Double      // wartość w jednostkach display
        let unit: String              // jednostka display
        let date: Date
    }

    private struct MetricGoalSnapshot: Sendable {
        let kindRaw: String
        let metricTitle: String       // englishTitle
        let direction: String         // "increase" lub "decrease"
        let targetMetricValue: Double // wartość celu w jednostkach bazowych
        let targetMetricUnit: String  // jednostka bazowa celu
        let targetDisplayValue: Double
        let targetDisplayUnit: String
        let startMetricValue: Double? // opcjonalny punkt startowy (bazowy)
        let startDisplayValue: Double?
        let startDate: Date?
        let createdDate: Date
    }

    private struct DeviceSnapshot: Sendable {
        let systemName: String
        let systemVersion: String
        let model: String
    }

    private func exportMetricsCSV() {
        let samplesSnapshot = fetchAllMetricSamplesSorted()
        let goalsSnapshot = fetchAllGoals()
        let currentUnitsSystem = unitsSystem
        let csvRows: [MetricCSVRowSnapshot] = samplesSnapshot.compactMap { sample in
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { return nil }
            let metricUnit: String
            switch kind.unitCategory {
            case .weight: metricUnit = "kg"
            case .length: metricUnit = "cm"
            case .percent: metricUnit = "%"
            }
            return MetricCSVRowSnapshot(
                kindRaw: sample.kindRaw,
                metricTitle: kind.englishTitle,
                metricValue: sample.value,
                metricUnit: metricUnit,
                displayValue: kind.valueForDisplay(fromMetric: sample.value, unitsSystem: currentUnitsSystem),
                unit: kind.unitSymbol(unitsSystem: currentUnitsSystem),
                date: sample.date
            )
        }
        let goalRows: [MetricGoalSnapshot] = goalsSnapshot.compactMap { goal in
            guard let kind = MetricKind(rawValue: goal.kindRaw) else { return nil }
            let metricUnit: String
            switch kind.unitCategory {
            case .weight: metricUnit = "kg"
            case .length: metricUnit = "cm"
            case .percent: metricUnit = "%"
            }
            let startDisplay = goal.startMetricValue.map {
                kind.valueForDisplay(fromMetric: $0, unitsSystem: currentUnitsSystem)
            }
            return MetricGoalSnapshot(
                kindRaw: goal.kindRaw,
                metricTitle: kind.englishTitle,
                direction: goal.directionRaw,
                targetMetricValue: goal.targetValue,
                targetMetricUnit: metricUnit,
                targetDisplayValue: kind.valueForDisplay(fromMetric: goal.targetValue, unitsSystem: currentUnitsSystem),
                targetDisplayUnit: kind.unitSymbol(unitsSystem: currentUnitsSystem),
                startMetricValue: goal.startMetricValue,
                startDisplayValue: startDisplay,
                startDate: goal.startDate,
                createdDate: goal.createdDate
            )
        }
        exportMessage = AppLocalization.string("Preparing data export...")
        isExporting = true
        let ts = timestampString()
        Task {
            let (metricsCSV, goalsCSV) = await Task.detached(priority: .userInitiated) {
                (SettingsView.buildMetricsCSV(from: csvRows),
                 SettingsView.buildGoalsCSV(from: goalRows))
            }.value
            let metricsURL = writeTempFile(named: "measureme-metrics-\(ts).csv", contents: metricsCSV)
            let goalsURL = writeTempFile(named: "measureme-goals-\(ts).csv", contents: goalsCSV)
            await MainActor.run {
                isExporting = false
                var items: [Any] = []
                if let u = metricsURL { items.append(u) }
                if let u = goalsURL { items.append(u) }
                guard !items.isEmpty else { return }
                shareItems = items
                shareSubject = AppLocalization.string("MeasureMe data export")
                isPresentingShareSheet = true
            }
        }
    }

    private func exportDiagnosticsJSON() {
        let sampleSnapshot = fetchAllMetricSamplesSorted()
        let photoCount = fetchPhotosCount()
        let syncEnabled = isSyncEnabled
        let lastImport = lastHealthImportTimestamp
        let deviceSnapshot = DeviceSnapshot(
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            model: UIDevice.current.model
        )
        exportMessage = AppLocalization.string("Generating diagnostics...")
        isExporting = true
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                SettingsView.buildDiagnosticsJSON(
                    samples: sampleSnapshot,
                    photosCount: photoCount,
                    isSyncEnabled: syncEnabled,
                    lastHealthImportTimestamp: lastImport,
                    device: deviceSnapshot
                )
            }.value
            let fileName = "measureme-diagnostics-\(timestampString()).json"
            let url = data.flatMap { writeTempFile(named: fileName, data: $0) }
            await MainActor.run {
                isExporting = false
                guard let url else { return }
                shareItems = [
                    url,
                    AppLocalization.string("Send diagnostics to ziebajacek@pm.me")
                ]
                shareSubject = AppLocalization.string("MeasureMe diagnostics")
                isPresentingShareSheet = true
            }
        }
    }

    private func fetchAllMetricSamplesSorted() -> [MetricSampleSnapshot] {
        let descriptor = FetchDescriptor<MetricSample>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let samples = (try? modelContext.fetch(descriptor)) ?? []
        return samples.map {
            MetricSampleSnapshot(kindRaw: $0.kindRaw, value: $0.value, date: $0.date)
        }
    }

    private struct GoalFetchSnapshot: Sendable {
        let kindRaw: String
        let directionRaw: String
        let targetValue: Double
        let startMetricValue: Double?
        let startDate: Date?
        let createdDate: Date
    }

    private func fetchAllGoals() -> [GoalFetchSnapshot] {
        let descriptor = FetchDescriptor<MetricGoal>(
            sortBy: [SortDescriptor(\.kindRaw, order: .forward)]
        )
        let goals = (try? modelContext.fetch(descriptor)) ?? []
        return goals.map {
            GoalFetchSnapshot(
                kindRaw: $0.kindRaw,
                directionRaw: $0.directionRaw,
                targetValue: $0.targetValue,
                startMetricValue: $0.startValue,
                startDate: $0.startDate,
                createdDate: $0.createdDate
            )
        }
    }

    private func fetchPhotosCount() -> Int {
        let descriptor = FetchDescriptor<PhotoEntry>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
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

    private nonisolated static func buildMetricsCSV(from rows: [MetricCSVRowSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // metric_id — stały klucz do importu (MetricKind.rawValue, language-agnostic)
        // value_metric / unit_metric — wartości bazowe (kg/cm/%) — determinizm przy imporcie
        // value / unit — wartości display (lb/in gdy imperial) — wygoda w Excelu
        var lines: [String] = ["metric_id,metric,value_metric,unit_metric,value,unit,timestamp"]
        for row in rows {
            let metricValueStr = String(format: "%.4f", row.metricValue)
            let displayValueStr = String(format: "%.2f", row.displayValue)
            let dateString = formatter.string(from: row.date)
            lines.append([
                csvField(row.kindRaw),
                csvField(row.metricTitle),
                metricValueStr,
                csvField(row.metricUnit),
                displayValueStr,
                csvField(row.unit),
                dateString
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func buildGoalsCSV(from rows: [MetricGoalSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = [
            "metric_id,metric,direction,target_value_metric,target_unit_metric,target_value,target_unit,start_value_metric,start_value,start_date,created_date"
        ]
        for row in rows {
            let targetMetricStr = String(format: "%.4f", row.targetMetricValue)
            let targetDisplayStr = String(format: "%.2f", row.targetDisplayValue)
            let startMetricStr = row.startMetricValue.map { String(format: "%.4f", $0) } ?? ""
            let startDisplayStr = row.startDisplayValue.map { String(format: "%.2f", $0) } ?? ""
            let startDateStr = row.startDate.map { formatter.string(from: $0) } ?? ""
            let createdStr = formatter.string(from: row.createdDate)
            lines.append([
                csvField(row.kindRaw),
                csvField(row.metricTitle),
                csvField(row.direction),
                targetMetricStr,
                csvField(row.targetMetricUnit),
                targetDisplayStr,
                csvField(row.targetDisplayUnit),
                startMetricStr,
                startDisplayStr,
                startDateStr,
                createdStr
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Escapuje pole CSV zgodnie z RFC 4180 — otacza cudzysłowami jeśli zawiera przecinek, cudzysłów lub nową linię.
    private nonisolated static func csvField(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private nonisolated static func buildDiagnosticsJSON(
        samples: [MetricSampleSnapshot],
        photosCount: Int,
        isSyncEnabled: Bool,
        lastHealthImportTimestamp: Double,
        device: DeviceSnapshot
    ) -> Data? {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metricCounts = Dictionary(grouping: samples) { $0.kindRaw }
            .mapValues { $0.count }

        let healthKitStatus = healthKitStatusText()
        let lastSync = lastHealthImportTimestamp > 0 ? iso.string(from: Date(timeIntervalSince1970: lastHealthImportTimestamp)) : nil

        let payload: [String: Any] = [
            "timestamp": iso.string(from: now),
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "system": "\(device.systemName) \(device.systemVersion)",
            "deviceModel": device.model,
            "metricsCount": samples.count,
            "metricsByKind": metricCounts,
            "photosCount": photosCount,
            "healthKit": [
                "available": HKHealthStore.isHealthDataAvailable(),
                "syncEnabled": isSyncEnabled,
                "authorizationStatus": healthKitStatus,
                "lastSync": lastSync as Any
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private nonisolated static func healthKitStatusText() -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "unavailable" }
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return "unknown" }
        let status = HKHealthStore().authorizationStatus(for: type)
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "denied"
        case .sharingAuthorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func writeTempFile(named name: String, contents: String) -> URL? {
        guard let data = contents.data(using: .utf8) else { return nil }
        return writeTempFile(named: name, data: data)
    }

    private func writeTempFile(named name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.debug("⚠️ Failed to write export file: \(error.localizedDescription)")
            return nil
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

    // MARK: - Import types

    private enum ImportStrategy { case merge, replace }

    private struct ImportResult {
        var samplesInserted: Int = 0
        var goalsInserted: Int = 0
        var goalsUpdated: Int = 0
        var rowsSkipped: Int = 0
    }

    private struct ParsedSampleRow {
        let kindRaw: String
        let value: Double   // value_metric — wartość bazowa (kg/cm/%)
        let date: Date
    }

    private struct MetricsParseResult {
        var rows: [ParsedSampleRow] = []
        var skipped: Int = 0
        nonisolated init() { rows = []; skipped = 0 }
    }

    private struct ParsedGoalRow {
        let kindRaw: String
        let direction: String
        let targetValue: Double     // target_value_metric
        let startValue: Double?     // start_value_metric (opcjonalne)
        let startDate: Date?
        let createdDate: Date
    }

    private struct GoalsParseResult {
        var rows: [ParsedGoalRow] = []
        var skipped: Int = 0
        nonisolated init() { rows = []; skipped = 0 }
    }

    // MARK: - Import logic

    @MainActor
    private func performImport(urls: [URL], strategy: ImportStrategy) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            let metricsURL = urls.first { $0.lastPathComponent.contains("metrics") }
            let goalsURL   = urls.first { $0.lastPathComponent.contains("goals") }

            var result = ImportResult()

            if strategy == .replace {
                try? deleteAllEntities(of: MetricSample.self)
                try? deleteAllEntities(of: MetricGoal.self)
                try? modelContext.save()
            }

            if let url = metricsURL {
                let r = await Task.detached(priority: .userInitiated) {
                    self.parseMetricsCSV(url: url)
                }.value
                insertSamples(r.rows, strategy: strategy, result: &result)
                result.rowsSkipped += r.skipped
            }

            if let url = goalsURL {
                let r = await Task.detached(priority: .userInitiated) {
                    self.parseGoalsCSV(url: url)
                }.value
                insertGoals(r.rows, strategy: strategy, result: &result)
                result.rowsSkipped += r.skipped
            }

            try? modelContext.save()

            var msg = String(format: AppLocalization.string("Imported %d measurements and %d goals."),
                             result.samplesInserted, result.goalsInserted + result.goalsUpdated)
            if result.rowsSkipped > 0 {
                msg += " " + String(format: AppLocalization.string("%d rows skipped."), result.rowsSkipped)
            }
            importResultMessage = msg
            isImporting = false
            pendingImportURLs = []
            showImportResult = true
            Haptics.success()
        }
    }

    // MARK: - CSV Parsers

    private nonisolated func parseMetricsCSV(url: URL) -> MetricsParseResult {
        var result = MetricsParseResult()
        guard url.startAccessingSecurityScopedResource() else { return result }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return result }
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return result }

        let cols = parseCSVLine(headerLine)
        guard let idxId  = cols.firstIndex(of: "metric_id"),
              let idxVal = cols.firstIndex(of: "value_metric"),
              let idxTs  = cols.firstIndex(of: "timestamp")
        else { return result }

        let isoFull  = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            let maxIdx = max(idxId, idxVal, idxTs)
            guard fields.count > maxIdx else { result.skipped += 1; continue }
            let kindRaw = fields[idxId]
            guard MetricKind(rawValue: kindRaw) != nil else { result.skipped += 1; continue }
            guard let value = Double(fields[idxVal]) else { result.skipped += 1; continue }
            let tsString = fields[idxTs]
            guard let date = isoFull.date(from: tsString) ?? isoBasic.date(from: tsString)
            else { result.skipped += 1; continue }
            result.rows.append(ParsedSampleRow(kindRaw: kindRaw, value: value, date: date))
        }
        return result
    }

    private nonisolated func parseGoalsCSV(url: URL) -> GoalsParseResult {
        var result = GoalsParseResult()
        guard url.startAccessingSecurityScopedResource() else { return result }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return result }
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return result }

        let cols = parseCSVLine(headerLine)
        guard let idxId      = cols.firstIndex(of: "metric_id"),
              let idxDir     = cols.firstIndex(of: "direction"),
              let idxTarget  = cols.firstIndex(of: "target_value_metric"),
              let idxCreated = cols.firstIndex(of: "created_date")
        else { return result }

        let idxStartVal  = cols.firstIndex(of: "start_value_metric")
        let idxStartDate = cols.firstIndex(of: "start_date")

        let isoFull  = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            let maxIdx = max(idxId, idxDir, idxTarget, idxCreated)
            guard fields.count > maxIdx else { result.skipped += 1; continue }

            let kindRaw = fields[idxId]
            guard MetricKind(rawValue: kindRaw) != nil else { result.skipped += 1; continue }

            let direction = fields[idxDir]
            guard direction == "increase" || direction == "decrease" else { result.skipped += 1; continue }

            guard let targetValue = Double(fields[idxTarget]) else { result.skipped += 1; continue }

            let createdStr = fields[idxCreated]
            guard let createdDate = isoFull.date(from: createdStr) ?? isoBasic.date(from: createdStr)
            else { result.skipped += 1; continue }

            var startValue: Double? = nil
            if let idx = idxStartVal, idx < fields.count, !fields[idx].isEmpty {
                startValue = Double(fields[idx])
            }
            var startDate: Date? = nil
            if let idx = idxStartDate, idx < fields.count, !fields[idx].isEmpty {
                startDate = isoFull.date(from: fields[idx]) ?? isoBasic.date(from: fields[idx])
            }

            result.rows.append(ParsedGoalRow(
                kindRaw: kindRaw,
                direction: direction,
                targetValue: targetValue,
                startValue: startValue,
                startDate: startDate,
                createdDate: createdDate
            ))
        }
        return result
    }

    /// RFC 4180 CSV line splitter — obsługuje pola w cudzysłowach i podwójne cudzysłowy.
    private nonisolated func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: idx)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        idx = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else if c == "\r" {
                    // pomiń CR w CRLF
                } else {
                    current.append(c)
                }
            }
            idx = line.index(after: idx)
        }
        fields.append(current)
        return fields
    }

    // MARK: - SwiftData Insert helpers

    @MainActor
    private func insertSamples(_ rows: [ParsedSampleRow], strategy: ImportStrategy, result: inout ImportResult) {
        var existingKeys = Set<String>()
        if strategy == .merge {
            let descriptor = FetchDescriptor<MetricSample>()
            let existing = (try? modelContext.fetch(descriptor)) ?? []
            for s in existing {
                let epoch = Int(s.date.timeIntervalSince1970)
                existingKeys.insert("\(s.kindRaw)_\(epoch)")
            }
        }
        for row in rows {
            if strategy == .merge {
                let epoch = Int(row.date.timeIntervalSince1970)
                let key = "\(row.kindRaw)_\(epoch)"
                if existingKeys.contains(key) { continue }
                existingKeys.insert(key)
            }
            guard let kind = MetricKind(rawValue: row.kindRaw) else { continue }
            modelContext.insert(MetricSample(kind: kind, value: row.value, date: row.date))
            result.samplesInserted += 1
        }
    }

    @MainActor
    private func insertGoals(_ rows: [ParsedGoalRow], strategy: ImportStrategy, result: inout ImportResult) {
        let descriptor = FetchDescriptor<MetricGoal>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        var existingByKind = Dictionary(uniqueKeysWithValues: existing.map { ($0.kindRaw, $0) })

        for row in rows {
            guard let kind = MetricKind(rawValue: row.kindRaw),
                  let direction = MetricGoal.Direction(rawValue: row.direction)
            else { continue }

            if let existingGoal = existingByKind[row.kindRaw] {
                existingGoal.targetValue = row.targetValue
                existingGoal.directionRaw = row.direction
                existingGoal.startValue = row.startValue
                existingGoal.startDate = row.startDate
                existingGoal.createdDate = row.createdDate
                result.goalsUpdated += 1
            } else {
                let newGoal = MetricGoal(
                    kind: kind,
                    targetValue: row.targetValue,
                    direction: direction,
                    createdDate: row.createdDate,
                    startValue: row.startValue,
                    startDate: row.startDate
                )
                modelContext.insert(newGoal)
                existingByKind[row.kindRaw] = newGoal
                result.goalsInserted += 1
            }
        }
    }
}
