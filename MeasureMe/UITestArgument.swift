import Foundation

enum UITestArgument: String {
    case mode = "-uiTestMode"
    case onboardingMode = "-uiTestOnboardingMode"
    case openSettingsTab = "-uiTestOpenSettingsTab"
    case openExperienceSettings = "-uiTestOpenExperienceSettings"
    case openSingleAdd = "-uiTestOpenSingleAdd"
    case openMultiImport = "-uiTestOpenMultiImport"
    case onboardingPriority = "-uiTestOnboardingPriority"
    /// Forces `hasCompletedOnboarding = true` and nothing else — no premium, no
    /// seeded data, no implied `-uiTestMode`. For tests that need a launch
    /// argument to state its own precondition (skip onboarding) rather than
    /// depending on whatever a previous launch left in UserDefaults.
    case forceOnboardingComplete = "-uiTestForceOnboardingComplete"

    // Premium / billing
    case forcePremium = "-uiTestForcePremium"
    case forceNonPremium = "-uiTestForceNonPremium"
    case simulateTrialActivation = "-uiTestSimulateTrialActivation"
    case showTrialReminderPrompt = "-uiTestShowTrialReminderPrompt"
    case showSettingsPaywall = "-uiTestShowSettingsPaywall"

    // Release notes
    case showWhatsNew = "-uiTestShowWhatsNew"

    // Seeding
    case seedMeasurements = "-uiTestSeedMeasurements"
    case seedPhotos = "-uiTestSeedPhotos"
    case seedPhotoMetrics = "-uiTestSeedPhotoMetrics"
    case skipMeasurementSeeding = "-uiTestSkipMeasurementSeeding"
    case noActiveMetrics = "-uiTestNoActiveMetrics"
    case profileName = "-uiTestProfileName"

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
    case languageES = "-uiTestLanguageES"
    case languageDE = "-uiTestLanguageDE"
    case languageFR = "-uiTestLanguageFR"
    case languagePTBR = "-uiTestLanguagePTBR"
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
    case pendingNavigationRoute = "-uiTestPendingNavigationRoute"
    case activationHub = "-uiTestActivationHub"
    case activationTask = "-uiTestActivationTask"
}

extension UITestArgument {

    /// `true` when this argument was passed at launch.
    ///
    /// Always `false` in release. These flags reach into premium entitlement, the photo
    /// privacy lock and seeded data, and there is no reason for any of that to be reachable in
    /// a shipping binary — gating here neutralises every call site at once and lets the
    /// optimiser strip the branches behind them.
    nonisolated static func isPresent(_ arg: UITestArgument) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(arg.rawValue)
        #else
        return false
        #endif
    }

    /// `true` when either `.mode` or `.onboardingMode` was passed.
    nonisolated static var isAnyTestMode: Bool {
        isPresent(.mode) || isPresent(.onboardingMode)
    }

    /// Launch arguments as far as this type is concerned — empty in release, so no flag can
    /// be observed in a shipping binary.
    private nonisolated static var processArguments: [String] {
        #if DEBUG
        return ProcessInfo.processInfo.arguments
        #else
        return []
        #endif
    }

    private nonisolated static func environmentFlag(_ name: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment[name] == "1"
        #else
        return false
        #endif
    }

    nonisolated static var shouldShowSettingsPaywall: Bool {
        isPresent(.showSettingsPaywall) || environmentFlag("UI_TEST_SHOW_SETTINGS_PAYWALL")
    }

    nonisolated static var shouldSimulateTrialActivation: Bool {
        isPresent(.simulateTrialActivation) || environmentFlag("UI_TEST_SIMULATE_TRIAL_ACTIVATION")
    }

    /// Returns the string value following the given flag, e.g. `-uiTestSeedPhotos 24` → `"24"`.
    ///
    /// Several call sites read this without an `isPresent` guard first, so the implicit
    /// process-arguments read has to be gated as well; an explicit `args` array is honoured in
    /// every configuration because that is how the unit tests drive it.
    nonisolated static func value(for arg: UITestArgument, in args: [String]? = nil) -> String? {
        let arguments = args ?? processArguments
        guard let index = arguments.firstIndex(of: arg.rawValue),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }
}
