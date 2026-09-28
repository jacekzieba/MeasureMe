import XCTest

final class PhotoFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-uiTestForcePremium", "-uiTestSeedPhotos", "24"]
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

        allowPhotoPermissionAlerts()
        XCTAssertFalse(
            XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
            "No system alert may outlive this test."
        )
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func tapTab(named name: String) {
        let tabBar = app.appTabBar
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "Expected tab bar to exist.")

        let localizedCandidates: [String]
        switch name {
        case "tab.home":
            localizedCandidates = ["tab.home", "Home", "Start", "Dom", "Strona główna"]
        case "tab.measurements":
            localizedCandidates = ["tab.measurements", "Measurements", "Pomiary"]
        case "tab.photos":
            localizedCandidates = ["tab.photos", "Photos", "Zdjęcia", "Zdjecia"]
        case "tab.settings":
            localizedCandidates = ["tab.settings", "Settings", "Ustawienia"]
        default:
            localizedCandidates = [name]
        }

        for candidate in localizedCandidates {
            let button = tabBar.buttons[candidate]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }

        XCTFail("Expected tab \(name) to exist.")
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

        // Export asks for add-only access, then full access for the album.
        allowPhotoPermissionAlerts()
    }

    /// Answers every photo-library permission alert SpringBoard shows. An alert
    /// left on screen outlives this test and swallows every tap in the suites
    /// that run after it, so none may remain. Button labels depend on the
    /// simulator language ("Allow", "Pozwól", …), so the button is picked by
    /// position: the second one allows, both in the add-only alert
    /// (Don't Allow, Allow) and in the full-access one
    /// (Select Photos, Allow Full Access, Keep Add Only). The full-access alert
    /// replaces the add-only one right away, so each pass answers whichever
    /// alert is showing; the test's closing assertion catches one that stays.
    private func allowPhotoPermissionAlerts() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        var timeout: TimeInterval = 3
        for _ in 0..<3 {
            guard alert.waitForExistence(timeout: timeout) else { return }
            alert.buttons.element(boundBy: 1).tap()
            timeout = 2
        }
    }

    private func closeCompareSheet() {
        let exportAlertOK = app.buttons["OK"].firstMatch
        if exportAlertOK.waitForExistence(timeout: 2) {
            exportAlertOK.tap()
        }

        let doneButton = app.descendants(matching: .any)["photos.compare.done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Expected Done button.")
        doneButton.tap()
    }
}
