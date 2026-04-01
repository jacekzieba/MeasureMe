/// Cel testow: Weryfikuje onboarding (kolejnosc krokow, akcje premium, linki prawne).
/// Dlaczego to wazne: Onboarding ustawia konfiguracje startowa; blad blokuje dalsze uzycie.
/// Kryteria zaliczenia: Kroki sa dostepne, mozna je przejsc, a kluczowe elementy sa widoczne.

import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        launchApp(arguments: ["-uiTestOnboardingMode"])
    }

    private func launchApp(arguments: [String]) {
        if app != nil, app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private var nextButton: XCUIElement {
        app.buttons["UITest Next"].firstMatch
    }

    private var backButton: XCUIElement {
        app.buttons["UITest Back"].firstMatch
    }

    private var skipButton: XCUIElement {
        app.buttons["UITest Skip"].firstMatch
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: WelcomeGoalAccessibilityValueReflectsSelection.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testWelcomeGoalAccessibilityValueReflectsSelection() {
        let goalIDs = [
            "onboarding.goal.loseWeight",
            "onboarding.goal.buildMuscle",
            "onboarding.goal.trackHealth"
        ]

        guard let goalButton = goalIDs
            .map({ app.buttons[$0] })
            .first(where: { $0.waitForExistence(timeout: 10) }) else {
            XCTFail("Expected at least one onboarding goal button")
            return
        }

        goalButton.tap()
        let value = goalButton.value as? String
        XCTAssertNotNil(value, "Cel powinien udostepniac wartosc dostepnosci")
        XCTAssertFalse((value ?? "").isEmpty, "Wartosc dostepnosci nie powinna byc pusta")
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: NavigateThroughAllStepsSequentially.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.next`).
    func testNavigateThroughAllStepsSequentially() {
        let firstNext = nextButton
        XCTAssertTrue(firstNext.waitForExistence(timeout: 10), "Przycisk Dalej powinien istniec")
        XCTAssertTrue(firstNext.isEnabled, "Przycisk Dalej powinien byc aktywny")
        firstNext.tap()

        XCTAssertTrue(app.buttons["onboarding.booster.healthkit"].waitForExistence(timeout: 5), "Na ekranie pierwszego pomiaru powinien byc widoczny prompt HealthKit")
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5), "Na ekranie pierwszego pomiaru powinien byc widoczny przycisk pominiecia")

        app.buttons["onboarding.skip"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Po pominieciu drugiego kroku onboarding powinien sie zakonczyc")
    }

    @MainActor
    /// Co sprawdza: Sprawdza, ze karta HealthKit jest widoczna na ekranie pierwszego pomiaru.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.next`, `onboarding.booster.healthkit`).
    func testHealthKitPromptIsVisibleOnFirstMeasurementStep() {
        let next = nextButton
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()

        let healthKitButton = app.buttons["onboarding.booster.healthkit"]
        XCTAssertTrue(healthKitButton.waitForExistence(timeout: 5), "Przycisk HealthKit powinien istniec na ekranie pierwszego pomiaru")
    }

    @MainActor
    func testHealthKitPromptDoesNotReplaceMeasurementFields() {
        let next = nextButton
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()

        XCTAssertTrue(app.buttons["onboarding.booster.healthkit"].exists, "Prompt HealthKit powinien byc widoczny")
        XCTAssertTrue(app.buttons["onboarding.skip"].exists, "Drugi krok powinien miec opcje pominiecia")
        XCTAssertTrue(app.textFields["onboarding.measurement.weight"].waitForExistence(timeout: 5), "Pole wagi powinno pozostac widoczne obok promptu HealthKit")
    }

    @MainActor
    /// Co sprawdza: Sprawdza, ze elementy UI sa widoczne zgodnie z oczekiwaniem (PrivacyNoteVisibleOnWelcome).
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.privacy.note`).
    func testPrivacyNoteVisibleOnWelcome() {
        let privacyNote = app.descendants(matching: .any)["onboarding.privacy.note"].firstMatch
        let privacyCopy = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Your data stays on this device by default")
        ).firstMatch
        let privacyHookCopy = app.staticTexts["Privacy note"].firstMatch

        XCTAssertTrue(
            privacyNote.waitForExistence(timeout: 10)
                || privacyCopy.waitForExistence(timeout: 10)
                || privacyHookCopy.waitForExistence(timeout: 10),
            "Notatka o prywatnosci powinna byc widoczna na ekranie powitalnym onboardingu"
        )
    }
}
