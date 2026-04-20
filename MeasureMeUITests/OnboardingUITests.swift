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
        let identifierNext = app.buttons["onboarding.test.next"].firstMatch
        if identifierNext.waitForExistence(timeout: 0.5) {
            return identifierNext
        }
        return app.buttons["UITest Next"].firstMatch
    }

    private var backButton: XCUIElement {
        let identifierBack = app.buttons["onboarding.test.back"].firstMatch
        if identifierBack.waitForExistence(timeout: 0.5) {
            return identifierBack
        }
        return app.buttons["UITest Back"].firstMatch
    }

    private var skipButton: XCUIElement {
        let identifierSkip = app.buttons["onboarding.test.skip"].firstMatch
        if identifierSkip.waitForExistence(timeout: 0.5) {
            return identifierSkip
        }
        return app.buttons["UITest Skip"].firstMatch
    }

    private func advanceIntroSlides() {
        for _ in 0..<3 {
            XCTAssertTrue(nextButton.waitForExistence(timeout: 10), "Next button should exist on intro slides")
            nextButton.tap()
        }
    }

    private func waitForOnboardingStep(_ expected: String, timeout: TimeInterval = 5) -> Bool {
        let stepHook = app.staticTexts["root.onboarding.test.step"].firstMatch
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: stepHook)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func reachPriorityStep() {
        advanceIntroSlides()
        XCTAssertTrue(app.textFields["onboarding.name.field"].waitForExistence(timeout: 5), "Name field should appear after intro")
        skipButton.tap()
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
        XCTAssertTrue(waitForOnboardingStep("step:0"), "Back should return to the previous intro slide")
    }

    func testIntroSkipAppearsOnlyAfterFirstSlideAndJumpsToName() {
        XCTAssertFalse(app.buttons["onboarding.intro.skip"].firstMatch.exists, "First intro slide should not expose skip intro")

        nextButton.tap()

        let introSkip = app.buttons["onboarding.intro.skip"].firstMatch
        XCTAssertTrue(introSkip.waitForExistence(timeout: 5), "Second intro slide should expose skip intro")
        introSkip.tap()

        XCTAssertTrue(app.textFields["onboarding.name.field"].waitForExistence(timeout: 5), "Skip intro should jump to name")
    }

    func testNameContinueRequiresNonEmptyInput() {
        advanceIntroSlides()

        let stepHook = app.staticTexts["root.onboarding.test.step"].firstMatch
        XCTAssertTrue(stepHook.waitForExistence(timeout: 5))
        XCTAssertEqual(stepHook.label, "step:3")

        nextButton.tap()

        XCTAssertEqual(stepHook.label, "step:3", "Empty name should not advance through the UITest Next bridge")

        let nameField = app.textFields["onboarding.name.field"].firstMatch
        nameField.tap()
        nameField.typeText("Alex")
        nextButton.tap()

        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].waitForExistence(timeout: 5), "Non-empty name should advance to priorities")
    }

    func testPriorityStepShowsThreePrimaryGoals() {
        reachPriorityStep()

        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.buildMuscle"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.improveHealth"].exists)
        XCTAssertTrue(app.staticTexts["Maintain / recomp"].exists)
        XCTAssertTrue(app.staticTexts["Pick one or two to continue."].exists)
    }

    func testHealthPromptAppearsAfterPrioritySelection() {
        reachPriorityStep()

        app.buttons["onboarding.priority.buildMuscle"].tap()
        nextButton.tap()

        let healthButton = app.buttons["onboarding.health.allow"].firstMatch
        XCTAssertTrue(healthButton.waitForExistence(timeout: 5), "Health soft ask should appear after priority selection")
        XCTAssertTrue(skipButton.exists, "Health step should allow skipping")
    }

    func testSkippingHealthCollapsesToContinueAndNoNotificationsStep() {
        reachPriorityStep()

        app.buttons["onboarding.priority.improveHealth"].tap()
        nextButton.tap()

        XCTAssertTrue(app.buttons["onboarding.health.allow"].waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertFalse(app.buttons["onboarding.notifications.allow"].waitForExistence(timeout: 1), "Notifications should no longer be part of onboarding")
        XCTAssertFalse(app.buttons["onboarding.health.allow"].exists, "Skipping Health should move to the completion step")
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Completion should expose the final continue action")
    }

    func testOnboardingCanReachDashboardWithSkips() {
        reachPriorityStep()

        app.buttons["onboarding.priority.loseWeight"].tap()
        nextButton.tap()

        XCTAssertTrue(app.buttons["onboarding.health.allow"].waitForExistence(timeout: 5))
        skipButton.tap()
        nextButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Finishing onboarding should open the main app")
    }

    func testPrivacyNoteVisibleInIntro() {
        nextButton.tap()
        nextButton.tap()

        let privacyNote = app.descendants(matching: .any)["onboarding.privacy.note"].firstMatch
        let privacyCopy = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "never leave your device")
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
