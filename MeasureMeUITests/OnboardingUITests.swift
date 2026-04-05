import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        launchApp(arguments: ["-uiTestOnboardingMode"])
    }

    private func launchApp(arguments: [String]) {
        if app != nil, app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private var nextButton: XCUIElement {
        app.buttons["UITest Next"].firstMatch
    }

    private var backButton: XCUIElement {
        app.buttons["UITest Back"].firstMatch
    }

    private var skipButton: XCUIElement {
        app.buttons["UITest Skip"].firstMatch
    }

    private func advanceIntroSlides() {
        for _ in 0..<5 {
            XCTAssertTrue(nextButton.waitForExistence(timeout: 10), "Next button should exist on intro slides")
            nextButton.tap()
        }
    }

    private func reachPriorityStep() {
        advanceIntroSlides()
        XCTAssertTrue(app.textFields["onboarding.name.field"].waitForExistence(timeout: 5), "Name field should appear after intro")
        skipButton.tap()
        nextButton.tap()
        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].waitForExistence(timeout: 5), "Priority step should appear")
    }

    func testIntroSlidesAdvanceToNameStep() {
        advanceIntroSlides()

        XCTAssertTrue(app.textFields["onboarding.name.field"].waitForExistence(timeout: 5), "Name field should appear after the intro carousel")
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Input steps should expose skip")
    }

    func testBackNavigationReturnsToPreviousIntroSlide() {
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10))
        nextButton.tap()

        let stepHook = app.staticTexts["root.onboarding.test.step"].firstMatch
        XCTAssertTrue(stepHook.waitForExistence(timeout: 5))
        XCTAssertEqual(stepHook.label, "step:1")

        backButton.tap()
        XCTAssertEqual(stepHook.label, "step:0")
    }

    func testPriorityStepShowsThreePrimaryGoals() {
        reachPriorityStep()

        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.buildMuscle"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.improveHealth"].exists)
    }

    func testHealthPromptAppearsAfterPrioritySelection() {
        reachPriorityStep()

        app.buttons["onboarding.priority.buildMuscle"].tap()
        nextButton.tap()

        let healthButton = app.buttons["onboarding.health.allow"].firstMatch
        XCTAssertTrue(healthButton.waitForExistence(timeout: 5), "Health soft ask should appear after personalization")
        XCTAssertTrue(skipButton.exists, "Health step should allow skipping")
    }

    func testSkippingHealthShowsNotificationsStep() {
        reachPriorityStep()

        app.buttons["onboarding.priority.improveHealth"].tap()
        nextButton.tap()

        XCTAssertTrue(app.buttons["onboarding.health.allow"].waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertTrue(app.buttons["onboarding.notifications.allow"].waitForExistence(timeout: 5), "Notifications step should follow the Health step")
    }

    func testOnboardingCanReachDashboardWithSkips() {
        reachPriorityStep()

        app.buttons["onboarding.priority.loseWeight"].tap()
        nextButton.tap()

        XCTAssertTrue(app.buttons["onboarding.health.allow"].waitForExistence(timeout: 5))
        skipButton.tap()
        XCTAssertTrue(app.buttons["onboarding.notifications.allow"].waitForExistence(timeout: 5))
        skipButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Completion step should still expose the final CTA")
        nextButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Finishing onboarding should open the main app")
    }

    func testPrivacyNoteVisibleOnWelcome() {
        let privacyNote = app.descendants(matching: .any)["onboarding.privacy.note"].firstMatch
        let privacyCopy = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Your data stays on this device by default")
        ).firstMatch
        let privacyHookCopy = app.staticTexts["Privacy note"].firstMatch

        XCTAssertTrue(
            privacyNote.waitForExistence(timeout: 10)
                || privacyCopy.waitForExistence(timeout: 10)
                || privacyHookCopy.waitForExistence(timeout: 10),
            "Privacy note should remain visible in onboarding test mode"
        )
    }
}
