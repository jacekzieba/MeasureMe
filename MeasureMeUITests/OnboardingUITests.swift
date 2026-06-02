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

    private func waitForOnboardingStep(_ expected: String, timeout: TimeInterval = 5) -> Bool {
        let stepHook = app.staticTexts["root.onboarding.test.step"].firstMatch
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: stepHook)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func advancePastWelcome() {
        XCTAssertTrue(waitForOnboardingStep("step:0"), "Expected to start on welcome step")
        nextButton.tap()
    }

    private func selectGoalAndAdvance(_ identifier: String) {
        // Onboarding content buttons don't receive synthesized XCUITest taps (the flow
        // bridges navigation through NotificationCenter for the same reason), so the goal
        // is chosen via a launch argument rather than by tapping the priority card.
        let priorityRaw = identifier.replacingOccurrences(of: "onboarding.priority.", with: "")
        launchApp(arguments: ["-uiTestOnboardingMode", "-uiTestOnboardingPriority", priorityRaw])
        advancePastWelcome()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        nextButton.tap()
    }

    private func advanceToHealthStep(selecting identifier: String = "onboarding.priority.improveHealth") {
        selectGoalAndAdvance(identifier)
        nextButton.tap()
        nextButton.tap()
        XCTAssertTrue(app.buttons["onboarding.health.allow"].waitForExistence(timeout: 5))
    }

    func testOnboardingStartsOnCombinedProfileStep() {
        advancePastWelcome()
        XCTAssertTrue(app.textFields["onboarding.name.field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.buildMuscle"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.improveHealth"].exists)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForOnboardingStep("step:1"))
    }

    func testBackNavigationReturnsFromMetricsToProfileStep() {
        selectGoalAndAdvance("onboarding.priority.loseWeight")

        let stepHook = app.staticTexts["root.onboarding.test.step"].firstMatch
        XCTAssertTrue(stepHook.waitForExistence(timeout: 5))
        XCTAssertEqual(stepHook.label, "step:2")

        backButton.tap()

        XCTAssertTrue(waitForOnboardingStep("step:1"))
        XCTAssertTrue(app.textFields["onboarding.name.field"].exists)
    }

    func testMetricsScreenReflectsSelectedGoal() {
        selectGoalAndAdvance("onboarding.priority.buildMuscle")

        XCTAssertTrue(app.staticTexts["Chest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Left bicep"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForOnboardingStep("step:2"))
    }

    func testHealthPromptAppearsAfterMetricsAndPhotos() {
        advanceToHealthStep()

        let healthButton = app.buttons["onboarding.health.allow"].firstMatch
        XCTAssertTrue(healthButton.exists, "Health soft ask should appear before the final Premium step")
        XCTAssertTrue(skipButton.exists, "Health step should still allow skipping")
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.note"].firstMatch.exists)
    }

    func testPremiumStepAppearsAfterHealth() {
        advanceToHealthStep()

        nextButton.tap()

        XCTAssertTrue(waitForOnboardingStep("step:5"))
        XCTAssertTrue(app.buttons["onboarding.premium.trial"].firstMatch.waitForExistence(timeout: 8))
    }

    func testOnboardingCanReachDashboardWithSkips() {
        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:1"))

        nextButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:2"))

        nextButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:3"))

        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:4"))

        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:5"))

        skipButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Finishing onboarding should open the main app")
    }
}
