import Foundation
import StoreKit

protocol AnalyticsClient {
    var isEnabled: Bool { get }
    func setup()
    func track(_ signal: AnalyticsSignal)
    func track(signalName: String, parameters: [String: String])
    func trackPaywallShown(reason: String, parameters: [String: String])
    func trackPurchaseCompleted(_ transaction: StoreKit.Transaction, parameters: [String: String])
}

enum AnalyticsSignal: String, CaseIterable {
    case appLaunched = "com.jacekzieba.measureme.app.launched"
    case appFirstFrameReady = "com.jacekzieba.measureme.app.first_frame_ready"

    case tabHomeSelected = "com.jacekzieba.measureme.tab.home.selected"
    case tabMeasurementsSelected = "com.jacekzieba.measureme.tab.measurements.selected"
    case tabPhotosSelected = "com.jacekzieba.measureme.tab.photos.selected"
    case tabSettingsSelected = "com.jacekzieba.measureme.tab.settings.selected"

    case onboardingStarted = "com.jacekzieba.measureme.onboarding.started"
    case onboardingStepWelcomeViewed = "com.jacekzieba.measureme.onboarding.step.welcome.viewed"
    case onboardingStepProfileViewed = "com.jacekzieba.measureme.onboarding.step.profile.viewed"
    case onboardingStepBoostersViewed = "com.jacekzieba.measureme.onboarding.step.boosters.viewed"
    case onboardingStepPremiumViewed = "com.jacekzieba.measureme.onboarding.step.premium.viewed"
    case onboardingCompleted = "com.jacekzieba.measureme.onboarding.completed"
    case onboardingSkipped = "com.jacekzieba.measureme.onboarding.skipped"
    case onboardingGoalLoseWeight  = "com.jacekzieba.measureme.onboarding.goal.lose_weight"
    case onboardingGoalBuildMuscle = "com.jacekzieba.measureme.onboarding.goal.build_muscle"
    case onboardingGoalTrackHealth = "com.jacekzieba.measureme.onboarding.goal.track_health"

    case firstMetricAdded = "com.jacekzieba.measureme.metric.first_added"
    case firstPhotoAdded = "com.jacekzieba.measureme.photo.first_added"

    case streakExtended = "com.jacekzieba.measureme.streak.extended"
    case streakBroken = "com.jacekzieba.measureme.streak.broken"

    static func onboardingStepViewed(stepIndex: Int) -> AnalyticsSignal? {
        switch stepIndex {
        case 0:
            return .onboardingStepWelcomeViewed
        case 1:
            return .onboardingStepProfileViewed
        case 2:
            return .onboardingStepBoostersViewed
        default:
            return nil
        }
    }
}

extension AppTab {
    var analyticsSelectionSignal: AnalyticsSignal? {
        switch self {
        case .home:
            return .tabHomeSelected
        case .measurements:
            return .tabMeasurementsSelected
        case .photos:
            return .tabPhotosSelected
        case .settings:
            return .tabSettingsSelected
        case .compose:
            return nil
        }
    }
}

enum AnalyticsPolicy {
    static let analyticsEnabledKey = "analytics_enabled"

    static func isEnabled(
        auditConfig: AuditConfig = .current,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: AppSettingsStore,
        isDebugBuild: Bool = isDebugFlag
    ) -> Bool {
        if auditConfig.disableAnalytics {
            return false
        }

        if userDefaults.object(forKey: analyticsEnabledKey) != nil,
           !userDefaults.bool(forKey: analyticsEnabledKey) {
            return false
        }

        if isDebugBuild {
            return false
        }

        if arguments.contains(UITestArgument.mode.rawValue) || arguments.contains(UITestArgument.onboardingMode.rawValue) {
            return false
        }

        return true
    }

    static func isEnabled(
        auditConfig: AuditConfig = .current,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDebugBuild: Bool = isDebugFlag
    ) -> Bool {
        isEnabled(
            auditConfig: auditConfig,
            arguments: arguments,
            userDefaults: .shared,
            isDebugBuild: isDebugBuild
        )
    }

    private static var isDebugFlag: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

final class NoopAnalyticsClient: AnalyticsClient {
    var isEnabled: Bool { false }
    func setup() {}
    func track(_ signal: AnalyticsSignal) {}
    func track(signalName: String, parameters: [String : String]) {}
    func trackPaywallShown(reason: String, parameters: [String : String]) {}
    func trackPurchaseCompleted(_ transaction: StoreKit.Transaction, parameters: [String : String]) {}
}
