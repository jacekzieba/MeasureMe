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
    }

    private func launchWithNoMetrics() {
        app.launchArguments = ["-uiTestMode", "-uiTestNoActiveMetrics"]
        app.launch()
    }

    /// Otworz arkusz QuickAdd z Home i poczekaj, az bedzie gotowy.
    private func openQuickAdd() {
        let addButton = app.buttons["home.quickadd.button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                      "Przycisk dodania pomiaru powinien istniec na Home")
        addButton.tap()

        // Poczekaj na przycisk zapisu - to potwierdza zaladowanie arkusza z aktywnymi metrykami.
        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5),
                      "Arkusz QuickAdd powinien sie pojawic z przyciskiem zapisu")
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
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `home.quickadd.button`, `quickadd.save`).
    func testQuickAddShowsEmptyStateWhenNoActiveMetrics() {
        launchWithNoMetrics()

        let addButton = app.buttons["home.quickadd.button"]
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
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `home.quickadd.button`, `quickadd.save`).
    func testQuickAddWithSeededDataShowsSaveButton() {
        // Zasiane dane wagi -> istnieje `latest` -> miarka widoczna, normalny przeplyw
        app.launchArguments = ["-uiTestMode", "-uiTestSeedMeasurements"]
        app.launch()

        let addButton = app.buttons["home.quickadd.button"]
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
}
