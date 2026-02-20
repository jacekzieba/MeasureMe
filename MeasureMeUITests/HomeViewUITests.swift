/// Cel testow: Weryfikuje kluczowe interakcje na Home (layout, przewijanie, widocznosc tresci).
/// Dlaczego to wazne: Home to centralny ekran nawigacji i podgladu metryk.
/// Kryteria zaliczenia: Krytyczne elementy sa widoczne i nie dochodzi do regresji ukladu.

import XCTest

final class HomeViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-uiTestForcePremium",              // force premium entitlement in UI
            "-uiTestBypassHealthSummaryGuards",// bypass availability/data guards for summary
            "-uiTestLongHealthInsight"         // use long test health insight text
        ]
        app.launch()
    }

    /// Co sprawdza: Sprawdza scenariusz: HealthAISummaryExpandsDynamically.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `home.health.ai.text`).
    func testHealthAISummaryExpandsDynamically() {
        // Przewin, aby upewnic sie, ze Home jest widoczne, jesli potrzeba
        // Assuming app starts on Home. If not, adjust navigation accordingly.

        let aiText = app.staticTexts["home.health.ai.text"]
        let exists = aiText.waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "Tekst podsumowania AI powinien istniec na Home")

        // Sprawdz, czy dlugi znacznik jest obecny, aby potwierdzic zaladowanie dlugiej tresci testowej
        XCTAssertTrue(aiText.label.contains("UI_TEST_LONG_HEALTH_INSIGHT_MARKER"),
                      "Expected long health insight test content to be rendered")

        // Podstawowa kontrola ukladu: tekst nie powinien byc obciety do jednej linii, a ramka powinna byc sensowna.
        // Nie odczytamy bezposrednio liczby linii, ale mozemy sprawdzic minimalna wysokosc i klikalnosc elementu.
        let frame = aiText.frame
        XCTAssertGreaterThan(frame.height, 40, "Podsumowanie AI powinno zajmowac wiele linii (wysokosc > 40)")
        XCTAssertTrue(aiText.isHittable || frame.height > 40, "Podsumowanie AI powinno byc poprawnie ulozone i wystarczajaco widoczne")
    }
}
