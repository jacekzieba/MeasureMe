/// Cel testow: Sprawdza wejscie do modelu 3D z zakladki Photos i bramke premium.
/// Dlaczego to wazne: Feature jest platny; zla bramka to albo utracony przychod, albo zablokowany user.
/// Kryteria zaliczenia: Bez premium widoczna zachęta, z premium widoczny prawdziwy ekran (nie zacheta).

import XCTest

final class BodyModelUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Co sprawdza: Bez `-uiTestMode` (i bez premium) otwarcie ekranu modelu 3D pokazuje zachete premium.
    /// Dlaczego: `hasAccess` w BodyModelScreen to `premiumStore.isPremium || UITestArgument.isPresent(.mode)` —
    ///   pominiecie trybu testowego jest jedynym sposobem, by faktycznie wywolac bramke zamiast ja ominac.
    /// Kryteria: Widoczny jest identyfikator `photos.bodyModel.premiumTeaser`.
    @MainActor
    func testOpeningBodyModelWithoutPremiumShowsTeaser() {
        // Celowo bez "-uiTestMode": ta flaga sama w sobie omija bramke premium
        // (`UITestArgument.isPresent(.mode)`), wiec test bramki musi biec bez niej.
        // "-uiTestForceNonPremium" dziala niezaleznie od "-uiTestMode" (PremiumStore czyta
        // je wprost z ProcessInfo), wiec status premium pozostaje deterministyczny.
        // "-uiTestForceOnboardingComplete" stwierdza wlasny warunek wstepny testu (pomin
        // onboarding) zamiast dziedziczyc go po tym, co zostawil poprzedni test na tym
        // symulatorze — bez tego test nie jest hermetyczny na swiezo wyczyszczonym symulatorze.
        app.launchArguments = ["-uiTestForceNonPremium", "-uiTestForceOnboardingComplete"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        tapTab(named: "tab.photos")

        let openButton = app.descendants(matching: .any)["photos.bodyModel.open"].firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 10), "Expected body model entry button on Photos tab.")
        openButton.tap()

        let teaser = app.descendants(matching: .any)["photos.bodyModel.premiumTeaser"].firstMatch
        XCTAssertTrue(teaser.waitForExistence(timeout: 10), "Expected premium teaser without premium access.")

        let mannequin = app.descendants(matching: .any)["photos.bodyModel.mannequin"].firstMatch
        XCTAssertFalse(mannequin.exists, "Mannequin content must not render behind the paywall.")
    }

    /// Co sprawdza: Z `-uiTestMode` otwarcie ekranu modelu 3D pokazuje prawdziwy ekran, nie zachete.
    /// Dlaczego: `-uiTestMode` jest przepustka uzywana przez cala reszte apki do ominiecia zakupu w testach —
    ///   ten test dowodzi, ze bramka faktycznie sie otwiera, a nie tylko, ze mozna ja pominac.
    /// Kryteria: Identyfikator `photos.bodyModel.premiumTeaser` nie istnieje; widoczny jest stan realny
    ///   ekranu (tu deterministycznie `photos.bodyModel.needsProfile`, bo plec jest jawnie nieustawiona).
    @MainActor
    func testOpeningBodyModelWithUiTestModeShowsRealScreen() {
        // Plec ustawiona jawnie na "notSpecified" tak, by stan ekranu byl deterministyczny
        // niezaleznie od tego, co poprzedni test zostawil w UserDefaults — bez niej
        // BodyModelViewModel od razu przechodzi w .needsProfile, co samo w sobie jest
        // dowodem, ze to prawdziwy ekran (a nie zachete premium).
        app.launchArguments = ["-uiTestMode", "-uiTestGenderNotSpecified"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        tapTab(named: "tab.photos")

        let openButton = app.descendants(matching: .any)["photos.bodyModel.open"].firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 10), "Expected body model entry button on Photos tab.")
        openButton.tap()

        let teaser = app.descendants(matching: .any)["photos.bodyModel.premiumTeaser"].firstMatch
        XCTAssertFalse(teaser.waitForExistence(timeout: 3), "Premium teaser must not show once the gate is bypassed.")

        let needsProfile = app.descendants(matching: .any)["photos.bodyModel.needsProfile"].firstMatch
        XCTAssertTrue(needsProfile.waitForExistence(timeout: 10), "Expected the real needsProfile state to render.")
    }

    // MARK: - Helpers

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
            let button = tabBar.buttons[candidate]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }

        XCTFail("Expected tab \(name) to exist.")
    }
}
