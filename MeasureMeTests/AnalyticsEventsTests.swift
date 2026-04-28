import XCTest
@testable import MeasureMe

final class AnalyticsEventsTests: XCTestCase {
    func testOnboardingSessionStartedPayloadIsStableAndPIIFree() {
        let event = AnalyticsEvents.onboardingSessionStarted(entrypoint: "root", restoredState: true)

        XCTAssertEqual(event.name, AnalyticsEventName.Onboarding.sessionStarted)
        XCTAssertEqual(
            event.parameters,
            [
                "flow_version": "3",
                "entrypoint": "root",
                "restored_state": "true"
            ]
        )
        XCTAssertNil(event.parameters["userName"])
        XCTAssertNil(event.parameters["height"])
        XCTAssertNil(event.parameters["age"])
    }

    func testOnboardingHealthPermissionResolvedUsesBooleanFlagsInsteadOfValues() {
        let event = AnalyticsEvents.onboardingHealthPermissionResolved(
            source: "onboarding",
            result: "granted",
            importedAge: true,
            importedHeight: false
        )

        XCTAssertEqual(event.name, AnalyticsEventName.Onboarding.healthPermissionResolved)
        XCTAssertEqual(event.parameters["imported_age"], "true")
        XCTAssertEqual(event.parameters["imported_height"], "false")
        XCTAssertNil(event.parameters["age"])
        XCTAssertNil(event.parameters["height"])
    }

    func testMeasurementSavedUsesControlledSourceAndBooleanString() {
        let event = AnalyticsEvents.measurementSaved(
            source: .activation,
            metricsCount: 2,
            isFirstMeasurement: false
        )

        XCTAssertEqual(event.name, AnalyticsEventName.Measurement.saved)
        XCTAssertEqual(event.parameters["source"], "activation")
        XCTAssertEqual(event.parameters["metrics_count"], "2")
        XCTAssertEqual(event.parameters["is_first_measurement"], "false")
    }

    func testPaywallPresentedUsesDeclaredSource() {
        let event = AnalyticsEvents.paywallPresented(source: .feature, reason: "feature_locked")

        XCTAssertEqual(event.name, AnalyticsEventName.Paywall.presented)
        XCTAssertEqual(event.parameters["source"], "feature")
        XCTAssertEqual(event.parameters["reason"], "feature_locked")
    }
}
