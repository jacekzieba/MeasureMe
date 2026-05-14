import XCTest

final class MeasureMeWatchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - App Launch

    @MainActor
    func testAppLaunchesSuccessfully() throws {
        // On simulator with debug data seeder, app should show metric list
        // Verify the app is running and has content
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Metric List

    @MainActor
    func testMetricListShowsMetrics() throws {
        // With debug data, we should see Weight, Body Fat, Waist
        let weightText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'kg' OR label CONTAINS[c] 'lb' OR label CONTAINS[c] 'Waga' OR label CONTAINS[c] 'Weight'"))
        XCTAssertTrue(weightText.count > 0, "Should display at least one metric")
    }

    // MARK: - Navigation to Quick Add

    @MainActor
    func testNavigateToQuickAdd() throws {
        // Tap the + button in toolbar
        let addButton = app.buttons["watch.openQuickAdd"].firstMatch
        if addButton.waitForExistence(timeout: 3) {
            addButton.tap()

            // Should show Save button on Quick Add screen
            let quickAddView = app.collectionViews["watch.quickAdd.view"].firstMatch
            XCTAssertTrue(quickAddView.waitForExistence(timeout: 10), "Quick Add should open")
            quickAddView.swipeUp()

            let saveButton = app.buttons["watch.quickAdd.save"].firstMatch
            XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Quick Add should show Save button")
        }
    }

    // MARK: - Metric Detail

    @MainActor
    func testNavigateToMetricDetail() throws {
        // Tap on the first metric in the list
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            firstCell.tap()

            // Detail view should show "Recent" or "Ostatnie" label
            let recentLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Recent' OR label CONTAINS[c] 'Ostatnie' OR label CONTAINS[c] 'Trend'")).firstMatch
            XCTAssertTrue(recentLabel.waitForExistence(timeout: 3), "Detail view should show recent entries section")
        }
    }

    // MARK: - Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
