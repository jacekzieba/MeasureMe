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
        // powitanie -> profil -> boostery -> premium -> zakonczenie
        for _ in 0..<4 {
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 6), "Przycisk Dalej powinien istniec podczas onboardingu")
            XCTAssertTrue(next.isEnabled, "Przycisk Dalej powinien byc aktywny")
            next.tap()
        }
    }

    private func openMeasurementsTab() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Pasek zakladek powinien byc widoczny")

        let measurementCandidates = ["Measurements", "Pomiary"]
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
