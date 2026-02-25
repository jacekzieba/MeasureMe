import XCTest

final class SinglePhotoPendingSaveUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testSaveDismissesImmediatelyAndShowsPendingPlaceholder() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        let saveButton = app.buttons["addPhoto.saveButton"]
        saveButton.tap()

        let saveGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: saveButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [saveGone], timeout: 3), .completed)

        let pending = element("photos.grid.pending.item")
        XCTAssertTrue(pending.waitForExistence(timeout: 4))
    }

    @MainActor
    func testPendingProgressUpdatesOverTime() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        app.buttons["addPhoto.saveButton"].tap()

        let pending = element("photos.grid.pending.item")
        XCTAssertTrue(pending.waitForExistence(timeout: 4))

        let first = extractPercentage(from: pending.value as? String)
        sleep(1)
        let second = extractPercentage(from: pending.value as? String)
        XCTAssertGreaterThanOrEqual(second, first)
    }

    @MainActor
    func testCompletionReplacesPendingWithPersistedPhoto() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        app.buttons["addPhoto.saveButton"].tap()

        let pending = element("photos.grid.pending.item")
        XCTAssertTrue(pending.waitForExistence(timeout: 4))

        let pendingGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: pending
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pendingGone], timeout: 12), .completed)

        XCTAssertTrue(app.buttons["photos.grid.item"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testFailureRemovesPendingAndShowsToast() {
        launchWithSingleAdd(extraArgs: ["-uiTestPendingForceFailure"])
        waitForSingleAddSheet()

        app.buttons["addPhoto.saveButton"].tap()

        let pending = element("photos.grid.pending.item")
        XCTAssertTrue(pending.waitForExistence(timeout: 4))

        let toast = element("photos.pending.failureToast")
        XCTAssertTrue(toast.waitForExistence(timeout: 6))

        let pendingGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: pending
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pendingGone], timeout: 8), .completed)
    }

    @MainActor
    func testPendingAppearsOnHomeWhileSaving() {
        launchWithSingleAdd()
        waitForSingleAddSheet()

        app.buttons["addPhoto.saveButton"].tap()

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 4))
        homeTab.tap()

        let homePending = element("home.lastPhotos.pending.item")
        let appearedDuringScroll = revealElementByScrollingHome(homePending, maxSwipes: 4)
        XCTAssertTrue(appearedDuringScroll || homePending.waitForExistence(timeout: 2))
    }
}

private extension SinglePhotoPendingSaveUITests {
    func launchWithSingleAdd(extraArgs: [String] = []) {
        app.launchArguments = ["-uiTestMode", "-uiTestOpenSingleAdd", "-uiTestPendingSlow"] + extraArgs
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
    }

    func extractPercentage(from value: String?) -> Int {
        guard let value else { return 0 }
        let digits = value.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func revealElementByScrollingHome(_ element: XCUIElement, maxSwipes: Int) -> Bool {
        let scrollView = app.scrollViews.firstMatch
        if element.exists { return true }
        for _ in 0..<maxSwipes where !element.exists {
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
            if element.exists { return true }
        }
        return element.exists
    }
}
