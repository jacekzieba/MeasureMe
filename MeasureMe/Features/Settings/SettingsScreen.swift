import SwiftUI
import SwiftData
import HealthKit
import UIKit
import Combine

private extension Notification.Name {
    static let settingsOpenHomeSettingsRequested = Notification.Name("settingsOpenHomeSettingsRequested")
}

// MARK: - Alert consolidation

enum SettingsAlert: Identifiable {
    case deleteAllDataConfirm
    case deleteAllDataResult(String)
    case seedDummyDataConfirm
    case seedDummyDataResult(String)
    case backupResult(String)
    case restoreConfirm
    case restoreConflict(String)
    case restoreResult(String)
    case importResult(String)

    var id: String {
        switch self {
        case .deleteAllDataConfirm: "deleteConfirm"
        case .deleteAllDataResult: "deleteResult"
        case .seedDummyDataConfirm: "seedConfirm"
        case .seedDummyDataResult: "seedResult"
        case .backupResult: "backupResult"
        case .restoreConfirm: "restoreConfirm"
        case .restoreConflict: "restoreConflict"
        case .restoreResult: "restoreResult"
        case .importResult: "importResult"
        }
    }
}

/// **SettingsView**
/// Application settings view. Responsible for:
/// - Enabling/disabling HealthKit synchronization
/// - Selecting units system (metric/imperial)
/// - Navigating to tracked metrics management
/// - Informational "About" section
///
/// **Performance optimizations:**
/// - HealthKit authorization launched asynchronously with a delay
/// - Task cancelled on view disappearance to avoid memory leaks
/// - No blocking of the main thread during permission requests
struct SettingsView: View {
    // MARK: - Constants
    static let settingsRowInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    
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
    @AppSetting(\.experience.appAppearance) private var appAppearance: String = AppAppearance.dark.rawValue
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
    @AppSetting(\.iCloudBackup.isEnabled) private var iCloudBackupEnabled: Bool = false
    @AppSetting(\.iCloudBackup.lastSuccessTimestamp) private var iCloudBackupLastSuccessTimestamp: Double = 0
    @AppSetting(\.iCloudBackup.lastErrorMessage) private var iCloudBackupLastErrorMessage: String = ""

    @State private var scrollOffset: CGFloat = 0
    @State private var shareItems: [Any] = []
    @State private var shareSubject: String? = nil
    @State private var isPresentingShareSheet = false
    @State private var isExporting = false
    @State private var exportMessage: String = ""
    @State private var showImportPicker = false
    @State private var showImportStrategyAlert = false
    @State private var pendingImportURLs: [URL] = []
    @State private var isImporting = false
    @State private var activeAlert: SettingsAlert?
    @State private var settingsSearchQuery: String = ""
    @State private var selectedSettingsRoute: SettingsSearchRoute?
    @State private var isBackingUp = false
    
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

    // MARK: - Consolidated alert helpers

    private var settingsAlertTitle: String {
        switch activeAlert {
        case .deleteAllDataConfirm, .deleteAllDataResult: AppLocalization.string("Delete all data")
        case .seedDummyDataConfirm, .seedDummyDataResult: AppLocalization.string("Seed dummy data")
        case .backupResult: AppLocalization.string("iCloud Backup")
        case .restoreConfirm, .restoreResult: AppLocalization.string("Restore from backup")
        case .restoreConflict: AppLocalization.string("Replace all local data with backup?")
        case .importResult: AppLocalization.string("Import complete")
        case .none: ""
        }
    }

    @ViewBuilder
    private func settingsAlertActions(_ alert: SettingsAlert) -> some View {
        switch alert {
        case .deleteAllDataConfirm:
            Button(AppLocalization.string("Cancel"), role: .cancel) { }
            Button(AppLocalization.string("Delete all data"), role: .destructive) { deleteAllUserData() }
        case .seedDummyDataConfirm:
            Button(AppLocalization.string("Cancel"), role: .cancel) { }
            Button(AppLocalization.string("Seed dummy data")) { seedDummyData() }
        case .restoreConfirm:
            Button(AppLocalization.string("Cancel"), role: .cancel) { }
            Button(AppLocalization.string("Restore"), role: .destructive) { performRestore() }
        case .restoreConflict:
            Button(AppLocalization.string("Cancel"), role: .cancel) { }
            Button(AppLocalization.string("Replace"), role: .destructive) { performRestore() }
        default:
            Button(AppLocalization.string("OK"), role: .cancel) { }
        }
    }

