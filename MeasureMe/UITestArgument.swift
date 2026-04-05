import Foundation

enum UITestArgument: String {
    case mode = "-uiTestMode"
    case onboardingMode = "-uiTestOnboardingMode"
    case openSettingsTab = "-uiTestOpenSettingsTab"
    case openSingleAdd = "-uiTestOpenSingleAdd"
    case openMultiImport = "-uiTestOpenMultiImport"

    // Premium / billing
    case forcePremium = "-uiTestForcePremium"
    case forceNonPremium = "-uiTestForceNonPremium"
    case simulateTrialActivation = "-uiTestSimulateTrialActivation"
    case showTrialReminderPrompt = "-uiTestShowTrialReminderPrompt"

    // Seeding
    case seedMeasurements = "-uiTestSeedMeasurements"
    case seedPhotos = "-uiTestSeedPhotos"
    case seedPhotoMetrics = "-uiTestSeedPhotoMetrics"
    case skipMeasurementSeeding = "-uiTestSkipMeasurementSeeding"
    case noActiveMetrics = "-uiTestNoActiveMetrics"

    // Health
    case healthAuthDenied = "-uiTestHealthAuthDenied"
    case healthAuthUnavailable = "-uiTestHealthAuthUnavailable"
    case bypassHealthSummaryGuards = "-uiTestBypassHealthSummaryGuards"

    // Checklist
    case showChecklist = "-uiTestShowChecklist"
    case expandChecklist = "-uiTestExpandChecklist"
    case checklistNeedsReminders = "-uiTestChecklistNeedsReminders"

    // Gender
    case genderNotSpecified = "-uiTestGenderNotSpecified"
    case genderMale = "-uiTestGenderMale"
    case genderFemale = "-uiTestGenderFemale"

    // Language
    case languagePL = "-uiTestLanguagePL"
    case languageEN = "-uiTestLanguageEN"
    case languageSystem = "-uiTestLanguageSystem"

    // Physique / indicators
    case physiqueSWROff = "-uiTestPhysiqueSWROff"

    // iCloud
    case enableICloudBackup = "-uiTestEnableICloudBackup"

    // AI / Insights
    case forceAIAvailable = "-uiTestForceAIAvailable"
    case longInsight = "-uiTestLongInsight"
    case longHealthInsight = "-uiTestLongHealthInsight"
    case longNextFocusInsight = "-uiTestLongNextFocusInsight"

    // Photos / pending
    case expandMeasurements = "-uiTestExpandMeasurements"
    case pendingSlow = "-uiTestPendingSlow"
    case pendingForceFailure = "-uiTestPendingForceFailure"

    // Home
    case homePinnedAction = "-uiTestHomePinnedAction"
    case pendingAppEntryAction = "-uiTestPendingAppEntryAction"
    case activationHub = "-uiTestActivationHub"
    case activationTask = "-uiTestActivationTask"
}

extension UITestArgument {

    /// `true` when this argument was passed at launch.
    nonisolated static func isPresent(_ arg: UITestArgument) -> Bool {
        ProcessInfo.processInfo.arguments.contains(arg.rawValue)
    }

    /// `true` when either `.mode` or `.onboardingMode` was passed.
    nonisolated static var isAnyTestMode: Bool {
        isPresent(.mode) || isPresent(.onboardingMode)
    }

    /// Returns the string value following the given flag, e.g. `-uiTestSeedPhotos 24` → `"24"`.
    nonisolated static func value(for arg: UITestArgument, in args: [String]? = nil) -> String? {
        let arguments = args ?? ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: arg.rawValue),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }
}
