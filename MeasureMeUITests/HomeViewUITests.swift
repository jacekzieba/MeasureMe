import XCTest

final class HomeViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-uiTestForcePremium",              // force premium entitlement in UI
            "-uiTestBypassHealthSummaryGuards",// bypass availability/data guards for summary
            "-uiTestLongHealthInsight"         // use long test health insight text
        ]
        app.launch()
    }

    func testHealthAISummaryExpandsDynamically() {
        // Scroll to make sure Home is visible if needed
        // Assuming app starts on Home. If not, adjust navigation accordingly.

        let aiText = app.staticTexts["home.health.ai.text"]
        let exists = aiText.waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "AI health summary text should exist on Home")

        // Verify the long marker is present to ensure we got the long test content
        XCTAssertTrue(aiText.label.contains("UI_TEST_LONG_HEALTH_INSIGHT_MARKER"),
                      "Expected long health insight test content to be rendered")

        // Basic layout sanity: the text should not be truncated to one line; size should be greater than a small threshold
        // We can't directly read line count, but we can assert a minimum height or that the element is hittable and has a non-trivial frame.
        let frame = aiText.frame
        XCTAssertGreaterThan(frame.height, 40, "AI summary should span multiple lines (height > 40)")
        XCTAssertTrue(aiText.isHittable || frame.height > 40, "AI summary should be laid out and visible enough")
    }
}
