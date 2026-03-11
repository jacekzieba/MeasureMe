import XCTest
@testable import MeasureMe

@MainActor
final class SettingsOverviewSummaryTests: XCTestCase {
    func testNotificationStatePrefersOffWhenNotificationsDisabled() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.notificationState(
                notificationsEnabled: false,
                reminderCount: 3
            ),
            .off
        )
    }

    func testNotificationStateReportsScheduledCount() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.notificationState(
                notificationsEnabled: true,
                reminderCount: 2
            ),
            .scheduled(2)
        )
    }

    func testExperienceStateDistinguishesFullReducedAndMixed() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.experienceState(
                animationsEnabled: true,
                hapticsEnabled: true
            ),
            .full
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.experienceState(
                animationsEnabled: false,
                hapticsEnabled: false
            ),
            .reduced
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.experienceState(
                animationsEnabled: true,
                hapticsEnabled: false
            ),
            .mixed
        )
    }

    func testProfileStateUsesNameBeforeFallbacks() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.profileState(
                userName: " Jacek ",
                userAge: 0,
                manualHeight: 0,
                userGender: "notSpecified"
            ),
            .named("Jacek")
        )
    }

    func testProfileStateDetectsIncompleteProfileWithoutName() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.profileState(
                userName: "",
                userAge: 28,
                manualHeight: 0,
                userGender: "notSpecified"
            ),
            .incomplete
        )
    }

    func testProfileStateDetectsEmptyProfile() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.profileState(
                userName: "",
                userAge: 0,
                manualHeight: 0,
                userGender: "notSpecified"
            ),
            .empty
        )
    }

    func testTrackedMetricAndIndicatorCountersCountEnabledFlags() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.trackedMetricCount(metricFlags: [true, false, true, false]),
            2
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.indicatorsCount(indicatorFlags: [true, true, false]),
            2
        )
    }

    func testHealthStateIncludesLastImportWhenAvailable() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.healthState(
                isSyncEnabled: true,
                lastImportText: "Mar 9, 08:14"
            ),
            .onLastImport("Mar 9, 08:14")
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.healthState(
                isSyncEnabled: true,
                lastImportText: nil
            ),
            .on
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.healthState(
                isSyncEnabled: false,
                lastImportText: "Mar 9, 08:14"
            ),
            .off
        )
    }

    func testAIStateMatchesPremiumAvailabilityAndToggle() {
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.aiState(
                isPremium: false,
                isAIAvailable: true,
                isAIEnabled: true
            ),
            .locked
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.aiState(
                isPremium: true,
                isAIAvailable: false,
                isAIEnabled: true
            ),
            .unavailable
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.aiState(
                isPremium: true,
                isAIAvailable: true,
                isAIEnabled: false
            ),
            .disabled
        )
        XCTAssertEqual(
            SettingsOverviewSummaryBuilder.aiState(
                isPremium: true,
                isAIAvailable: true,
                isAIEnabled: true
            ),
            .available
        )
    }
}
