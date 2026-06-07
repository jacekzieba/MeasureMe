import XCTest
@testable import MeasureMe

final class AnalyticsEventsTests: XCTestCase {
    func testOnboardingSessionStartedPayloadIsStableAndPIIFree() {
        let event = AnalyticsEvents.onboardingSessionStarted(entrypoint: "root", restoredState: true)

        XCTAssertEqual(event.name, AnalyticsEventName.Onboarding.sessionStarted)
        XCTAssertEqual(
            event.parameters,
            [
                "flow_version": AnalyticsEvents.onboardingFlowVersion,
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

    func testHealthPermissionUsesNeutralSource() {
        let prompted = AnalyticsEvents.healthPermissionPrompted(source: .settings)
        let resolved = AnalyticsEvents.healthPermissionResolved(source: .checklist, result: "denied")

        XCTAssertEqual(prompted.name, AnalyticsEventName.Health.permissionPrompted)
        XCTAssertEqual(prompted.parameters["source"], "settings")
        XCTAssertEqual(resolved.name, AnalyticsEventName.Health.permissionResolved)
        XCTAssertEqual(resolved.parameters["source"], "checklist")
        XCTAssertEqual(resolved.parameters["result"], "denied")
    }

    func testPhotoEventsSupportOnboardingSource() {
        let started = AnalyticsEvents.photoAddStarted(source: .onboarding)
        let completed = AnalyticsEvents.photoAddCompleted(source: .onboarding, isFirstPhoto: true)

        XCTAssertEqual(started.name, AnalyticsEventName.Photo.addStarted)
        XCTAssertEqual(started.parameters["source"], "onboarding")
        XCTAssertEqual(completed.name, AnalyticsEventName.Photo.addCompleted)
        XCTAssertEqual(completed.parameters["source"], "onboarding")
        XCTAssertEqual(completed.parameters["is_first_photo"], "true")
    }

    func testPurchaseRestoreCompletedUsesLowCardinalityResult() {
        let event = AnalyticsEvents.purchaseRestoreCompleted(source: .paywall, result: "restored")

        XCTAssertEqual(event.name, AnalyticsEventName.Purchase.restoreCompleted)
        XCTAssertEqual(event.parameters["source"], "paywall")
        XCTAssertEqual(event.parameters["result"], "restored")
    }

    func testActivationDismissedIncludesProgressWithoutPII() {
        let event = AnalyticsEvents.activationDismissed(
            currentTask: "addPhoto",
            completedTasksCount: 1,
            skippedTasksCount: 2
        )

        XCTAssertEqual(event.name, AnalyticsEventName.Activation.dismissed)
        XCTAssertEqual(event.parameters["current_task"], "addPhoto")
        XCTAssertEqual(event.parameters["completed_tasks_count"], "1")
        XCTAssertEqual(event.parameters["skipped_tasks_count"], "2")
    }
}
