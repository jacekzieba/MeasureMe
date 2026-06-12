import XCTest

/// v5 onboarding flow (6 steps): welcome(0) → goal(1) → startingPoint(2) → rhythm(3) → boosters(4) → plan(5).
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

    /// Goal cards don't receive synthesized XCUITest taps, so the goal is chosen via a launch
    /// argument; the test then advances from welcome to the goal step and on to starting point.
    private func selectGoalAndAdvance(_ identifier: String) {
        let priorityRaw = identifier.replacingOccurrences(of: "onboarding.priority.", with: "")
        launchApp(arguments: ["-uiTestOnboardingMode", "-uiTestOnboardingPriority", priorityRaw])
        advancePastWelcome()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForOnboardingStep("step:1"))
        nextButton.tap()
    }

    private func assertWeightHeroFieldVisible() {
        let field = app.textFields["onboarding.measurement.weight"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Expected the weight hero field on the starting point step")
    }

    /// Navigate to the boosters step where the Apple Health soft ask lives.
    /// Rhythm is reached then *skipped* so the test never triggers the notification system prompt.
    private func advanceToBoostersStep(selecting identifier: String = "onboarding.priority.improveHealth") {
        selectGoalAndAdvance(identifier)
        XCTAssertTrue(waitForOnboardingStep("step:2"))
        assertWeightHeroFieldVisible()
        XCTAssertFalse(app.buttons["onboarding.health.allow"].exists, "Health prompt should not appear on the starting point step")

        nextButton.tap() // starting point → rhythm
        XCTAssertTrue(waitForOnboardingStep("step:3"))
        XCTAssertFalse(app.buttons["onboarding.health.allow"].exists, "Health prompt should not appear on the rhythm step")

        skipButton.tap() // rhythm → boosters (skip avoids the notification permission prompt)
        XCTAssertTrue(waitForOnboardingStep("step:4"))
        XCTAssertTrue(app.buttons["onboarding.health.allow"].waitForExistence(timeout: 5))
    }

    func testOnboardingStartsOnGoalStep() {
        advancePastWelcome()
        XCTAssertFalse(app.textFields["onboarding.name.field"].exists, "v5 goal step no longer asks for a name")
        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.buildMuscle"].exists)
        XCTAssertTrue(app.buttons["onboarding.priority.improveHealth"].exists)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForOnboardingStep("step:1"))
    }

    func testBackNavigationReturnsFromStartingPointToGoal() {
        selectGoalAndAdvance("onboarding.priority.loseWeight")

        XCTAssertTrue(waitForOnboardingStep("step:2"))

        backButton.tap()

        XCTAssertTrue(waitForOnboardingStep("step:1"))
        XCTAssertTrue(app.buttons["onboarding.priority.loseWeight"].exists)
    }

    func testStartingPointShowsWeightHero() {
        selectGoalAndAdvance("onboarding.priority.buildMuscle")

        assertWeightHeroFieldVisible()
        XCTAssertTrue(waitForOnboardingStep("step:2"))
    }

    func testHealthPromptAppearsOnBoostersStep() {
        advanceToBoostersStep()

        let healthButton = app.buttons["onboarding.health.allow"].firstMatch
        XCTAssertTrue(healthButton.exists, "Health soft ask should appear on the boosters step")
        XCTAssertTrue(skipButton.exists, "Boosters step should still allow skipping")
    }

    func testOnboardingFinishesFromPlan() {
        advanceToBoostersStep()

        nextButton.tap() // boosters → plan
        XCTAssertTrue(waitForOnboardingStep("step:5"))

        nextButton.tap() // plan → dashboard

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Finishing the plan should open the main app")
    }

    func testOnboardingCanReachDashboardWithSkips() {
        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:1"))

        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:2"))

        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:3"))

        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:4"))

        skipButton.tap()
        XCTAssertTrue(waitForOnboardingStep("step:5"))

        skipButton.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Finishing onboarding should open the main app")
    }
}
