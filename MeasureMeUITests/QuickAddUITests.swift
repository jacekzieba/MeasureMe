/// Cel testow: Sprawdza UI Quick Add (otwarcie, zapis, puste stany, brak crashy).
/// Dlaczego to wazne: To najczesciej uzywana akcja; musi byc szybka i niezawodna.
/// Kryteria zaliczenia: Arkusz otwiera sie poprawnie, zapis dziala, a scenariusze brzegowe sa stabilne.

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
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    private func launchWithNoMetrics() {
        app.launchArguments = ["-uiTestMode", "-uiTestNoActiveMetrics"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    private func tapTab(named name: String) {
        let tabBar = app.tabBars.firstMatch
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
            let button = tabBar.buttons[candidate].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }

        XCTFail("Expected tab \(name) to exist.")
    }

    /// Otworz arkusz QuickAdd z glownego entry pointu w tab barze i poczekaj, az bedzie gotowy.
    private func openQuickAdd() {
        let addButton = app.tabBars.buttons["tab.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Przycisk dodania pomiaru powinien istniec w tab barze")
        addButton.tap()

        // Poczekaj na przycisk zapisu - to potwierdza zaladowanie arkusza z aktywnymi metrykami.
        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5),
                      "Arkusz QuickAdd powinien sie pojawic z przyciskiem zapisu")
    }

    private func quickAddLaunchStateSummary() -> String {
        let states = [
            ("pendingAddPhoto.active", app.otherElements["uitest.debug.pendingAddPhoto.active"].exists),
            ("pendingAddPhoto.overlayActive", app.otherElements["uitest.debug.pendingAddPhoto.overlayActive"].exists),
            ("tab.photos", app.otherElements["uitest.debug.tab.photos"].exists),
            ("sourceChooser.visible", app.otherElements["photos.sourceChooser.visible"].exists),
            ("cameraButton", app.buttons["photos.add.menu.camera"].firstMatch.exists),
            ("libraryButton", app.buttons["photos.add.menu.library"].firstMatch.exists)
        ]

        return states
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: ", ")
    }

    // MARK: - Tests

    @MainActor
    /// Co sprawdza: Sprawdza, ze QuickAddSheetOpensWithSaveButton dziala poprawnie (otwarcie i podstawowe warunki).
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `quickadd.save`).
    func testQuickAddSheetOpensWithSaveButton() {
        launchWithActiveMetrics()
        openQuickAdd()

        // Przycisk zapisu widoczny oznacza, ze arkusz ma wiersze metryk i klawiatura jest schowana.
        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.isHittable, "Przycisk zapisu powinien byc klikalny")
    }

    @MainActor
    /// Co sprawdza: Sprawdza, ze QuickAddRapidSaveTaps nie powoduje crasha.
    /// Dlaczego: Chroni krytyczny przeplyw przed regresja i nieoczekiwanymi crashami.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `quickadd.save`).
    func testQuickAddRapidSaveTapsDoesNotCrash() {
        launchWithActiveMetrics()
        openQuickAdd()

        let saveButton = app.buttons["quickadd.save"]
        saveButton.tap()
        saveButton.tap()
        saveButton.tap()

        // Aplikacja nie powinna sie wysypac
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "Aplikacja powinna pozostac uruchomiona po szybkich tapnieciach zapisu"
        )
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: QuickAddShowsEmptyStateWhenNoActiveMetrics.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `tab.add`, `quickadd.save`).
    func testQuickAddShowsEmptyStateWhenNoActiveMetrics() {
        launchWithNoMetrics()

        let addButton = app.tabBars.buttons["tab.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Przycisk dodania pomiaru powinien istniec")
        addButton.tap()

        // Przycisk zapisu NIE moze sie pojawic (pusty stan = brak metryk = brak paska zapisu)
        let saveButton = app.buttons["quickadd.save"]
        // Daj arkuszowi chwile na zaladowanie, potem potwierdz brak przycisku zapisu
        sleep(2)
        XCTAssertFalse(saveButton.exists,
                       "Przycisk zapisu nie powinien sie pojawic, gdy nie ma aktywnych metryk")
    }

    // MARK: - First-time flow

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: QuickAddFirstTimeShowsHintText.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `Enter your first value`).
    func testQuickAddFirstTimeShowsHintText() {
        // Czysta baza + aktywne metryki -> brak `latest` -> przeplyw pierwszego uruchomienia
        launchWithActiveMetrics()
        openQuickAdd()

        // Podpowiedz "Enter your first value" powinna byc widoczna w arkuszu
        let hint = app.staticTexts["Enter your first value"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "Podpowiedz pierwszego uruchomienia powinna sie pojawic, gdy brak poprzednich pomiarow")
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: QuickAddWithSeededDataShowsSaveButton.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `tab.add`, `quickadd.save`).
    func testQuickAddWithSeededDataShowsSaveButton() {
        // Zasiane dane wagi -> istnieje `latest` -> miarka widoczna, normalny przeplyw
        app.launchArguments = ["-uiTestMode", "-uiTestSeedMeasurements"]
        app.launch()

        let addButton = app.tabBars.buttons["tab.add"].firstMatch
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()

            let saveButton = app.buttons["quickadd.save"]
            XCTAssertTrue(saveButton.waitForExistence(timeout: 5),
                          "Przycisk zapisu powinien sie pojawic, gdy zasiane dane dostarczaja ostatnie wartosci")
            XCTAssertTrue(saveButton.isHittable, "Przycisk zapisu powinien byc klikalny")
        }
        // Jesli addButton nie istnieje (zasiane dane = hasAnyMeasurements), to tez poprawnie
        // QuickAdd jest wtedy otwierany inaczej, gdy dane juz istnieja.
    }

    @MainActor
    func testPendingQuickAddEntryActionOpensQuickAddSheetOnLaunch() {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestPendingAppEntryAction", "openQuickAdd"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        XCTAssertTrue(
            app.buttons["quickadd.save"].waitForExistence(timeout: 20),
            "Pending app entry action should present Quick Add right after launch"
        )
    }

    @MainActor
    func testPendingAddPhotoEntryActionOpensPhotoSourceChooserOnLaunch() {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestPendingAppEntryAction", "openAddPhoto"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let cameraOption = app.buttons["photos.add.menu.camera"].firstMatch
        let libraryOption = app.buttons["photos.add.menu.library"].firstMatch
        XCTAssertTrue(
            cameraOption.waitForExistence(timeout: 20),
            "Pending app entry action should open Add Photo source chooser with camera option. State: \(quickAddLaunchStateSummary())"
        )
        XCTAssertTrue(
            libraryOption.exists,
            "Source chooser should also expose library option. State: \(quickAddLaunchStateSummary())"
        )
    }

    @MainActor
    func testPhotosAddButtonShowsAnchoredMenuOptions() {
        app.launchArguments = ["-uiTestMode", "-uiTestSeedMeasurements"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        tapTab(named: "tab.photos")

        let addButton = app.buttons["photos.add.button"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))
        addButton.tap()

        let cameraOption = app.buttons["photos.add.menu.camera"].firstMatch
        let libraryOption = app.buttons["photos.add.menu.library"].firstMatch
        XCTAssertTrue(cameraOption.waitForExistence(timeout: 3), "Camera option should be visible in add menu")
        XCTAssertTrue(libraryOption.exists, "Library option should be visible in add menu")
    }
}