    @ViewBuilder
    private func settingsAlertMessage(_ alert: SettingsAlert) -> some View {
        switch alert {
        case .deleteAllDataConfirm:
            Text(AppLocalization.string("This removes all measurements, goals, photos, reminders, and imported HealthKit data stored in MeasureMe on this device. Apple Health records are not deleted and can be re-imported if sync is enabled again."))
        case .deleteAllDataResult(let msg), .seedDummyDataResult(let msg),
             .backupResult(let msg), .restoreResult(let msg),
             .restoreConflict(let msg), .importResult(let msg):
            Text(msg)
        case .seedDummyDataConfirm:
            Text(AppLocalization.string("This will add realistic sample measurements for recent weeks. Existing data will remain unchanged."))
        case .restoreConfirm:
            Text(AppLocalization.string("This will replace all current measurements, goals, photos, and settings with the latest iCloud backup."))
        }
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

    @State private var homeModuleSummary: String = ""
    @State private var notificationsSummary: String = ""

    private func refreshHomeModuleSummary() {
        let visibleCount = settingsStore.homeLayoutSnapshot().items.filter(\.isVisible).count
        homeModuleSummary = AppLocalization.plural("settings.summary.home.modules", visibleCount)
    }

    private func refreshNotificationsSummary() {
        switch SettingsOverviewSummaryBuilder.notificationState(
            notificationsEnabled: notificationManager.notificationsEnabled,
            reminderCount: NotificationManager.shared.loadReminders().count
        ) {
        case .off:
            notificationsSummary = AppLocalization.string("settings.summary.notifications.off")
        case .enabledNoSchedule:
            notificationsSummary = AppLocalization.string("settings.summary.notifications.none")
        case .scheduled(let count):
            notificationsSummary = AppLocalization.string("settings.summary.notifications.count", count)
        }
    }

    private var languageSummary: String {
        switch AppLanguage.fromStoredValue(appLanguage) {
        case .system:
            return AppLocalization.string("System")
        case .en:
            return AppLocalization.string("English")
        case .pl:
            return AppLocalization.string("Polish")
        case .es:
            return AppLocalization.string("Spanish")
        case .de:
            return AppLocalization.string("German")
        case .fr:
            return AppLocalization.string("French")
        case .ptBR:
            return AppLocalization.string("Portuguese (Brazil)")
        }
    }

    private var unitsSummary: String {
        unitsSystem == "imperial"
            ? AppLocalization.string("Imperial")
            : AppLocalization.string("Metric")
    }

    private var experienceSummary: String {
        switch SettingsOverviewSummaryBuilder.appearanceState(appAppearanceRaw: appAppearance) {
        case .system:
            return AppLocalization.string("settings.summary.appearance.system")
        case .light:
            return AppLocalization.string("settings.summary.appearance.light")
        case .dark:
            return AppLocalization.string("settings.summary.appearance.dark")
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

    private var overviewSnapshot: SettingsOverviewSnapshot {
        SettingsOverviewSnapshot(
            accountTitle: accountTitle,
            accountSubtitle: accountSubtitle,
            homeModuleSummary: homeModuleSummary,
            notificationsSummary: notificationsSummary,
            languageSummary: languageSummary,
            unitsSummary: unitsSummary,
            experienceSummary: experienceSummary,
            profileSummary: profileSummary,
            trackedMetricsSummary: trackedMetricsSummary,
            indicatorsSummary: indicatorsSummary,
            aiSummary: aiSummary,
            healthSummary: healthSummary,
            isPremium: premiumStore.isPremium
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SettingsBackdrop(
                    topHeight: 380,
                    scrollOffset: scrollOffset,
                    tint: Color.cyan.opacity(0.22)
                )
                .ignoresSafeArea(edges: .top)
                
                // Content
                List {
                ScreenTitleHeader(title: AppLocalization.string("Settings"), topPadding: 0, bottomPadding: 4)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                SettingsSearchSection(query: $settingsSearchQuery)

                if !premiumStore.isPremium && !isSearchingSettings {
                    topPremiumCTASection
                }

                if isSearchingSettings {
                    SettingsSearchResultsSection(
                        items: filteredSettingsSearchItems,
                        onOpenRoute: openSettingsRoute
                    )
                } else {
                    SettingsOverviewSections(
                        snapshot: overviewSnapshot,
                        onOpenRoute: openSettingsRoute,
                        onRestorePurchases: { Task { await premiumStore.restorePurchases() } },
                        onShareApp: shareApp,
                        onTerms: { openURL(LegalLinks.termsOfUse) },
                        onPrivacy: { openURL(LegalLinks.privacyPolicy) },
                        onAccessibility: { openURL(LegalLinks.accessibility) },
                        onExplorePremium: { premiumStore.presentPaywall(reason: .settings) },
                        onManageSubscription: { premiumStore.openManageSubscriptions() }
                    )
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
            .scrollContentBackground(.hidden) // Hide default List background
            .onAppear {
                schedulePendingDeepLinksHandling()
                refreshHomeModuleSummary()
                refreshNotificationsSummary()
            }
            .onChange(of: settingsStore.snapshot.homeLayout.layoutData) { _, _ in
                refreshHomeModuleSummary()
            }
            .onReceive(notificationManager.objectWillChange) { _ in
                // Delay slightly so the new values are committed.
                DispatchQueue.main.async { refreshNotificationsSummary() }
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
            .scrollDismissesKeyboard(.interactively)
            .applyNoScrollContentInsetsIfAvailable()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                // Keep the navigation bar chrome stable during push transitions.
                .toolbarBackground(.hidden, for: .navigationBar)
                .accessibilityIdentifier("settings.root")
            .sheet(isPresented: $isPresentingShareSheet) {
                ShareSheet(items: shareItems, subject: shareSubject)
            }
            .alert(
                settingsAlertTitle,
                isPresented: Binding(get: { activeAlert != nil }, set: { if !$0 { activeAlert = nil } }),
                presenting: activeAlert,
                actions: settingsAlertActions,
                message: settingsAlertMessage
            )
            .modifier(
                SettingsImportFlowModifier(
                    showImportPicker: $showImportPicker,
                    showImportStrategyAlert: $showImportStrategyAlert,
                    pendingImportURLs: $pendingImportURLs,
                    activeAlert: $activeAlert,
                    onImport: performImport
                )
            )
            if isExporting {
                exportOverlay
            }
            }
            .navigationDestination(item: $selectedSettingsRoute) { route in
                SettingsRouteDestinationView(
                    route: route,
                    userName: $userName,
                    userGender: $userGender,
                    userAge: $userAge,
                    manualHeight: $manualHeight,
                    unitsSystem: $unitsSystem,
                    showWHtROnHome: $showWHtROnHome,
                    showRFMOnHome: $showRFMOnHome,
                    showBMIOnHome: $showBMIOnHome,
                    showBodyFatOnHome: $showBodyFatOnHome,
                    showLeanMassOnHome: $showLeanMassOnHome,
                    showWHROnHome: $showWHROnHome,
                    showWaistRiskOnHome: $showWaistRiskOnHome,
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
                    showPhysiqueRFM: $showPhysiqueRFM,
                    isSyncEnabled: $isSyncEnabled,
                    hkWeight: $hkWeight,
                    hkBodyFat: $hkBodyFat,
                    hkHeight: $hkHeight,
                    hkLeanMass: $hkLeanMass,
                    hkWaist: $hkWaist,
                    appAppearance: $appAppearance,
                    animationsEnabled: $animationsEnabled,
                    hapticsEnabled: $hapticsEnabled,
                    appLanguage: $appLanguage,
                    appleIntelligenceEnabled: $appleIntelligenceEnabled,
                    iCloudBackupEnabled: $iCloudBackupEnabled,
                    isBackingUp: $isBackingUp,
                    lastImportText: lastImportText,
                    isPremium: premiumStore.isPremium,
                    iCloudBackupLastSuccessText: iCloudBackupLastSuccessText,
                    iCloudBackupLastErrorText: iCloudBackupErrorText,
                    onExport: exportData,
                    onImport: { showImportPicker = true },
                    onBackupNow: performBackupNow,
                    onRestoreLatestBackup: initiateRestore,
                    onPresentPremiumFeature: { premiumStore.presentPaywall(reason: .feature($0)) },
                    onSeedDummyData: { activeAlert = .seedDummyDataConfirm },
                    onDeleteAll: { activeAlert = .deleteAllDataConfirm },
                    onReportBug: exportDiagnosticsJSON
                )
            }
        }
    }

    private var topPremiumCTASection: some View {
        Section {
            Button {
                premiumStore.presentPaywall(reason: .settings)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(AppTypography.iconMedium)
                    Text(AppLocalization.string("settings.action.explorePremium"))
                        .font(AppTypography.bodyEmphasis)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
            .accessibilityIdentifier("settings.action.explorePremium")
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(SettingsView.settingsRowInsets)
    }

    // MARK: - Exports

    private func exportMetricsCSV() {
        exportData(format: .csv)
    }

    private func exportData(format: SettingsExporter.ExportFormat, pdfStartDate: Date? = nil) {
        SettingsTransferCoordinator.exportData(
            format: format,
            context: modelContext,
            unitsSystem: unitsSystem,
            setExportMessage: { exportMessage = $0 },
            setIsExporting: { isExporting = $0 },
            setShareItems: { shareItems = $0 },
            setShareSubject: { shareSubject = $0 },
            setIsPresentingShareSheet: { isPresentingShareSheet = $0 },
            pdfStartDate: pdfStartDate
        )
    }

    private func exportDiagnosticsJSON() {
        SettingsTransferCoordinator.exportDiagnostics(
            context: modelContext,
            isSyncEnabled: isSyncEnabled,
            lastHealthImportTimestamp: lastHealthImportTimestamp,
            setExportMessage: { exportMessage = $0 },
            setIsExporting: { isExporting = $0 },
            setShareItems: { shareItems = $0 },
            setShareSubject: { shareSubject = $0 },
            setIsPresentingShareSheet: { isPresentingShareSheet = $0 }
        )
    }

    private func shareApp() {
        SettingsTransferCoordinator.shareApp(
            setShareItems: { shareItems = $0 },
            setShareSubject: { shareSubject = $0 },
            setIsPresentingShareSheet: { isPresentingShareSheet = $0 }
        )
    }

    private func openSettingsRoute(_ route: SettingsSearchRoute) {
        selectedSettingsRoute = route
        DispatchQueue.main.async {
            settingsSearchQuery = ""
        }
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
            guard premiumStore.isPremium else {
                Haptics.light()
                premiumStore.presentPaywall(reason: .feature("iCloud Backup"))
                return
            }
            isBackingUp = true
            defer { isBackingUp = false }
            let result = await SettingsBackupCoordinator.performBackupNow(
                context: modelContext,
                isPremium: premiumStore.isPremium,
                isBackupEnabled: iCloudBackupEnabled
            )
            if result.isSuccess {
                Haptics.success()
            } else {
                Haptics.error()
            }
            activeAlert = .backupResult(result.message)
        }
    }

    private func initiateRestore() {
        Task { @MainActor in
            guard premiumStore.isPremium else {
                Haptics.light()
                premiumStore.presentPaywall(reason: .feature("iCloud Backup"))
                return
            }
            switch await SettingsBackupCoordinator.preflightRestore(
                context: modelContext,
                isPremium: premiumStore.isPremium
            ) {
            case .readyToRestoreImmediately:
                performRestore()
            case .needsConflictConfirmation(let message):
                activeAlert = .restoreConflict(message)
            case .failed(let message):
                Haptics.error()
                activeAlert = .restoreResult(message)
            }
        }
    }

    private func performRestore() {
        Task { @MainActor in
            guard premiumStore.isPremium else {
                Haptics.light()
                premiumStore.presentPaywall(reason: .feature("iCloud Backup"))
                return
            }
            let result = await SettingsBackupCoordinator.performRestore(
                context: modelContext,
                isPremium: premiumStore.isPremium
            )
            if result.isSuccess {
                Haptics.success()
            } else {
                Haptics.error()
            }
            activeAlert = .restoreResult(result.message)
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

            activeAlert = .deleteAllDataResult(AppLocalization.string("All local app data has been deleted."))
            Haptics.success()
        } catch {
            AppLog.debug("⚠️ Failed to delete all app data: \(error)")
            activeAlert = .deleteAllDataResult(AppLocalization.string("Could not delete all data. Please try again."))
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

            activeAlert = .seedDummyDataResult(String(
                format: AppLocalization.string("Dummy data added: %d measurements."),
                inserted
            ))
            Haptics.success()
        } catch {
            AppLog.debug("⚠️ Failed to seed dummy data: \(error)")
            activeAlert = .seedDummyDataResult(AppLocalization.string("Could not seed dummy data. Please try again."))
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
        SettingsTransferCoordinator.performImport(
            urls: urls,
            strategy: strategy,
            context: modelContext,
            setIsImporting: { isImporting = $0 },
            clearPendingImportURLs: { pendingImportURLs = [] },
            setActiveAlert: { activeAlert = $0 }
        )
    }
}
