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
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("showLastPhotosOnHome") private var showLastPhotosOnHome: Bool = true
    @AppStorage("showMeasurementsOnHome") private var showMeasurementsOnHome: Bool = true
    @AppStorage("showHealthMetricsOnHome") private var showHealthMetricsOnHome: Bool = true
    @AppStorage("onboarding_checklist_show") private var showOnboardingChecklistOnHome: Bool = true
    @AppStorage("settings_open_tracked_measurements") private var settingsOpenTrackedMeasurements: Bool = false
    @AppStorage("settings_open_reminders") private var settingsOpenReminders: Bool = false
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    
    // Core Metrics visibility
    @AppStorage("showWHtROnHome") private var showWHtROnHome: Bool = true
    @AppStorage("showRFMOnHome") private var showRFMOnHome: Bool = true
    @AppStorage("showBMIOnHome") private var showBMIOnHome: Bool = true
    
    // Body Composition visibility
    @AppStorage("showBodyFatOnHome") private var showBodyFatOnHome: Bool = true
    @AppStorage("showLeanMassOnHome") private var showLeanMassOnHome: Bool = true
    
    // Risk Indicators visibility
    @AppStorage("showABSIOnHome") private var showABSIOnHome: Bool = true
    @AppStorage("showConicityOnHome") private var showConicityOnHome: Bool = true
    
    @AppStorage("userGender") private var userGender: String = "notSpecified"
    @AppStorage("manualHeight") private var manualHeight: Double = 0.0
    @AppStorage("userAge") private var userAge: Int = 0
    @AppStorage("healthkit_last_import") private var lastHealthImportTimestamp: Double = 0.0
    @AppStorage("apple_intelligence_enabled") private var appleIntelligenceEnabled: Bool = true
    
    @AppStorage("healthkit_sync_weight") private var hkWeight: Bool = true
    @AppStorage("healthkit_sync_bodyFat") private var hkBodyFat: Bool = true
    @AppStorage("healthkit_sync_height") private var hkHeight: Bool = true
    @AppStorage("healthkit_sync_leanBodyMass") private var hkLeanMass: Bool = true
    @AppStorage("healthkit_sync_waist") private var hkWaist: Bool = true

    @State private var scrollOffset: CGFloat = 0
    @State private var shareItems: [Any] = []
    @State private var shareSubject: String? = nil
    @State private var isPresentingShareSheet = false
    @State private var isExporting = false
    @State private var exportMessage: String = ""
    @State private var showDeleteAllDataConfirm = false
    @State private var showDeleteAllDataResult = false
    @State private var deleteAllDataResultMessage = ""
    @State private var navigateToTrackedMeasurements: Bool = false
    @State private var navigateToReminders: Bool = false
    @State private var settingsSearchQuery: String = ""
    
    private var lastImportText: String? {
        guard lastHealthImportTimestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: lastHealthImportTimestamp)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private enum SettingsSearchRoute: String, Hashable {
        case profile
        case metrics
        case healthIndicators
        case health
        case notifications
        case home
        case aiInsights
        case units
        case experience
        case language
        case data
        case faq
    }

    private struct SettingsSearchItem: Identifiable {
        let route: SettingsSearchRoute
        let title: String
        let subtitle: String
        let keywords: [String]

        var id: String { route.rawValue + "_" + title }
    }

    private var isSearchingSettings: Bool {
        !settingsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var settingsSearchItems: [SettingsSearchItem] {
        [
            SettingsSearchItem(route: .profile, title: AppLocalization.string("Profile"), subtitle: AppLocalization.string("Name, gender, age, height"), keywords: ["profile", "name", "gender", "age", "height", "profil", "imię", "płeć", "wiek", "wzrost"]),
            SettingsSearchItem(route: .metrics, title: AppLocalization.string("Metrics"), subtitle: AppLocalization.string("Tracked measurements"), keywords: ["metrics", "tracked", "measurements", "metryki", "śledzone", "pomiary"]),
            SettingsSearchItem(route: .healthIndicators, title: AppLocalization.string("Health indicators"), subtitle: AppLocalization.string("Choose indicators to show"), keywords: ["health indicators", "indicators", "wskaźniki", "zdrowia"]),
            SettingsSearchItem(route: .health, title: AppLocalization.string("Health"), subtitle: AppLocalization.string("Sync and synced data"), keywords: ["health", "sync", "synced", "zdrowie", "synchronizacja", "synchronizowane"]),
            SettingsSearchItem(route: .notifications, title: AppLocalization.string("Notifications"), subtitle: AppLocalization.string("Manage reminders"), keywords: ["notifications", "reminders", "powiadomienia", "przypomnienia"]),
            SettingsSearchItem(route: .home, title: AppLocalization.string("Home"), subtitle: AppLocalization.string("Home sections visibility"), keywords: ["home", "strona główna", "widoczność"]),
            SettingsSearchItem(route: .aiInsights, title: AppLocalization.string("AI Insights"), subtitle: AppLocalization.string("Enable AI Insights"), keywords: ["ai", "insights", "analizy ai", "apple intelligence"]),
            SettingsSearchItem(route: .units, title: AppLocalization.string("Units"), subtitle: AppLocalization.string("Metric or imperial"), keywords: ["units", "metric", "imperial", "jednostki", "metryczny", "imperialne"]),
            SettingsSearchItem(route: .experience, title: AppLocalization.string("Animations and haptics"), subtitle: AppLocalization.string("Animations and haptics"), keywords: ["animations", "haptics", "animacje", "haptyka"]),
            SettingsSearchItem(route: .language, title: AppLocalization.string("Language"), subtitle: AppLocalization.string("App language"), keywords: ["language", "app language", "język", "polski", "english"]),
            SettingsSearchItem(route: .data, title: AppLocalization.string("Data"), subtitle: AppLocalization.string("Export and delete"), keywords: ["data", "export", "delete", "dane", "eksport", "usuń"]),
            SettingsSearchItem(route: .faq, title: AppLocalization.string("FAQ"), subtitle: AppLocalization.string("Read frequently asked questions"), keywords: ["faq", "help", "pomoc", "pytania"])
        ]
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
                                .frame(minHeight: 44, alignment: .trailing)
                            }
                        }
                    }
                }
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
                        SettingsCardHeader(title: AppLocalization.string("Health indicators"), systemImage: "heart.text.square.fill")
                        NavigationLink {
                            HealthIndicatorsSettingsDetailView(
                                showWHtROnHome: $showWHtROnHome,
                                showRFMOnHome: $showRFMOnHome,
                                showBMIOnHome: $showBMIOnHome,
                                showBodyFatOnHome: $showBodyFatOnHome,
                                showLeanMassOnHome: $showLeanMassOnHome,
                                showABSIOnHome: $showABSIOnHome,
                                showConicityOnHome: $showConicityOnHome
                            )
                        } label: {
                            Text(AppLocalization.string("Choose indicators to show"))
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
                                showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome
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
                        SettingsCardHeader(title: AppLocalization.string("Animations and haptics"), systemImage: "sparkles")
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

                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.10)) {
                        SettingsCardHeader(title: AppLocalization.string("Data"), systemImage: "square.and.arrow.up")
                        NavigationLink {
                            DataSettingsDetailView(
                                onExport: {
                                    Haptics.light()
                                    if premiumStore.isPremium {
                                        exportMetricsCSV()
                                    } else {
                                        premiumStore.presentPaywall(reason: .feature("Data export"))
                                    }
                                },
                                onDeleteAll: {
                                    Haptics.light()
                                    showDeleteAllDataConfirm = true
                                }
                            )
                        } label: {
                            Text(AppLocalization.string("Open data settings"))
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
                        SettingsCardHeader(title: AppLocalization.string("App"), systemImage: "info.circle")

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

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.about)
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("About"),
                                trailingSymbol: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                        SettingsRowDivider()

                        Button {
                            openURL(LegalLinks.featureRequest)
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("Feature request"),
                                trailingSymbol: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                        SettingsRowDivider()

                        Button {
                            Haptics.light()
                            exportDiagnosticsJSON()
                        } label: {
                            appSectionRowLabel(
                                title: AppLocalization.string("Report a bug"),
                                trailingSymbol: "ladybug"
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

    private func deleteAllEntities<T: PersistentModel>(of type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let objects = try modelContext.fetch(descriptor)
        for object in objects {
            modelContext.delete(object)
        }
    }

    private func clearHealthKitSyncMetadata() {
        let defaults = UserDefaults.standard
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
        let defaults = UserDefaults.standard
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
        case .healthIndicators:
            HealthIndicatorsSettingsDetailView(
                showWHtROnHome: $showWHtROnHome,
                showRFMOnHome: $showRFMOnHome,
                showBMIOnHome: $showBMIOnHome,
                showBodyFatOnHome: $showBodyFatOnHome,
                showLeanMassOnHome: $showLeanMassOnHome,
                showABSIOnHome: $showABSIOnHome,
                showConicityOnHome: $showConicityOnHome
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
                showOnboardingChecklistOnHome: $showOnboardingChecklistOnHome
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
                onDeleteAll: {
                    Haptics.light()
                    showDeleteAllDataConfirm = true
                }
            )
        case .faq:
            FAQView()
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
}

// MARK: - Sections

private struct PremiumBenefitsInfoView: View {
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.appAccent.opacity(0.2))

            List {
                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("settings.app.subscription.active"), systemImage: "checkmark.seal.fill")

                        Text(AppLocalization.string("settings.app.subscription.active.detail"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)

                        SettingsRowDivider()

                        benefitRow(icon: "sparkles", textKey: "premium.carousel.unlock.item.ai")
                        SettingsRowDivider()
                        benefitRow(icon: "photo.on.rectangle.angled", textKey: "premium.carousel.unlock.item.compare")
                        SettingsRowDivider()
                        benefitRow(icon: "heart.text.square.fill", textKey: "premium.carousel.unlock.item.health")
                        SettingsRowDivider()
                        benefitRow(icon: "doc.text.fill", textKey: "premium.carousel.unlock.item.export")
                        SettingsRowDivider()
                        benefitRow(icon: "flag.fill", textKey: "premium.carousel.unlock.item.support")
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Premium Edition"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func benefitRow(icon: String, textKey: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppTypography.iconMedium)
                .foregroundStyle(Color.appAccent)
                .frame(width: 22, alignment: .leading)

            Text(AppLocalization.string(textKey))
                .font(AppTypography.body)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func applyNoScrollContentInsetsIfAvailable() -> some View {
        self
    }
}
