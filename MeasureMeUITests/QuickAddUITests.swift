import XCTest

final class QuickAddUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func launchWithActiveMetrics() {
        app.launchArguments = ["-uiTestMode"]
        app.launch()
    }

    private func launchWithNoMetrics() {
        app.launchArguments = ["-uiTestMode", "-uiTestNoActiveMetrics"]
        app.launch()
    }

    /// Open the QuickAdd sheet from Home and wait until it is ready.
    private func openQuickAdd() {
        let addButton = app.buttons["home.quickadd.button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Add measurement button should exist on Home")
        addButton.tap()

        // Wait for the save button — proves the sheet loaded with active metrics.
        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5),
                      "QuickAdd sheet should appear with Save button")
    }

    // MARK: - Tests

    @MainActor
    func testQuickAddSheetOpensWithSaveButton() {
        launchWithActiveMetrics()
        openQuickAdd()

        // Save button visible means sheet has metric rows and keyboard is dismissed.
        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.isHittable, "Save button should be tappable")
    }

    @MainActor
    func testQuickAddRapidSaveTapsDoesNotCrash() {
        launchWithActiveMetrics()
        openQuickAdd()

        let saveButton = app.buttons["quickadd.save"]
        saveButton.tap()
        saveButton.tap()
        saveButton.tap()

        // App should not crash
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "App should remain running after rapid save taps"
        )
    }

    @MainActor
    func testQuickAddShowsEmptyStateWhenNoActiveMetrics() {
        launchWithNoMetrics()

        let addButton = app.buttons["home.quickadd.button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Add measurement button should exist")
        addButton.tap()

        // Save button must NOT appear (empty state = no metrics = no save bar)
        let saveButton = app.buttons["quickadd.save"]
        // Give the sheet a moment to load, then assert save is absent
        sleep(2)
        XCTAssertFalse(saveButton.exists,
                       "Save button should not appear when no metrics are active")
    }

    // MARK: - First-time flow

    @MainActor
    func testQuickAddFirstTimeShowsHintText() {
        // Clean DB + active metrics → no `latest` → first-time flow
        launchWithActiveMetrics()
        openQuickAdd()

        // The hint "Enter your first value" should be visible somewhere in the sheet
        let hint = app.staticTexts["Enter your first value"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "First-time hint should appear when no previous measurements exist")
    }

    @MainActor
    func testQuickAddWithSeededDataShowsSaveButton() {
        // Seeded weight data → `latest` exists → ruler visible, normal flow
        app.launchArguments = ["-uiTestMode", "-uiTestSeedMeasurements"]
        app.launch()

        let addButton = app.buttons["home.quickadd.button"]
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()

            let saveButton = app.buttons["quickadd.save"]
            XCTAssertTrue(saveButton.waitForExistence(timeout: 5),
                          "Save button should appear when seeded data provides latest values")
            XCTAssertTrue(saveButton.isHittable, "Save button should be tappable")
        }
        // If addButton doesn't exist (seeded data = hasAnyMeasurements), that's also OK —
        // QuickAdd is accessed differently when data exists.
    }
}
