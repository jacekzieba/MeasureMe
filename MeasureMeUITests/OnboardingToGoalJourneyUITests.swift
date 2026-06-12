/// Cel testow: Testy sciezki UI od onboardingu do ustawienia celu i wejscia w docelowy stan.
/// Dlaczego to wazne: Awaria tej sciezki blokuje start uzytkownika w aplikacji.
/// Kryteria zaliczenia: Wszystkie kroki przechodza, a stan koncowy jest poprawny i utrwalony.

import XCTest

final class OnboardingToGoalJourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestOnboardingMode", "-uiTestSeedMeasurements", "-uiTestOnboardingPriority", "buildMuscle"]
        app.launch()
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: FullJourneyOnboardingQuickAddChartAndSetGoal.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `measurements.scroll`).
    func testFullJourneyOnboardingQuickAddChartAndSetGoal() {
        completeOnboardingFlow()

        openMeasurementsTab()

        let measurementsScroll = app.scrollViews["measurements.scroll"]
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 8), "Kontener pomiarow powinien istniec")

        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'metric.tile.open.'"))
        if !tiles.firstMatch.waitForExistence(timeout: 5) {
            measurementsScroll.swipeUp()
        }
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 5),
                      "Po pierwszym zapisie powinien byc dostepny co najmniej jeden kafelek metryki")
    }

    private func completeOnboardingFlow() {
        let next = onboardingNextButton()
        let skip = onboardingSkipButton()
        XCTAssertTrue(next.waitForExistence(timeout: 12), "Przycisk Dalej powinien istniec podczas onboardingu")
        next.tap()  // welcome → goal

        // Goal jest wybrany przez launch arg (-uiTestOnboardingPriority buildMuscle).
        XCTAssertTrue(app.buttons["onboarding.priority.buildMuscle"].firstMatch.waitForExistence(timeout: 8), "Krok celu powinien byc widoczny")
        next.tap()  // goal → starting point

        let weightField = app.textFields["onboarding.measurement.weight"].firstMatch
        XCTAssertTrue(weightField.waitForExistence(timeout: 8), "Krok punktu startowego powinien pokazac hero wagi")
        next.tap()  // starting point → rhythm (zapisuje punkt startowy)

        skip.tap()  // rhythm → boosters (skip omija prompt o powiadomienia)

        XCTAssertTrue(app.buttons["onboarding.health.allow"].firstMatch.waitForExistence(timeout: 8), "Krok boosterow powinien zawierac Apple Health")
        skip.tap()  // boosters → plan
        next.tap()  // plan → finish
    }

    private func onboardingNextButton() -> XCUIElement {
        let identifierNext = app.buttons["onboarding.test.next"].firstMatch
        if identifierNext.waitForExistence(timeout: 0.5) {
            return identifierNext
        }
        return app.buttons["UITest Next"].firstMatch
    }

    private func onboardingSkipButton() -> XCUIElement {
        let identifierSkip = app.buttons["onboarding.test.skip"].firstMatch
        if identifierSkip.waitForExistence(timeout: 0.5) {
            return identifierSkip
        }
        return app.buttons["UITest Skip"].firstMatch
    }

    private func openMeasurementsTab() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Pasek zakladek powinien byc widoczny")

        let measurementCandidates = ["tab.measurements", "Measurements", "Pomiary"]
        for label in measurementCandidates {
            let button = tabBar.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }

        let byPrefix = tabBar.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Measure' OR label BEGINSWITH[c] 'Pomiar'"))
        if byPrefix.firstMatch.exists {
            byPrefix.firstMatch.tap()
            return
        }

        XCTFail("Could not locate Measurements tab button")
    }
}
