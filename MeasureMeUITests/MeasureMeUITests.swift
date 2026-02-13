import XCTest

final class MeasureMeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSmokeAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testHealthSyncDeniedRollsBackToggleAndShowsError() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestHealthAuthDenied"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()

        let toggle = app.switches["settings.health.sync.toggle"]
        if !toggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        toggle.tap()

        let errorLabel = app.staticTexts["settings.health.sync.error"]
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(isSwitchOff(toggle))
    }

    @MainActor
    func testLongInsightTextExpandsTileHeight() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForcePremium",
            "-uiTestForceAIAvailable",
            "-uiTestLongInsight",
            "-uiTestSeedMeasurements"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Measurements"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Measurements"].tap()

        let insightText = app.staticTexts["insight.card.text.compact"].firstMatch
        XCTAssertTrue(insightText.waitForExistence(timeout: 8))
        XCTAssertTrue(insightText.label.contains("UI_TEST_LONG_INSIGHT_MARKER"))
        XCTAssertGreaterThan(insightText.frame.height, 30)

        let openWeightDetail = app.buttons["metric.tile.open.weight"]
        if openWeightDetail.waitForExistence(timeout: 5) {
            openWeightDetail.tap()
            let detailedInsight = app.staticTexts["insight.card.text.detail"].firstMatch
            XCTAssertTrue(detailedInsight.waitForExistence(timeout: 8))
            XCTAssertGreaterThan(detailedInsight.frame.height, 30)
        } else {
            XCTFail("Expected weight detail navigation button.")
        }
    }

    private func isSwitchOff(_ element: XCUIElement) -> Bool {
        guard let value = element.value as? String else { return false }
        return value == "0" || value.lowercased() == "off"
    }
}
