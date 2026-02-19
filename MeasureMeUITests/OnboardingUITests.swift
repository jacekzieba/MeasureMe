import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestOnboardingMode"]
        app.launch()
    }

    @MainActor
    func testWelcomeGoalAccessibilityValueReflectsSelection() {
        let goalIDs = [
            "onboarding.goal.loseWeight",
            "onboarding.goal.buildMuscle",
            "onboarding.goal.trackHealth"
        ]

        guard let goalButton = goalIDs
            .map({ app.buttons[$0] })
            .first(where: { $0.waitForExistence(timeout: 3) }) else {
            XCTFail("Expected at least one onboarding goal button")
            return
        }

        goalButton.tap()
        let value = goalButton.value as? String
        XCTAssertNotNil(value, "Goal should expose accessibility value")
        XCTAssertFalse((value ?? "").isEmpty, "Accessibility value should not be empty")
    }

    @MainActor
    func testNavigateThroughAllStepsSequentially() {
        // welcome -> profile -> boosters -> premium
        for _ in 0..<3 {
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5), "Next button should exist")
            XCTAssertTrue(next.isEnabled, "Next button should be enabled")
            next.tap()
        }

        let nextOnPremium = app.buttons["onboarding.next"]
        XCTAssertTrue(nextOnPremium.waitForExistence(timeout: 5), "Next button should exist on premium step")
        XCTAssertTrue(nextOnPremium.isEnabled, "Next button should be enabled on premium step")
    }

    @MainActor
    func testPremiumStepShowsLegalLinksAndRestoreAction() {
        // welcome -> profile -> boosters -> premium
        for _ in 0..<3 {
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5), "Next button should exist")
            next.tap()
        }

        let restore = app.buttons["onboarding.premium.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "Restore purchases action should be visible on premium step")

        let privacyLink = app.descendants(matching: .any)["onboarding.premium.privacy"]
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 5), "Privacy Policy link should be visible on premium step")

        let termsLink = app.descendants(matching: .any)["onboarding.premium.terms"]
        XCTAssertTrue(termsLink.waitForExistence(timeout: 5), "Terms of Use link should be visible on premium step")
    }

    @MainActor
    func testRemindersButtonOpensSheet() {
        // welcome -> profile -> boosters
        for _ in 0..<2 {
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }

        let remindersButton = app.buttons["onboarding.booster.reminders"]
        XCTAssertTrue(remindersButton.waitForExistence(timeout: 5), "Reminders booster button should exist")
        remindersButton.tap()

        let cancel = app.buttons["onboarding.reminder.cancel"]
        let confirm = app.buttons["onboarding.reminder.confirm"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5) || confirm.waitForExistence(timeout: 5),
                      "Reminder setup sheet should appear")
        if cancel.exists {
            cancel.tap()
        }
    }

    @MainActor
    func testPrivacyNoteVisibleOnWelcome() {
        let privacyNote = app.descendants(matching: .any)["onboarding.privacy.note"]
        XCTAssertTrue(privacyNote.waitForExistence(timeout: 5), "Privacy note should be visible on onboarding welcome")
    }
}
