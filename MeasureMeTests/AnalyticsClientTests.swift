import XCTest
@testable import MeasureMe

@MainActor
final class AnalyticsClientTests: XCTestCase {
    func testPolicyDisabledWhenAuditDisablesAnalytics() {
        let defaults = UserDefaults(suiteName: "AnalyticsClientTests.audit")!
        defaults.removePersistentDomain(forName: "AnalyticsClientTests.audit")
        defaults.set(true, forKey: AnalyticsPolicy.analyticsEnabledKey)
        let settings = AppSettingsStore(defaults: defaults)

        let config = AuditConfig(
            isEnabled: true,
            useMockData: false,
            disableAnalytics: true,
            disablePaywallNetwork: false,
            fixedDate: nil,
            route: nil
        )

        let enabled = AnalyticsPolicy.isEnabled(
            auditConfig: config,
            arguments: ["MeasureMe"],
            userDefaults: settings,
            isDebugBuild: false
        )

        XCTAssertFalse(enabled)
    }

    func testPolicyDisabledWhenUserTurnsAnalyticsOff() {
        let defaults = UserDefaults(suiteName: "AnalyticsClientTests.userOff")!
        defaults.removePersistentDomain(forName: "AnalyticsClientTests.userOff")
        defaults.set(false, forKey: AnalyticsPolicy.analyticsEnabledKey)
        let settings = AppSettingsStore(defaults: defaults)

        let config = AuditConfig(
            isEnabled: false,
            useMockData: false,
            disableAnalytics: false,
            disablePaywallNetwork: false,
            fixedDate: nil,
            route: nil
        )

        let enabled = AnalyticsPolicy.isEnabled(
            auditConfig: config,
            arguments: ["MeasureMe"],
            userDefaults: settings,
            isDebugBuild: false
        )

        XCTAssertFalse(enabled)
    }

    func testPolicyDisabledInDebugBuild() {
        let defaults = UserDefaults(suiteName: "AnalyticsClientTests.debug")!
        defaults.removePersistentDomain(forName: "AnalyticsClientTests.debug")
        defaults.set(true, forKey: AnalyticsPolicy.analyticsEnabledKey)
        let settings = AppSettingsStore(defaults: defaults)

        let config = AuditConfig(
            isEnabled: false,
            useMockData: false,
            disableAnalytics: false,
            disablePaywallNetwork: false,
            fixedDate: nil,
            route: nil
        )

        let enabled = AnalyticsPolicy.isEnabled(
            auditConfig: config,
            arguments: ["MeasureMe"],
            userDefaults: settings,
            isDebugBuild: true
        )

        XCTAssertFalse(enabled)
    }

    func testPolicyDisabledForUITestModeArguments() {
        let defaults = UserDefaults(suiteName: "AnalyticsClientTests.uitest")!
        defaults.removePersistentDomain(forName: "AnalyticsClientTests.uitest")
        defaults.set(true, forKey: AnalyticsPolicy.analyticsEnabledKey)
        let settings = AppSettingsStore(defaults: defaults)

        let config = AuditConfig(
            isEnabled: false,
            useMockData: false,
            disableAnalytics: false,
            disablePaywallNetwork: false,
            fixedDate: nil,
            route: nil
        )

        let modeDisabled = AnalyticsPolicy.isEnabled(
            auditConfig: config,
            arguments: ["MeasureMe", "-uiTestMode"],
            userDefaults: settings,
            isDebugBuild: false
        )
        let onboardingDisabled = AnalyticsPolicy.isEnabled(
            auditConfig: config,
            arguments: ["MeasureMe", "-uiTestOnboardingMode"],
            userDefaults: settings,
            isDebugBuild: false
        )

        XCTAssertFalse(modeDisabled)
        XCTAssertFalse(onboardingDisabled)
    }

    func testPolicyEnabledOnlyWhenAllConditionsPass() {
        let defaults = UserDefaults(suiteName: "AnalyticsClientTests.enabled")!
        defaults.removePersistentDomain(forName: "AnalyticsClientTests.enabled")
        defaults.set(true, forKey: AnalyticsPolicy.analyticsEnabledKey)
        let settings = AppSettingsStore(defaults: defaults)

        let config = AuditConfig(
            isEnabled: false,
            useMockData: false,
            disableAnalytics: false,
            disablePaywallNetwork: false,
            fixedDate: nil,
            route: nil
        )

        let enabled = AnalyticsPolicy.isEnabled(
            auditConfig: config,
            arguments: ["MeasureMe"],
            userDefaults: settings,
            isDebugBuild: false
        )

        XCTAssertTrue(enabled)
    }

    func testTabToSignalMapping() {
        XCTAssertEqual(AppTab.home.analyticsSelectionSignal, .tabHomeSelected)
        XCTAssertEqual(AppTab.measurements.analyticsSelectionSignal, .tabMeasurementsSelected)
        XCTAssertEqual(AppTab.photos.analyticsSelectionSignal, .tabPhotosSelected)
        XCTAssertEqual(AppTab.settings.analyticsSelectionSignal, .tabSettingsSelected)
        XCTAssertNil(AppTab.compose.analyticsSelectionSignal)
    }

    func testOnboardingStepToSignalMapping() {
        XCTAssertEqual(AnalyticsSignal.onboardingStepViewed(stepIndex: 0), .onboardingStepWelcomeViewed)
        XCTAssertEqual(AnalyticsSignal.onboardingStepViewed(stepIndex: 1), .onboardingStepProfileViewed)
        XCTAssertEqual(AnalyticsSignal.onboardingStepViewed(stepIndex: 2), .onboardingStepBoostersViewed)
        XCTAssertEqual(AnalyticsSignal.onboardingStepViewed(stepIndex: 3), .onboardingStepPremiumViewed)
        XCTAssertNil(AnalyticsSignal.onboardingStepViewed(stepIndex: -1))
        XCTAssertNil(AnalyticsSignal.onboardingStepViewed(stepIndex: 99))
    }

    func testFirstEventsSignalNames() {
        XCTAssertEqual(AnalyticsSignal.firstMetricAdded.rawValue, "com.jacekzieba.measureme.metric.first_added")
        XCTAssertEqual(AnalyticsSignal.firstPhotoAdded.rawValue, "com.jacekzieba.measureme.photo.first_added")
    }
}
