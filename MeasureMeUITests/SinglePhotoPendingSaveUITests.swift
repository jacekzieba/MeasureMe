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
        let pendingInPhotos = element("photos.grid.pending.item")
        XCTAssertTrue(pendingInPhotos.waitForExistence(timeout: 4), "Pending placeholder should appear on Photos right after save")

        tapTab(identifier: "tab.home", fallbackLabels: ["Home", "Główna"])

        let homePending = element("home.lastPhotos.pending.item")
        let appearedDuringScroll = revealElementByScrollingHome(homePending, maxSwipes: 4)
        let homeRecentPhoto = element("home.recentPhotos.item.0")
        let pendingOrSavedVisible = appearedDuringScroll
            || homePending.waitForExistence(timeout: 2)
            || homeRecentPhoto.waitForExistence(timeout: 2)
        XCTAssertTrue(pendingOrSavedVisible, "Home should show pending placeholder or already-saved recent photo")
    }
}

private extension SinglePhotoPendingSaveUITests {
    func launchWithSingleAdd(extraArgs: [String] = []) {
        app.launchArguments = [
            "-uiTestMode",
            "-auditCapture",
            "-auditRoute", "photos",
            "-uiTestOpenSingleAdd",
            "-uiTestPendingSlow"
        ] + extraArgs
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
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

    func tapTab(identifier: String, fallbackLabels: [String]) {
        for _ in 0..<6 {
            let tab = app.buttons[identifier].firstMatch
            if tab.exists && tab.isHittable {
                tab.tap()
                return
            }

            for label in fallbackLabels {
                let candidate = app.buttons[label].firstMatch
                if candidate.exists && candidate.isHittable {
                    candidate.tap()
                    return
                }
            }

            app.swipeDown()
        }

        XCTFail("Tab should exist: \(identifier)")
    }
}
