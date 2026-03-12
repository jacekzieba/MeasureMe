import SwiftUI
import SwiftData
import HealthKit
import UIKit

private extension Notification.Name {
    static let settingsOpenHomeSettingsRequested = Notification.Name("settingsOpenHomeSettingsRequested")
}

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
    @ObservedObject private var settingsStore = AppSettingsStore.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @AppSetting(\.health.isSyncEnabled) private var isSyncEnabled: Bool = false
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    @AppSetting(\.home.settingsOpenTrackedMeasurements) private var settingsOpenTrackedMeasurements: Bool = false
    @AppSetting(\.home.settingsOpenReminders) private var settingsOpenReminders: Bool = false
    @AppSetting(\.home.settingsOpenHomeSettings) private var settingsOpenHomeSettings: Bool = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.experience.hapticsEnabled) private var hapticsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    @AppSetting(\.experience.appLanguage) private var appLanguage: String = "system"
    
    // Core Metrics visibility
    @AppSetting(\.indicators.showWHtROnHome) private var showWHtROnHome: Bool = true
    @AppSetting(\.indicators.showRFMOnHome) private var showRFMOnHome: Bool = true
    @AppSetting(\.indicators.showBMIOnHome) private var showBMIOnHome: Bool = true
    
    // Body Composition visibility
    @AppSetting(\.indicators.showBodyFatOnHome) private var showBodyFatOnHome: Bool = true
    @AppSetting(\.indicators.showLeanMassOnHome) private var showLeanMassOnHome: Bool = true
    
    // Risk Indicators visibility
    @AppSetting(\.indicators.showWHROnHome) private var showWHROnHome: Bool = true
    @AppSetting(\.indicators.showWaistRiskOnHome) private var showWaistRiskOnHome: Bool = true
    @AppSetting(\.indicators.showABSIOnHome) private var showABSIOnHome: Bool = true
    @AppSetting(\.indicators.showBodyShapeScoreOnHome) private var showBodyShapeScoreOnHome: Bool = true
    @AppSetting(\.indicators.showCentralFatRiskOnHome) private var showCentralFatRiskOnHome: Bool = true

    // Physique indicators visibility
    @AppSetting(\.indicators.showPhysiqueSWR) private var showPhysiqueSWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueCWR) private var showPhysiqueCWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueSHR) private var showPhysiqueSHR: Bool = true
    @AppSetting(\.indicators.showPhysiqueHWR) private var showPhysiqueHWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueBWR) private var showPhysiqueBWR: Bool = true
    @AppSetting(\.indicators.showPhysiqueWHtR) private var showPhysiqueWHtR: Bool = true
    @AppSetting(\.indicators.showPhysiqueBodyFat) private var showPhysiqueBodyFat: Bool = true
    @AppSetting(\.indicators.showPhysiqueRFM) private var showPhysiqueRFM: Bool = true
    
    @AppSetting(\.profile.userGender) private var userGender: String = "notSpecified"
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0.0
    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.health.healthkitLastImport) private var lastHealthImportTimestamp: Double = 0.0
    @AppSetting(\.analytics.appleIntelligenceEnabled) private var appleIntelligenceEnabled: Bool = true
    
    @AppSetting(\.health.healthkitSyncWeight) private var hkWeight: Bool = true
    @AppSetting(\.health.healthkitSyncBodyFat) private var hkBodyFat: Bool = true
    @AppSetting(\.health.healthkitSyncHeight) private var hkHeight: Bool = true
    @AppSetting(\.health.healthkitSyncLeanBodyMass) private var hkLeanMass: Bool = true
    @AppSetting(\.health.healthkitSyncWaist) private var hkWaist: Bool = true
    @AppSetting(\.iCloudBackup.isEnabled) private var iCloudBackupEnabled: Bool = true
    @AppSetting(\.iCloudBackup.lastSuccessTimestamp) private var iCloudBackupLastSuccessTimestamp: Double = 0
    @AppSetting(\.iCloudBackup.lastErrorMessage) private var iCloudBackupLastErrorMessage: String = ""

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
    @State private var showBackupResult = false
    @State private var backupResultMessage = ""
    @State private var showRestoreBackupConfirm = false
    @State private var showRestoreResult = false
    @State private var restoreResultMessage = ""
    @State private var showRestoreConflict = false
    @State private var restoreConflictMessage = ""
    @State private var settingsSearchQuery: String = ""
    @State private var selectedSettingsRoute: SettingsSearchRoute?
    
    private var lastImportText: String? {
        guard lastHealthImportTimestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: lastHealthImportTimestamp)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var iCloudBackupLastSuccessText: String {
        guard iCloudBackupLastSuccessTimestamp > 0 else {
            return AppLocalization.string("No iCloud backup yet.")
        }
        let date = Date(timeIntervalSince1970: iCloudBackupLastSuccessTimestamp)
        return AppLocalization.string("Last iCloud backup: %@", date.formatted(date: .abbreviated, time: .shortened))
    }

    private var iCloudBackupErrorText: String? {
        let trimmed = iCloudBackupLastErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private var homeModuleSummary: String {
        let visibleCount = settingsStore.homeLayoutSnapshot().items.filter(\.isVisible).count
        return AppLocalization.string("settings.summary.home.modules", visibleCount)
    }

    private var notificationsSummary: String {
        switch SettingsOverviewSummaryBuilder.notificationState(
            notificationsEnabled: notificationManager.notificationsEnabled,
            reminderCount: NotificationManager.shared.loadReminders().count
        ) {
        case .off:
            return AppLocalization.string("settings.summary.notifications.off")
        case .enabledNoSchedule:
            return AppLocalization.string("settings.summary.notifications.none")
        case .scheduled(let count):
            return AppLocalization.string("settings.summary.notifications.count", count)
        }
    }

    private var languageSummary: String {
        switch AppLanguage(rawValue: appLanguage) ?? .system {
        case .system:
            return AppLocalization.string("System")
        case .en:
            return AppLocalization.string("English")
        case .pl:
            return AppLocalization.string("Polish")
        }
    }

    private var unitsSummary: String {
        unitsSystem == "imperial"
            ? AppLocalization.string("Imperial")
            : AppLocalization.string("Metric")
    }

    private var experienceSummary: String {
        switch SettingsOverviewSummaryBuilder.experienceState(
            animationsEnabled: animationsEnabled,
            hapticsEnabled: hapticsEnabled
        ) {
        case .full:
            return AppLocalization.string("settings.summary.experience.full")
        case .reduced:
            return AppLocalization.string("settings.summary.experience.reduced")
        case .mixed:
            return AppLocalization.string("settings.summary.experience.mixed")
        }
    }

    private var profileSummary: String {
        switch SettingsOverviewSummaryBuilder.profileState(
            userName: userName,
            userAge: userAge,
            manualHeight: manualHeight,
            userGender: userGender
        ) {
        case .named(let name):
            return name
        case .incomplete:
            return AppLocalization.string("settings.summary.profile.incomplete")
        case .empty:
            return AppLocalization.string("settings.summary.profile.empty")
        }
    }

    private var trackedMetricsSummary: String {
        let enabledCount = SettingsOverviewSummaryBuilder.trackedMetricCount(
            metricFlags: AppSettingsKeys.Metrics.allEnabledKeys.map { settingsStore.bool(forKey: $0) }
        )
        return AppLocalization.string("settings.summary.metrics.count", enabledCount)
    }

    private var indicatorsSummary: String {
        let enabledCount = SettingsOverviewSummaryBuilder.indicatorsCount(indicatorFlags: [
            showWHtROnHome,
            showRFMOnHome,
            showBMIOnHome,
            showBodyFatOnHome,
            showLeanMassOnHome,
            showWHROnHome,
            showWaistRiskOnHome,
            showABSIOnHome,
            showBodyShapeScoreOnHome,
            showCentralFatRiskOnHome,
            showPhysiqueSWR,
            showPhysiqueCWR,
            showPhysiqueSHR,
            showPhysiqueHWR,
            showPhysiqueBWR,
            showPhysiqueWHtR,
            showPhysiqueBodyFat,
            showPhysiqueRFM
        ])
        return AppLocalization.string("settings.summary.indicators.count", enabledCount)
    }

    private var healthSummary: String {
        switch SettingsOverviewSummaryBuilder.healthState(
            isSyncEnabled: isSyncEnabled,
            lastImportText: lastImportText
        ) {
        case .off:
            return AppLocalization.string("settings.summary.health.off")
        case .onLastImport(let lastImportText):
            return AppLocalization.string("settings.summary.health.on.lastimport", lastImportText)
        case .on:
            return AppLocalization.string("settings.summary.health.on")
        }
    }

    private var aiSummary: String {
        switch SettingsOverviewSummaryBuilder.aiState(
            isPremium: premiumStore.isPremium,
            isAIAvailable: AppleIntelligenceSupport.isAvailable(),
            isAIEnabled: appleIntelligenceEnabled
        ) {
        case .locked:
            return AppLocalization.string("settings.summary.ai.locked")
        case .unavailable:
            return AppLocalization.string("settings.summary.ai.unavailable")
        case .disabled:
            return AppLocalization.string("settings.summary.ai.disabled")
        case .available:
            return AppLocalization.string("settings.summary.ai.available")
        }
    }

    private var accountTitle: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "MeasureMe" : trimmed
    }

    private var accountSubtitle: String {
        premiumStore.isPremium
            ? AppLocalization.string("settings.summary.premium.active")
            : AppLocalization.string("settings.summary.premium.free")
    }

    private let settingsTheme = FeatureTheme.settings
    private let healthTheme = FeatureTheme.health

    @ViewBuilder private var settingsSearchSection: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfaceElevated) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(AppTypography.iconMedium)
                        .foregroundStyle(AppColorRoles.textTertiary)
                        .accessibilityHidden(true)

                    TextField(
                        AppLocalization.string("Search Settings"),
                        text: $settingsSearchQuery
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .accessibilityIdentifier("settings.search.field")

                    if isSearchingSettings {
                        Button {
                            settingsSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.iconMedium)
                                .foregroundStyle(AppColorRoles.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.search.clear")
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("settings.section.search")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)
    }

    @ViewBuilder private var settingsSections: some View {
        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.account"))

            SettingsCard(tint: settingsTheme.strongTint) {
                HStack(spacing: AppSpacing.sm) {
                    Image("BrandButton")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountTitle)
                            .font(AppTypography.displayStatement)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(accountSubtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Spacer()
                }

                if premiumStore.isPremium {
                    SettingsActionRow(
                        title: AppLocalization.string("Manage subscription"),
                        subtitle: AppLocalization.string("settings.summary.subscription.manage"),
                        systemImage: "crown.fill",
                        trailingText: nil,
                        accessibilityIdentifier: "settings.row.manageSubscription"
                    ) {
                        premiumStore.openManageSubscriptions()
                    }

                    SettingsRowDivider()

                    SettingsNavigationRow(
                        title: AppLocalization.string("Premium Edition"),
                        subtitle: AppLocalization.string("settings.app.subscription.view.benefits"),
                        systemImage: "checkmark.seal.fill",
                        trailingText: nil,
                        accessibilityIdentifier: "settings.row.premiumBenefits"
                    ) {
                        PremiumBenefitsInfoView()
                    }
                } else {
                    Text(AppLocalization.string("settings.summary.premium.pitch"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        premiumStore.presentPaywall(reason: .settings)
                    } label: {
                        Text(AppLocalization.string("settings.action.explorePremium"))
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                    .accessibilityIdentifier("settings.action.explorePremium")
                }
            }
            .accessibilityIdentifier("settings.section.account")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)

        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.setup"))

            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                settingsOverviewRow(
                    route: .home,
                    title: AppLocalization.string("Home"),
                    subtitle: homeModuleSummary,
                    systemImage: "house.fill",
                    accessibilityIdentifier: "settings.row.home"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .notifications,
                    title: AppLocalization.string("Notifications"),
                    subtitle: notificationsSummary,
                    systemImage: "bell.badge",
                    accessibilityIdentifier: "settings.row.notifications"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .language,
                    title: AppLocalization.string("Language"),
                    subtitle: languageSummary,
                    systemImage: "globe",
                    accessibilityIdentifier: "settings.row.language"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .units,
                    title: AppLocalization.string("Units"),
                    subtitle: unitsSummary,
                    systemImage: "ruler",
                    accessibilityIdentifier: "settings.row.units"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .experience,
                    title: AppLocalization.string("Animations and haptics"),
                    subtitle: experienceSummary,
                    systemImage: "apple.haptics.and.music.note",
                    accessibilityIdentifier: "settings.row.experience"
                )
            }
            .accessibilityIdentifier("settings.section.setup")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)

        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.measurements"))

            SettingsCard(tint: FeatureTheme.measurements.softTint) {
                settingsOverviewRow(
                    route: .profile,
                    title: AppLocalization.string("Profile"),
                    subtitle: profileSummary,
                    systemImage: "person.crop.circle",
                    accessibilityIdentifier: "settings.row.profile"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .metrics,
                    title: AppLocalization.string("Metrics"),
                    subtitle: trackedMetricsSummary,
                    systemImage: "list.bullet.clipboard",
                    accessibilityIdentifier: "settings.row.metrics"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .indicators,
                    title: AppLocalization.string("Indicators"),
                    subtitle: indicatorsSummary,
                    systemImage: "slider.horizontal.3",
                    accessibilityIdentifier: "settings.row.indicators"
                )
            }
            .accessibilityIdentifier("settings.section.measurements")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)

        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.insights"))

            SettingsCard(tint: FeatureTheme.premium.softTint) {
                settingsOverviewRow(
                    route: .aiInsights,
                    title: AppLocalization.string("AI Insights"),
                    subtitle: aiSummary,
                    systemImage: "sparkles",
                    accessibilityIdentifier: "settings.row.ai"
                )
            }
            .accessibilityIdentifier("settings.section.insights")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)

        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.health"))

            SettingsCard(tint: healthTheme.softTint) {
                settingsOverviewRow(
                    route: .health,
                    title: AppLocalization.string("Health"),
                    subtitle: healthSummary,
                    systemImage: "heart.fill",
                    accessibilityIdentifier: "settings.row.health"
                )
            }
            .accessibilityIdentifier("settings.section.health")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)

        Section {
            SettingsSectionEyebrow(title: AppLocalization.string("settings.section.support"))

            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                settingsOverviewRow(
                    route: .data,
                    title: AppLocalization.string("Data"),
                    subtitle: AppLocalization.string("settings.summary.data"),
                    systemImage: "square.and.arrow.up",
                    accessibilityIdentifier: "settings.row.data"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .faq,
                    title: AppLocalization.string("FAQ"),
                    subtitle: AppLocalization.string("settings.summary.support"),
                    systemImage: "questionmark.circle",
                    accessibilityIdentifier: "settings.row.faq"
                )

                SettingsRowDivider()

                settingsOverviewRow(
                    route: .about,
                    title: AppLocalization.string("About"),
                    subtitle: AppLocalization.string("About MeasureMe"),
                    systemImage: "info.circle",
                    accessibilityIdentifier: "settings.row.about"
                )
            }
            .accessibilityIdentifier("settings.section.support")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(Self.settingsRowInsets)

        Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsCardHeader(title: AppLocalization.string("App"), systemImage: "iphone.gen3.sizes")

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
                .accessibilityIdentifier("settings.row.restorePurchases")

                SettingsRowDivider()

                Button {
                    shareApp()
                } label: {
                    appSectionRowLabel(
                        title: AppLocalization.string("Share app"),
                        subtitle: "MeasureMe – Body Tracker",
                        trailingSymbol: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("settings.row.shareApp")

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
            .accessibilityIdentifier("settings.section.app")
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

                settingsSearchSection

                if isSearchingSettings {
                    Section {
                        if filteredSettingsSearchItems.isEmpty {
                            Text(AppLocalization.string("No matching settings"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                        } else {
                            ForEach(filteredSettingsSearchItems) { item in
                                Button {
                                    openSettingsRoute(item.route)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(item.subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .buttonStyle(.plain)
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
            .tint(settingsTheme.accent)
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
            .onChange(of: settingsOpenHomeSettings) { _, _ in
                schedulePendingDeepLinksHandling()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsOpenHomeSettingsRequested)) { _ in
                openSettingsRoute(.home)
            }
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowSeparatorTint(.clear)
            .listSectionSeparatorTint(.clear)
            .applyNoScrollContentInsetsIfAvailable()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                // Keep the navigation bar chrome stable during push transitions.
                .toolbarBackground(.hidden, for: .navigationBar)
                .accessibilityIdentifier("settings.root")
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
            .alert(AppLocalization.string("iCloud Backup"), isPresented: $showBackupResult) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(backupResultMessage)
            }
            .alert(AppLocalization.string("Restore from backup"), isPresented: $showRestoreBackupConfirm) {
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Restore"), role: .destructive) {
                    performRestore()
                }
            } message: {
                Text(AppLocalization.string("This will replace all current measurements, goals, photos, and settings with the latest iCloud backup."))
            }
            .alert(AppLocalization.string("Replace all local data with backup?"), isPresented: $showRestoreConflict) {
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Replace"), role: .destructive) {
                    performRestore()
                }
            } message: {
                Text(restoreConflictMessage)
            }
            .alert(AppLocalization.string("Restore from backup"), isPresented: $showRestoreResult) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(restoreResultMessage)
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
            .navigationDestination(item: $selectedSettingsRoute) { route in
                settingsSearchDestination(for: route)
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
                    .foregroundStyle(AppColorRoles.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
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

    private func shareApp() {
        let appName = "MeasureMe – Body Tracker"
        let shareText = AppLocalization.string(
            "share.app.message",
            appName,
            LegalLinks.appStore.absoluteString
        )
        shareItems = [shareText, LegalLinks.appStore]
        shareSubject = appName
        isPresentingShareSheet = true
    }

    @ViewBuilder
    private func settingsOverviewRow(
        route: SettingsSearchRoute,
        title: String,
        subtitle: String,
        systemImage: String,
        accessibilityIdentifier: String
    ) -> some View {
        SettingsActionRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            openSettingsRoute(route)
        }
    }

    private func openSettingsRoute(_ route: SettingsSearchRoute) {
        settingsSearchQuery = ""
        selectedSettingsRoute = route
    }

    private func handlePendingDeepLinks() {
        if settingsOpenTrackedMeasurements {
            settingsOpenTrackedMeasurements = false
            openSettingsRoute(.metrics)
        }

        if settingsOpenReminders {
            settingsOpenReminders = false
            openSettingsRoute(.notifications)
        }

        if settingsOpenHomeSettings {
            settingsOpenHomeSettings = false
            openSettingsRoute(.home)
        }
    }

    private func schedulePendingDeepLinksHandling() {
        Task { @MainActor in
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

    private func performBackupNow() {
        Task { @MainActor in
            AppSettingsStore.shared.set(\.iCloudBackup.isEnabled, true)
            let result = await ICloudBackupService.createBackupNow(context: modelContext, isPremium: true)
            switch result {
            case .success(let manifest):
                Haptics.success()
                backupResultMessage = AppLocalization.string("Backup complete. %d measurements, %d goals, %d photos saved.", manifest.metricsCount, manifest.goalsCount, manifest.photosCount)
                showBackupResult = true
            case .failure(let error):
                Haptics.error()
                backupResultMessage = error.localizedMessage
                showBackupResult = true
            }
        }
    }

    private func initiateRestore() {
        Task { @MainActor in
            let preflightResult = await ICloudBackupService.preflightRestore(context: modelContext, isPremium: true)
            switch preflightResult {
            case .success(let manifest):
                let localMetrics = (try? modelContext.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
                let localGoals = (try? modelContext.fetchCount(FetchDescriptor<MetricGoal>())) ?? 0
                let localPhotos = (try? modelContext.fetchCount(FetchDescriptor<PhotoEntry>())) ?? 0

                if localMetrics == 0 && localGoals == 0 && localPhotos == 0 {
                    // Database empty — restore without confirmation
                    performRestore()
                } else {
                    // Database has data — show conflict alert with details
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    let backupDate = formatter.string(from: manifest.createdAt)

                    restoreConflictMessage = AppLocalization.string("Your data: %d measurements, %d goals, %d photos.", localMetrics, localGoals, localPhotos)
                        + "\n"
                        + AppLocalization.string("Backup from %@ contains %d measurements, %d goals, %d photos.", backupDate, manifest.metricsCount, manifest.goalsCount, manifest.photosCount)
                    showRestoreConflict = true
                }
            case .failure(let error):
                Haptics.error()
                restoreResultMessage = error.localizedMessage
                showRestoreResult = true
            }
        }
    }

    private func performRestore() {
        Task { @MainActor in
            let result = await ICloudBackupService.restoreLatestBackupManually(context: modelContext, isPremium: true)
            switch result {
            case .success:
                Haptics.success()
                restoreResultMessage = AppLocalization.string("Data restored successfully from iCloud backup.")
                showRestoreResult = true
            case .failure(let error):
                Haptics.error()
                restoreResultMessage = error.localizedMessage
                showRestoreResult = true
            }
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
        AppSettingsStore.shared.clearHealthKitSyncMetadata()
    }

    private func clearUserDataDefaults() {
        AppSettingsStore.shared.clearUserDataDefaults()
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
            HomeSettingsDetailView()
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
                iCloudBackupEnabled: $iCloudBackupEnabled,
                iCloudBackupLastSuccessText: iCloudBackupLastSuccessText,
                iCloudBackupLastErrorText: iCloudBackupErrorText,
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
                    SettingsDataActions.runPremiumAction(
                        isPremium: premiumStore.isPremium,
                        feature: "Data import",
                        onAllowed: { showImportPicker = true },
                        onLocked: { premiumStore.presentPaywall(reason: .feature($0)) }
                    )
                },
                onBackupNow: {
                    Haptics.light()
                    SettingsDataActions.runPremiumAction(
                        isPremium: premiumStore.isPremium,
                        feature: "iCloud Backup",
                        onAllowed: { performBackupNow() },
                        onLocked: { premiumStore.presentPaywall(reason: .feature($0)) }
                    )
                },
                onRestoreLatestBackup: {
                    Haptics.light()
                    SettingsDataActions.runPremiumAction(
                        isPremium: premiumStore.isPremium,
                        feature: "iCloud Backup",
                        onAllowed: { initiateRestore() },
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
                    .tint(settingsTheme.accent)
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
            do {
                let msg = try await SettingsImporter.importData(urls: urls, strategy: strategy, context: modelContext)
                importResultMessage = msg
                Haptics.success()
            } catch {
                importResultMessage = error.localizedDescription
                Haptics.error()
            }
            isImporting = false
            pendingImportURLs = []
            showImportResult = true
        }
    }
}
