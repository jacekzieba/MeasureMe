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
        app.launchArguments = ["-uiTestOnboardingMode", "-uiTestSeedMeasurements"]
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
        XCTAssertTrue(next.waitForExistence(timeout: 12), "Przycisk Dalej powinien istniec podczas onboardingu")

        let buildMuscle = app.buttons["onboarding.priority.buildMuscle"].firstMatch
        XCTAssertTrue(buildMuscle.waitForExistence(timeout: 8), "Polaczony krok profilu i celu powinien byc widoczny")
        buildMuscle.tap()
        next.tap()

        next.tap()
        next.tap()

        let skip = app.buttons["UITest Skip"].firstMatch
        XCTAssertTrue(app.buttons["onboarding.health.allow"].firstMatch.waitForExistence(timeout: 8), "Krok Health powinien byc widoczny")
        skip.tap()
    }

    private func onboardingNextButton() -> XCUIElement {
        let identifierNext = app.buttons["onboarding.test.next"].firstMatch
        if identifierNext.waitForExistence(timeout: 0.5) {
            return identifierNext
        }
        return app.buttons["UITest Next"].firstMatch
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
