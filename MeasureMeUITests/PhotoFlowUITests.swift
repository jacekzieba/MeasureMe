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
        tapTab(named: "tab.photos")

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
        // Wejdź w tryb selekcji. Jeśli jesteśmy już w selekcji po poprzedniej iteracji,
        // przycisk toggle może być zastąpiony przez "Done".
        let selectMode = app.descendants(matching: .any)["photos.select.mode.toggle"].firstMatch
        if selectMode.waitForExistence(timeout: 5) {
            selectMode.tap()
        } else {
            let selectionDone = app.descendants(matching: .any)["photos.selection.done"].firstMatch
            XCTAssertTrue(selectionDone.waitForExistence(timeout: 2), "Expected select mode toggle or selection done state.")
        }

        // Hook UI test: zaznacza pierwsze 2 zdjęcia z bazy
        let selectTwoHook = app.descendants(matching: .any)["photos.compare.selectTwoHook"].firstMatch
        XCTAssertTrue(selectTwoHook.waitForExistence(timeout: 3), "Expected UI test select-two hook.")
        selectTwoHook.tap()

        // Teraz 2 zdjęcia zaznaczone → przycisk Compare widoczny
        let openCompare = app.descendants(matching: .any)["photos.compare.open"].firstMatch
        XCTAssertTrue(openCompare.waitForExistence(timeout: 5), "Expected compare action button.")
        openCompare.tap()

        XCTAssertTrue(app.descendants(matching: .any)["photos.compare.done"].firstMatch.waitForExistence(timeout: 5), "Expected compare sheet.")
    }

    private func tapExportAndHandleSystemPromptIfNeeded() {
        let exportButton = app.descendants(matching: .any)["photos.compare.export"].firstMatch
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
        let doneButton = app.descendants(matching: .any)["photos.compare.done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Expected Done button.")
        doneButton.tap()
    }
}
