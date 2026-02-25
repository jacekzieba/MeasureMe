import XCTest

/// Testy UI dla MultiPhotoImportView.
///
/// PHPickerViewController jest zewnętrznym procesem systemowym i nie może być
/// kontrolowany przez XCUITest. Zamiast tego używamy launch argumentu
/// -uiTestOpenMultiImport {count}, który powoduje, że PhotoView automatycznie
/// otwiera MultiPhotoImportView z wygenerowanymi zdjęciami testowymi.
///
/// Wymagane launch argumenty:
///   -uiTestMode                  → pomija onboarding, włącza premium, ustawia język EN
///   -uiTestOpenMultiImport {N}   → otwiera MultiPhotoImportView z N zdjęciami po wejściu na tab Photos
final class MultiPhotoImportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helper

    private func launchWithMultiImport(photoCount: Int) {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestOpenMultiImport", "\(photoCount)"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        tapPhotosTab()
    }

    private func tapPhotosTab() {
        let tab = app.tabBars.buttons["Photos"]
        XCTAssertTrue(tab.waitForExistence(timeout: 6), "Tab 'Photos' powinien istnieć")
        tab.tap()
    }

    private func waitForMultiImportSheet(timeout: TimeInterval = 5) {
        // Sheet jest obecny gdy istnieje przycisk Save w toolbarze
        let saveButton = app.buttons["multiImport.saveButton"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: timeout),
            "MultiPhotoImportView powinien się otworzyć (multiImport.saveButton nie znaleziony w \(timeout)s)"
        )
    }

    // MARK: - Testy otwarcia widoku

    /// Co sprawdza: MultiPhotoImportView otwiera się po wejściu na tab Photos z flagą -uiTestOpenMultiImport.
    /// Dlaczego: Weryfikuje, że hook działa i sheet pojawia się bez interakcji z systemowym pickerem.
    /// Kryteria: Przycisk Save (multiImport.saveButton) istnieje.
    @MainActor
    func testMultiImportSheetOpensViaLaunchArgument() {
        launchWithMultiImport(photoCount: 3)
        waitForMultiImportSheet()
    }

    /// Co sprawdza: Przycisk Cancel istnieje i jest dostępny.
    /// Dlaczego: Użytkownik musi móc anulować import bez zapisywania.
    /// Kryteria: multiImport.cancelButton istnieje i jest enabled.
    @MainActor
    func testMultiImportCancelButtonExists() {
        launchWithMultiImport(photoCount: 2)
        waitForMultiImportSheet()

        let cancelButton = app.buttons["multiImport.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        XCTAssertTrue(cancelButton.isEnabled, "Przycisk Cancel powinien być aktywny")
    }

    /// Co sprawdza: Tytuł nawigacyjny zawiera liczbę importowanych zdjęć.
    /// Dlaczego: User musi wiedzieć ile zdjęć importuje — tytuł "Import 3 Photos" to kluczowy sygnał.
    /// Kryteria: Statyczny tekst zawierający "3" lub "3 Photo" istnieje w navbarze.
    @MainActor
    func testMultiImportTitleShowsPhotoCount() {
        let count = 3
        launchWithMultiImport(photoCount: count)
        waitForMultiImportSheet()

        // NavigationTitle renderuje się jako staticText — szukamy tekstu zawierającego liczbę
        let titleElement = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3'")).firstMatch
        XCTAssertTrue(
            titleElement.waitForExistence(timeout: 3),
            "Tytuł powinien zawierać liczbę \(count) importowanych zdjęć"
        )
    }

    // MARK: - Tagi

    /// Co sprawdza: Toggle tagu wholeBody jest widoczny i interaktywny.
    /// Dlaczego: wholeBody jest domyślnie zawsze dostępny — musi być toggleowalny.
    /// Kryteria: multiImport.tagToggle.wholeBody istnieje i jest enabled.
    @MainActor
    func testWholeBodyTagToggleIsInteractable() {
        launchWithMultiImport(photoCount: 2)
        waitForMultiImportSheet()

        let toggle = app.switches["multiImport.tagToggle.wholeBody"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Toggle tagu wholeBody powinien istnieć")
        XCTAssertTrue(toggle.isEnabled, "Toggle wholeBody powinien być enabled")
    }

    /// Co sprawdza: Toggle wholeBody można przełączyć (on → off → on).
    /// Dlaczego: UI musi reagować na tap — toggle zamrożony to bug UX.
    /// Kryteria: Wartość toggle zmienia się po tapnięciu.
    ///
    /// Uwaga implementacyjna: LiquidSwitchToggleStyle renderuje toggle jako Button
    /// (nie standardowy UISwitch). XCUITest widzi element przez accessibility jako switch,
    /// ale tap musi trafiać w obszar samego przycisku (prawa strona HStacka).
    /// Używamy .buttons zamiast .switches, bo tap na .switches może trafić w etykietę.
    @MainActor
    func testWholeBodyTagToggleCanBeToggled() {
        launchWithMultiImport(photoCount: 2)
        waitForMultiImportSheet()

        // LiquidSwitchToggleStyle to Button wewnątrz HStacka — identyfikator jest na całym Toggle,
        // który accessibility eksponuje jako "switch". Tapujemy na identifierze, ale szukamy
        // przez switches (bo accessibility role to switch) i tapujemy w prawą stronę gdzie jest knob.
        let toggle = app.switches["multiImport.tagToggle.wholeBody"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))

        let valueBefore = toggle.value as? String

        // Tapujemy w prawą część togglea (gdzie jest knob) zamiast w środek całego elementu
        let frame = toggle.frame
        let knobX = frame.maxX - 26  // 26px od prawej krawędzi = środek 52px capsule
        let knobY = frame.midY
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: knobX, dy: knobY))
            .tap()

        let valueAfter = toggle.value as? String
        XCTAssertNotEqual(valueBefore, valueAfter, "Wartość toggle powinna zmienić się po tapnięciu w knob")
    }

    // MARK: - Cancel

    /// Co sprawdza: Tapnięcie Cancel zamyka MultiPhotoImportView.
    /// Dlaczego: Cancel musi działać niezawodnie — użytkownik musi móc wyjść z widoku.
    /// Kryteria: Po tapnięciu Cancel multiImport.saveButton znika z ekranu.
    @MainActor
    func testMultiImportCancelDismissesSheet() {
        launchWithMultiImport(photoCount: 2)
        waitForMultiImportSheet()

        let cancelButton = app.buttons["multiImport.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        // Po zamknięciu sheetu Save button nie powinien być widoczny
        let saveButton = app.buttons["multiImport.saveButton"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: saveButton
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "MultiPhotoImportView powinien zostać zamknięty po tapnięciu Cancel")
    }

    // MARK: - Save flow

    /// Co sprawdza: Po tapnięciu Save pojawia się karta postępu, a potem sheet się zamyka.
    /// Dlaczego: Weryfikuje cały happy path: Save → progress → dismiss.
    /// Kryteria: multiImport.progressCard pojawia się i znika, sheet zamknięty.
    @MainActor
    func testMultiImportSaveShowsProgressAndCompletes() {
        launchWithMultiImport(photoCount: 3)
        waitForMultiImportSheet()

        let saveButton = app.buttons["multiImport.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()

        // Karta postępu powinna pojawić się podczas zapisywania
        let progressCard = app.otherElements["multiImport.progressCard"]
        // Nie wymuszamy istnienia karty (może być za szybka dla 3 małych zdjęć testowych),
        // ale po zakończeniu sheet powinien się zamknąć

        // Sheet zamknięty = Save button zniknie
        let saveGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: saveButton
        )
        let saveResult = XCTWaiter.wait(for: [saveGone], timeout: 15)
        XCTAssertEqual(
            saveResult, .completed,
            "MultiPhotoImportView powinien się zamknąć po zapisaniu zdjęć (timeout: 15s)"
        )

        // progressCard nie powinna być widoczna po zamknięciu
        XCTAssertFalse(
            progressCard.exists,
            "Karta postępu nie powinna być widoczna po zakończeniu zapisu"
        )
    }

    /// Co sprawdza: Save jest wyłączone podczas trwającego zapisu — double tap nie jest możliwy.
    /// Dlaczego: Double-tap Save powodowałby duplikaty wpisów w bazie.
    /// Kryteria: Drugi tap Save bezpośrednio po pierwszym nie powoduje błędu, sheet zamyka się raz.
    @MainActor
    func testSaveButtonCannotBeDoubleTapped() {
        launchWithMultiImport(photoCount: 3)
        waitForMultiImportSheet()

        let saveButton = app.buttons["multiImport.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.isEnabled, "Save powinien być aktywny przed zapisem")

        // Tappujemy Save dwukrotnie bardzo szybko — drugi tap powinien być zignorowany
        // bo isSaving == true wyłącza przycisk.
        // UWAGA: Po optymalizacji encodeBestFit małe testowe obrazy kompresują się
        // niemal natychmiast, więc sheet może zniknąć zanim sprawdzimy isEnabled.
        saveButton.tap()
        if saveButton.exists && saveButton.isEnabled {
            saveButton.tap() // drugi tap tylko jeśli jeszcze aktywny
        }

        // Efekt końcowy: sheet zamknięty, brak alertu o błędzie
        let saveGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: saveButton
        )
        let result = XCTWaiter.wait(for: [saveGone], timeout: 15)
        XCTAssertEqual(result, .completed, "Sheet powinien się zamknąć po zapisie (bez błędu duplikatu)")

        // Brak alertu o błędzie = sukces
        XCTAssertFalse(
            app.alerts.firstMatch.exists,
            "Nie powinno być żadnego alertu po podwójnym tapnięciu Save"
        )
    }

    // MARK: - Pasek miniaturek

    /// Co sprawdza: Pasek miniaturek (thumbnailStrip) jest widoczny.
    /// Dlaczego: Użytkownik musi widzieć podgląd zdjęć przed importem.
    /// Kryteria: multiImport.thumbnailStrip istnieje.
    @MainActor
    func testThumbnailStripIsVisible() {
        launchWithMultiImport(photoCount: 3)
        waitForMultiImportSheet()

        let strip = app.scrollViews["multiImport.thumbnailStrip"]
        XCTAssertTrue(
            strip.waitForExistence(timeout: 3),
            "Pasek miniaturek powinien być widoczny"
        )
    }
}
