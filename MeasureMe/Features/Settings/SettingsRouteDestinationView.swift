import SwiftUI

struct SettingsRouteDestinationView: View {
    let route: SettingsSearchRoute

    @Binding var userName: String
    @Binding var userGender: String
    @Binding var userAge: Int
    @Binding var manualHeight: Double
    @Binding var unitsSystem: String

    @Binding var showWHtROnHome: Bool
    @Binding var showRFMOnHome: Bool
    @Binding var showBMIOnHome: Bool
    @Binding var showBodyFatOnHome: Bool
    @Binding var showLeanMassOnHome: Bool
    @Binding var showWHROnHome: Bool
    @Binding var showWaistRiskOnHome: Bool
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

    @Binding var isSyncEnabled: Bool
    @Binding var hkWeight: Bool
    @Binding var hkBodyFat: Bool
    @Binding var hkHeight: Bool
    @Binding var hkLeanMass: Bool
    @Binding var hkWaist: Bool

    @Binding var appAppearance: String
    @Binding var animationsEnabled: Bool
    @Binding var hapticsEnabled: Bool
    @Binding var appLanguage: String
    @Binding var appleIntelligenceEnabled: Bool
    @Binding var iCloudBackupEnabled: Bool
    @Binding var isBackingUp: Bool

    let lastImportText: String?
    let isPremium: Bool
    let iCloudBackupLastSuccessText: String
    let iCloudBackupLastErrorText: String?
    let onExport: (SettingsExporter.ExportFormat, Date?) -> Void
    let onImport: () -> Void
    let onBackupNow: () -> Void
    let onRestoreLatestBackup: () -> Void
    let onPresentPremiumFeature: (String) -> Void
    let onSeedDummyData: () -> Void
    let onDeleteAll: () -> Void
    let onReportBug: () -> Void

    var body: some View {
        content(for: route)
    }

    @ViewBuilder
    private func content(for route: SettingsSearchRoute) -> some View {
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
                appAppearance: $appAppearance,
                animationsEnabled: $animationsEnabled,
                hapticsEnabled: $hapticsEnabled
            )
        case .language:
            LanguageSettingsDetailView(appLanguage: $appLanguage)
        case .data:
            SettingsDataDestinationView(
                iCloudBackupEnabled: $iCloudBackupEnabled,
                isBackingUp: $isBackingUp,
                isPremium: isPremium,
                iCloudBackupLastSuccessText: iCloudBackupLastSuccessText,
                iCloudBackupLastErrorText: iCloudBackupLastErrorText,
                onExport: onExport,
                onImport: onImport,
                onBackupNow: onBackupNow,
                onRestoreLatestBackup: onRestoreLatestBackup,
                onPresentPremiumFeature: onPresentPremiumFeature,
                onSeedDummyData: onSeedDummyData,
                onDeleteAll: onDeleteAll
            )
        case .faq:
            FAQView()
        case .about:
            SettingsAboutDestinationView(onReportBug: onReportBug)
        }
    }
}
