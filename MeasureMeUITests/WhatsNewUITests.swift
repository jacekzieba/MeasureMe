/// Cel testow: Sprawdza arkusz "Co nowego" i kafelek modelu ciala na ekranie glownym.
/// Dlaczego to wazne: Oba istnieja wylacznie po to, zeby user znalazl model 3D. Jesli arkusz
///   sie nie otwiera albo jego przycisk nigdzie nie prowadzi, funkcja zostaje tam, gdzie byla —
///   za nieopisana ikonka w toolbarze zakladki Zdjecia.
/// Kryteria zaliczenia: Arkusz pokazuje sie na fladze, jego przycisk otwiera model,
///   a kafelek na Home jest widoczny i tez do modelu prowadzi.

import XCTest

final class WhatsNewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Co sprawdza: Flaga `-uiTestShowWhatsNew` otwiera arkusz notatek o wydaniu.
    /// Dlaczego: W trybie testow arkusz jest domyslnie wyciszony (inaczej rozwalalby kazdy inny
    ///   test), wiec bez jawnej flagi nic nigdy by go nie sprawdzilo.
    /// Kryteria: Identyfikator `whatsNew.sheet` istnieje.
    @MainActor
    func testWhatsNewSheetShowsOnFlag() {
        app.launchArguments = ["-uiTestMode", "-uiTestShowWhatsNew"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let sheet = app.descendants(matching: .any)["whatsNew.sheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "Expected the What's New sheet on the opt-in flag.")

        let open = app.descendants(matching: .any)["whatsNew.open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "Expected the deep-link button inside the sheet.")
    }

    /// Co sprawdza: Bez flagi arkusz sie nie pokazuje.
    /// Dlaczego: To jest wyciszenie, na ktorym stoi determinizm calej reszty pakietu UI —
    ///   gdyby przestalo dzialac, awarie wysypalyby sie w losowych, niepowiazanych testach.
    /// Kryteria: `whatsNew.sheet` nie istnieje.
    @MainActor
    func testWhatsNewSheetIsSuppressedInPlainTestMode() {
        app.launchArguments = ["-uiTestMode"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let sheet = app.descendants(matching: .any)["whatsNew.sheet"].firstMatch
        XCTAssertFalse(sheet.waitForExistence(timeout: 5), "The sheet must stay suppressed without its flag.")
    }

    /// Co sprawdza: Przycisk "Pokaz mi" z arkusza doprowadza do ekranu modelu ciala.
    /// Dlaczego: Cala wartosc arkusza siedzi w tym jednym skoku; sam tekst o nowej funkcji
    ///   zostawia usera dokladnie tam, gdzie byl.
    /// Kryteria: Po tapnieciu widoczny jest ktorykolwiek stan ekranu modelu.
    @MainActor
    func testWhatsNewOpenButtonReachesTheBodyModel() {
        app.launchArguments = ["-uiTestMode", "-uiTestShowWhatsNew", "-uiTestGenderNotSpecified"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let open = app.descendants(matching: .any)["whatsNew.open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15), "Expected the deep-link button inside the sheet.")
        open.tap()

        XCTAssertTrue(
            waitForBodyModelScreen(timeout: 20),
            "Expected the body model screen after tapping the sheet's open button."
        )
    }

    /// Co sprawdza: Kafelek modelu ciala jest na ekranie glownym, gdy sa jakiekolwiek pomiary.
    /// Dlaczego: To jedyna widoczna sciezka do modelu poza ikonka w toolbarze Zdjec — a ikonki
    ///   nikt nie znajduje celowo.
    /// Kryteria: Identyfikator `home.bodyModel.card` istnieje.
    @MainActor
    func testHomeShowsBodyModelCard() {
        app.launchArguments = ["-uiTestMode", "-uiTestSeedMeasurements"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let card = app.descendants(matching: .any)["home.bodyModel.card"].firstMatch
        XCTAssertTrue(
            scrollToElement(card, timeout: 20),
            "Expected the body model card on Home once measurements exist."
        )
    }

    /// Co sprawdza: Tapniecie kafelka otwiera ekran modelu ciala.
    /// Dlaczego: Kafelek, ktory tylko wyglada jak przycisk, jest gorszy niz jego brak.
    /// Kryteria: Po tapnieciu widoczny jest ktorykolwiek stan ekranu modelu.
    @MainActor
    func testHomeBodyModelCardOpensTheModel() {
        app.launchArguments = ["-uiTestMode", "-uiTestSeedMeasurements", "-uiTestGenderNotSpecified"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let card = app.descendants(matching: .any)["home.bodyModel.card"].firstMatch
        XCTAssertTrue(scrollToElement(card, timeout: 20), "Expected the body model card on Home.")
        card.tap()

        XCTAssertTrue(
            waitForBodyModelScreen(timeout: 20),
            "Expected the body model screen after tapping the Home card."
        )
    }

    // MARK: - Helpers

    /// Ekran modelu ma kilka legalnych stanow wejsciowych (brak plci, brakujace pomiary,
    /// manekin) i ktory z nich wypadnie, zalezy od tego, co zostalo w kontenerze symulatora.
    /// Test nawigacji ma dowodzic dotarcia na ekran, nie zgadywac jego stan.
    private func waitForBodyModelScreen(timeout: TimeInterval) -> Bool {
        let identifiers = [
            "photos.bodyModel.needsProfile",
            "photos.bodyModel.missingMetrics",
            "photos.bodyModel.mannequin",
            "photos.bodyModel.preparing",
            "photos.bodyModel.premiumTeaser"
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers where app.descendants(matching: .any)[identifier].firstMatch.exists {
                return true
            }
            usleep(300_000)
        }
        return false
    }

    /// Kafelek siedzi pod modulami Home, wiec na iPhonie startuje poza ekranem.
    private func scrollToElement(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }

        for _ in 0..<8 {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
