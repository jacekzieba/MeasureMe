import XCTest

final class PhotoFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-uiTestSeedPhotos", "24"]
    }

    @MainActor
    func testPhotoCompareExportLoopDoesNotCrash() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        tapTab(named: "Photos")

        for _ in 0..<3 {
            openCompareWithHook()
            tapExportAndHandleSystemPromptIfNeeded()
            closeCompareSheet()
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func tapTab(named name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected tab \(name) to exist.")
        button.tap()
    }

    private func openCompareWithHook() {
        let compareMode = app.buttons["photos.compare.mode.toggle"]
        XCTAssertTrue(compareMode.waitForExistence(timeout: 5), "Expected compare mode toggle.")
        compareMode.tap()

        let openCompare = app.buttons["photos.compare.open"]
        if !openCompare.waitForExistence(timeout: 2) {
            compareMode.tap()
        }
        XCTAssertTrue(openCompare.waitForExistence(timeout: 5), "Expected compare action button.")
        openCompare.tap()

        XCTAssertTrue(app.buttons["photos.compare.done"].waitForExistence(timeout: 5), "Expected compare sheet.")
    }

    private func tapExportAndHandleSystemPromptIfNeeded() {
        let exportButton = app.buttons["photos.compare.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Expected export button.")
        exportButton.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permissionButtons = [
            "Allow Full Access", "Allow", "OK",
            "Zezwól na pełny dostęp", "Zezwól", "Dobrze"
        ]
        for label in permissionButtons {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                break
            }
        }
    }

    private func closeCompareSheet() {
        let doneButton = app.buttons["photos.compare.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Expected Done button.")
        doneButton.tap()
    }
}
