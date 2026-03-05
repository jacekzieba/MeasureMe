import XCTest

final class SinglePhotoSaveUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
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
        launchWithSingleAdd(extraLaunchArguments: ["-uiTestExpandMeasurements"])
        waitForSingleAddSheet()
        expandMeasurementsSection()

        let metricField = firstMetricField()
        XCTAssertTrue(metricField.waitForExistence(timeout: 5), "Measurements section should expand and show metric fields")
    }

    @MainActor
    func testMeasurementsFilledCounterUpdatesAfterInput() {
        launchWithSingleAdd(extraLaunchArguments: ["-uiTestExpandMeasurements"])
        waitForSingleAddSheet()
        expandMeasurementsSection()

        let metricField = firstMetricField()
        XCTAssertTrue(metricField.waitForExistence(timeout: 3), "A metric field should exist after expanding section")

        metricField.tap()
        metricField.typeText("82")

        let filledCount = app.staticTexts["addPhoto.measurements.filledCount"]
        XCTAssertTrue(filledCount.waitForExistence(timeout: 3), "Filled counter should appear after entering a measurement")
        XCTAssertTrue(filledCount.label.contains("1"), "Filled counter should show one completed metric")
    }
}

private extension SinglePhotoSaveUITests {
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Scrolls AddPhotoView's scroll view until `element` is hittable or `maxAttempts` reached.
    /// Uses a slow drag with a 0.5 s hold at the end so the scroll view is fully at rest
    /// (no momentum / deceleration) before we lift the finger — ensuring the subsequent tap
    /// is not absorbed by an active scroll-view gesture recogniser.
    func scrollUntilHittable(_ element: XCUIElement, maxAttempts: Int = 5) {
        let scrollView = app.scrollViews["addPhoto.scrollView"]
        var attempts = 0
        while !element.isHittable && attempts < maxAttempts {
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end   = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            // withVelocity: .slow  → minimal momentum after lift
            // thenHoldForDuration: 0.5  → scroll view settles fully before touch-up
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.5)
            attempts += 1
        }
        // Extra settle time after all scrolling is complete.
        // Also gives ScrollViewTouchDelayFixer's asyncAfter(0.3s) block time to run.
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Taps an element.
    /// `delaysContentTouches` is disabled for UI-test builds via `ScrollViewTouchDelayFixer`,
    /// so a plain `.tap()` is sufficient — the scroll view forwards the touch immediately.
    func tapElement(_ element: XCUIElement) {
        element.tap()
    }

    /// Taps via an absolute-coordinate `XCUICoordinate` derived from the element's midpoint.
    /// This routes through the app-level coordinate system rather than XCTest's element
    /// interaction system, which can behave differently inside UIScrollView hierarchies.
    func tapElementViaCoordinate(_ element: XCUIElement) {
        let frame = element.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let target = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        target.tap()
    }

    func firstMetricField() -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "addPhoto.metricField.")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    func expandMeasurementsSection() {
        // Let navigation push animation fully complete before interacting.
        Thread.sleep(forTimeInterval: 0.6)

        let toggle = app.buttons["addPhoto.measurements.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Measurements section toggle should exist")
        scrollUntilHittable(toggle, maxAttempts: 6)

        let content = element("addPhoto.measurements.content")
        let metricField = firstMetricField()

        for _ in 0..<5 where !(content.exists || metricField.exists) {
            if toggle.isHittable {
                tapElement(toggle)
            } else {
                tapElementViaCoordinate(toggle)
            }

            if content.waitForExistence(timeout: 0.9) || metricField.waitForExistence(timeout: 0.9) {
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertTrue(
            content.exists || metricField.exists,
            "Measurements section should expand and expose content"
        )
    }

    func launchWithSingleAdd(extraLaunchArguments: [String] = []) {
        app.launchArguments = ["-uiTestMode", "-uiTestOpenSingleAdd"] + extraLaunchArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        tapPhotosTab()
    }

    func tapPhotosTab() {
        let tab = app.tabBars.buttons["tab.photos"]
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
