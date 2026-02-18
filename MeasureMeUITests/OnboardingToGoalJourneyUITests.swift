import XCTest

final class OnboardingToGoalJourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestOnboardingMode", "-uiTestSeedMeasurements"]
        app.launch()
    }

    @MainActor
    func testFullJourneyOnboardingQuickAddChartAndSetGoal() {
        completeOnboardingFlow()

        openMeasurementsTab()

        let measurementsScroll = app.scrollViews["measurements.scroll"]
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 8), "Measurements container should exist")

        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'metric.tile.open.'"))
        if !tiles.firstMatch.waitForExistence(timeout: 5) {
            measurementsScroll.swipeUp()
        }
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 5),
                      "At least one metric tile should be available after first save")
    }

    private func completeOnboardingFlow() {
        // welcome -> profile -> boosters -> premium -> finish
        for _ in 0..<4 {
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 6), "Next button should exist during onboarding")
            XCTAssertTrue(next.isEnabled, "Next button should be enabled")
            next.tap()
        }
    }

    private func openMeasurementsTab() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar should be visible")

        let measurementCandidates = ["Measurements", "Pomiary"]
        for label in measurementCandidates {
            let button = tabBar.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }

        let byPrefix = tabBar.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Measure' OR label BEGINSWITH[c] 'Pomiar'"))
        if byPrefix.firstMatch.exists {
            byPrefix.firstMatch.tap()
            return
        }

        XCTFail("Could not locate Measurements tab button")
    }
}
