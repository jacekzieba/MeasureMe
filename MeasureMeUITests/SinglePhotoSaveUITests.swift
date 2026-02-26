import XCTest

final class SinglePhotoSaveUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testSingleSaveDismissesAndReturnsToPhotos() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        let saveButton = app.buttons["addPhoto.saveButton"]
        saveButton.tap()

        let saveGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: saveButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [saveGone], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["photos.add.button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSingleSaveShowsPhotoInGridImmediately() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        app.buttons["addPhoto.saveButton"].tap()

        let gridItems = app.buttons.matching(identifier: "photos.grid.item")
        let appears = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 1"),
            object: gridItems
        )
        XCTAssertEqual(XCTWaiter.wait(for: [appears], timeout: 10), .completed)
    }

    @MainActor
    func testSingleSaveDoubleTapSaveDoesNotDuplicate() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        let saveButton = app.buttons["addPhoto.saveButton"]
        saveButton.tap()
        if saveButton.exists && saveButton.isEnabled {
            saveButton.tap()
        }

        let gridItems = app.buttons.matching(identifier: "photos.grid.item")
        let exactlyOne = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 1"),
            object: gridItems
        )
        XCTAssertEqual(XCTWaiter.wait(for: [exactlyOne], timeout: 12), .completed)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor
    func testMeasurementsSectionIsCollapsedByDefault() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        let toggle = app.buttons["addPhoto.measurements.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Measurements section toggle should exist")

        let content = element("addPhoto.measurements.content")
        XCTAssertFalse(content.exists, "Measurements section should be collapsed initially")
    }

    @MainActor
    func testMeasurementsSectionExpandsAfterTap() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        let toggle = app.buttons["addPhoto.measurements.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Measurements section toggle should exist")
        toggle.tap()

        let content = element("addPhoto.measurements.content")
        XCTAssertTrue(content.waitForExistence(timeout: 3), "Measurements section content should expand")
    }

    @MainActor
    func testMeasurementsFilledCounterUpdatesAfterInput() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        let toggle = app.buttons["addPhoto.measurements.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Measurements section toggle should exist")
        toggle.tap()

        let weightField = app.textFields["addPhoto.metricField.weight"]
        if !weightField.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(weightField.waitForExistence(timeout: 3), "Weight metric field should exist after expanding section")

        weightField.tap()
        weightField.typeText("82")

        let filledCount = app.staticTexts["addPhoto.measurements.filledCount"]
        XCTAssertTrue(filledCount.waitForExistence(timeout: 3), "Filled counter should appear after entering a measurement")
        XCTAssertTrue(filledCount.label.contains("1"), "Filled counter should show one completed metric")
    }
}

private extension SinglePhotoSaveUITests {
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func launchWithSingleAdd() {
        app.launchArguments = ["-uiTestMode", "-uiTestOpenSingleAdd"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        tapPhotosTab()
    }

    func tapPhotosTab() {
        let tab = app.tabBars.buttons["Photos"]
        XCTAssertTrue(tab.waitForExistence(timeout: 6), "Tab 'Photos' should exist")
        tab.tap()
    }

    func waitForSingleAddSheet(timeout: TimeInterval = 5) {
        let saveButton = app.buttons["addPhoto.saveButton"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: timeout),
            "AddPhotoView should open via -uiTestOpenSingleAdd"
        )

        let cancelButton = app.buttons["addPhoto.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2), "Cancel button should exist")
    }
}
