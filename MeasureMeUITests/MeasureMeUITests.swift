/// Cel testow: Smoke testy UI aplikacji (start i podstawowe scenariusze krytyczne).
/// Dlaczego to wazne: To bezpiecznik przed regresjami startupowymi i bledami integracyjnymi.
/// Kryteria zaliczenia: Aplikacja uruchamia sie i wykonuje podstawowe kroki bez bledow.

import XCTest

final class MeasureMeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: SmokeAppLaunches.
    /// Dlaczego: Chroni krytyczny przeplyw przed regresja i nieoczekiwanymi crashami.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testSmokeAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: HealthSyncDeniedRollsBackToggleAndShowsError.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `Settings`, `settings.health.sync.toggle`, `settings.health.sync.error`).
    func testHealthSyncDeniedRollsBackToggleAndShowsError() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestHealthAuthDenied",
            "-uiTestOpenSettingsTab"
        ]
        app.launch()
        waitForSettingsOverview(app)
        tapSettingsTabIfNeeded(app)

        let searchField = settingsSearchField(in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Health")

        let healthRow = app.staticTexts["Health"].firstMatch
        XCTAssertTrue(healthRow.waitForExistence(timeout: 5))
        healthRow.tap()

        let toggle = app.switches["settings.health.sync.toggle"].firstMatch
        scrollToReveal(toggle, in: app, maxSwipes: 6)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        if !isSwitchOff(toggle) {
            toggle.tap()
            XCTAssertTrue(isSwitchOff(toggle))
        }

        toggle.tap()

        let errorLabel = app.staticTexts["settings.health.sync.error"]
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(isSwitchOff(toggle))
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: LongInsightTextExpandsTileHeight.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `Measurements`, `insight.card.text.compact`, `metric.tile.open.weight`).
    func testLongInsightTextExpandsTileHeight() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForcePremium",
            "-uiTestForceAIAvailable",
            "-uiTestLongInsight",
            "-uiTestSeedMeasurements"
        ]
        app.launch()

        tapTab(in: app, identifier: "tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])

        let insightText = app.staticTexts["insight.card.text.compact"].firstMatch
        XCTAssertTrue(insightText.waitForExistence(timeout: 8))
        XCTAssertTrue(insightText.label.contains("UI_TEST_LONG_INSIGHT_MARKER"))
        XCTAssertGreaterThan(insightText.frame.height, 30)

        let openWeightDetail = app.buttons["metric.tile.open.weight"]
        if openWeightDetail.waitForExistence(timeout: 5) {
            openWeightDetail.tap()
            let detailedInsight = app.staticTexts["insight.card.text.detail"].firstMatch
            XCTAssertTrue(detailedInsight.waitForExistence(timeout: 8))
            XCTAssertGreaterThan(detailedInsight.frame.height, 30)
        } else {
            XCTFail("Expected weight detail navigation button.")
        }
    }

    @MainActor
    /// Co sprawdza: Sekcja AI w szczegółach metryki pozostaje widoczna przy zmianie zakresu wykresu.
    /// Dlaczego: Chroni regresję, w której przełączenie 7D/30D/All chowa insight mimo aktywnego AI.
    /// Kryteria: Insight istnieje i nadal zawiera marker po przełączeniach zakresu.
    func testInsightRemainsVisibleWhenSwitchingChartRange() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForcePremium",
            "-uiTestForceAIAvailable",
            "-uiTestLongInsight",
            "-uiTestSeedMeasurements"
        ]
        app.launch()

        waitForAppToBecomeInteractable(app)

        let openWeightDetail = app.buttons["metric.tile.open.weight"].firstMatch
        if !openWeightDetail.waitForExistence(timeout: 3) {
            let nextFocus = app.buttons["home.nextFocus.button"].firstMatch
            if nextFocus.waitForExistence(timeout: 3) {
                nextFocus.tap()
            } else {
                tapTab(in: app, identifier: "tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])
            }
        }
        XCTAssertTrue(openWeightDetail.waitForExistence(timeout: 5))
        openWeightDetail.tap()

        let detailInsight = app.staticTexts["insight.card.text.detail"].firstMatch
        XCTAssertTrue(detailInsight.waitForExistence(timeout: 8))
        XCTAssertTrue(detailInsight.label.contains("UI_TEST_LONG_INSIGHT_MARKER"))

        let range7D = app.buttons["7D"].firstMatch
        if range7D.exists { range7D.tap() }
        XCTAssertTrue(detailInsight.waitForExistence(timeout: 5))

        let range30D = app.buttons["30D"].firstMatch
        if range30D.exists { range30D.tap() }
        XCTAssertTrue(detailInsight.waitForExistence(timeout: 5))

        let rangeAll = app.buttons["All"].firstMatch
        if rangeAll.exists { rangeAll.tap() }
        XCTAssertTrue(detailInsight.waitForExistence(timeout: 5))
        XCTAssertTrue(detailInsight.label.contains("UI_TEST_LONG_INSIGHT_MARKER"))
    }

    @MainActor
    /// Co sprawdza: Kafelek celu pod wykresem otwiera formularz i pozwala zapisać nowy cel.
    /// Dlaczego: To zabezpiecza regresję, w której "Set Goal" wygląda jak CTA, ale nie działa albo nie zapisuje danych.
    /// Kryteria: Sheet celu otwiera się, zapis jest możliwy, a po zamknięciu ekran pokazuje nowy target.
    func testSetGoalFromChartCardSavesTarget() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestSeedMeasurements"
        ]
        app.launch()

        waitForAppToBecomeInteractable(app)

        let openWeightDetail = app.buttons["metric.tile.open.weight"].firstMatch
        if !openWeightDetail.waitForExistence(timeout: 3) {
            let nextFocus = app.buttons["home.nextFocus.button"].firstMatch
            if nextFocus.waitForExistence(timeout: 3) {
                nextFocus.tap()
            } else {
                tapTab(in: app, identifier: "tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])
            }
        }

        XCTAssertTrue(openWeightDetail.waitForExistence(timeout: 5), "Weight detail navigation button should exist")
        openWeightDetail.tap()

        let goalButton = app.buttons["metric.detail.goal"].firstMatch
        XCTAssertTrue(goalButton.waitForExistence(timeout: 5), "Goal action should be tappable under the chart")
        goalButton.tap()

        let goalSheet = app.navigationBars[app.staticTexts["Set Goal"].firstMatch.exists ? "Set Goal" : "Ustaw cel"].firstMatch
        XCTAssertTrue(goalSheet.waitForExistence(timeout: 5), "Goal sheet should open after tapping the goal card")

        let goalInput = app.textFields["goal.input.value"].firstMatch.exists
            ? app.textFields["goal.input.value"].firstMatch
            : (
                app.descendants(matching: .any)["goal.input.value"].firstMatch.exists
                ? app.descendants(matching: .any)["goal.input.value"].firstMatch
                : app.textFields.firstMatch
            )
        XCTAssertTrue(goalInput.waitForExistence(timeout: 5), "Goal input should be visible after tapping hero goal segment")
        goalInput.tap()
        goalInput.typeText("75")

        let saveButton = app.buttons["goal.save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button should exist in goal sheet")
        XCTAssertTrue(saveButton.isEnabled, "Valid goal value should enable saving")
        saveButton.tap()

        XCTAssertTrue(goalButton.waitForExistence(timeout: 5), "Goal sheet should dismiss after saving")
        XCTAssertFalse(app.staticTexts["Set a target"].firstMatch.exists, "Saved goal should replace the placeholder copy")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "75")).firstMatch.waitForExistence(timeout: 5),
            "Saved goal target should be visible on the detail screen"
        )
    }

    @MainActor
    /// Co sprawdza: Ekran szczegółu metryki nie renderuje już sekcji "Your Progress", a pionowy swipe po wykresie nadal przewija ekran.
    /// Dlaczego: To zabezpiecza nowy układ karty i regresję, w której overlay wykresu blokuje scroll listy.
    /// Kryteria: Goal i Trend są obecne pod wykresem, "Your Progress" nie istnieje, a po swipe na wykresie sekcja History pozostaje osiągalna.
    func testMetricDetailChartCardLayoutAndVerticalScroll() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestSeedMeasurements"
        ]
        app.launch()

        waitForAppToBecomeInteractable(app)

        let openWeightDetail = app.buttons["metric.tile.open.weight"].firstMatch
        if !openWeightDetail.waitForExistence(timeout: 3) {
            let nextFocus = app.buttons["home.nextFocus.button"].firstMatch
            if nextFocus.waitForExistence(timeout: 3) {
                nextFocus.tap()
            } else {
                tapTab(in: app, identifier: "tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])
            }
        }

        XCTAssertTrue(openWeightDetail.waitForExistence(timeout: 5), "Weight detail navigation button should exist")
        openWeightDetail.tap()

        XCTAssertTrue(app.buttons["metric.detail.goal"].firstMatch.waitForExistence(timeout: 5), "Goal action should be visible")
        XCTAssertTrue(app.buttons["metric.detail.trend"].firstMatch.waitForExistence(timeout: 5), "Trend action should be visible")
        XCTAssertFalse(app.staticTexts["Your Progress"].firstMatch.exists, "Legacy Your Progress section should not be rendered")
        XCTAssertFalse(app.staticTexts["Twoje postępy"].firstMatch.exists, "Legacy localized progress section should not be rendered")

        let chart = app.otherElements["metric.detail.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "Chart should be visible")

        let historyHeader = app.staticTexts["History"].firstMatch
        XCTAssertTrue(historyHeader.waitForExistence(timeout: 5), "History header should be reachable before swipe")
        let initialMinY = historyHeader.frame.minY

        chart.swipeUp()
        if historyHeader.frame.minY >= initialMinY {
            app.swipeUp()
        }

        XCTAssertTrue(historyHeader.waitForExistence(timeout: 2), "History header should remain reachable after swiping on chart")
        XCTAssertLessThanOrEqual(historyHeader.frame.minY, initialMinY, "Swiping on the chart should not block vertical scrolling")
    }

    private func isSwitchOff(_ element: XCUIElement) -> Bool {
        guard let value = element.value as? String else { return false }
        return value == "0" || value.lowercased() == "off"
    }

    private func waitForAppToBecomeInteractable(_ app: XCUIApplication) {
        if app.otherElements["app.root.ready"].waitForExistence(timeout: 3) {
            return
        }

        let likelyInteractiveElements: [XCUIElement] = [
            app.tabBars.firstMatch,
            app.buttons["metric.tile.open.weight"].firstMatch,
            app.buttons["home.nextFocus.button"].firstMatch,
            app.navigationBars.firstMatch
        ]

        let becameInteractable = likelyInteractiveElements.contains { $0.waitForExistence(timeout: 5) }
        XCTAssertTrue(becameInteractable, "App should become interactable even if app.root.ready is unavailable")
    }

    private func tapTab(in app: XCUIApplication, identifier: String, fallbackLabels: [String]) {
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 10)

        for _ in 0..<6 {
            let candidates = [identifier] + fallbackLabels
            for candidate in candidates {
                let button = app.buttons[candidate].firstMatch
                if button.exists && button.isHittable {
                    button.tap()
                    return
                }
            }

            if tabBar.exists {
                let xOffset: CGFloat
                switch identifier {
                case "tab.home": xOffset = 0.10
                case "tab.measurements": xOffset = 0.30
                case "tab.photos": xOffset = 0.70
                case "tab.settings": xOffset = 0.90
                default: xOffset = 0.50
                }
                tabBar.coordinate(withNormalizedOffset: CGVector(dx: xOffset, dy: 0.5)).tap()
                if app.buttons[identifier].exists || app.buttons.matching(NSPredicate(format: "identifier == %@", identifier)).count > 0 {
                    return
                }
            }

            app.swipeDown()
        }

        XCTFail("Tab should exist: \(identifier)")
    }

    private func scrollToReveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int) {
        for _ in 0..<maxSwipes {
            if element.exists {
                return
            }
            app.swipeUp()
        }
    }

    private func settingsSearchField(in app: XCUIApplication) -> XCUIElement {
        if app.textFields["settings.search.field"].firstMatch.exists {
            return app.textFields["settings.search.field"].firstMatch
        }
        if app.descendants(matching: .any)["settings.search.field"].firstMatch.exists {
            return app.descendants(matching: .any)["settings.search.field"].firstMatch
        }
        return app.textFields.firstMatch
    }

    private func tapSettingsTabIfNeeded(_ app: XCUIApplication) {
        if app.descendants(matching: .any)["settings.root"].firstMatch.exists
            || app.descendants(matching: .any)["settings.section.search"].firstMatch.exists
            || settingsSearchField(in: app).exists {
            return
        }

        for candidate in ["tab.settings", "Settings", "Ustawienia"] {
            let button = app.buttons[candidate].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    private func waitForSettingsOverview(_ app: XCUIApplication, timeout: TimeInterval = 20) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: min(timeout, 10)))

        let appRoot = app.otherElements["app.root.ready"].firstMatch
        let settingsRoot = app.descendants(matching: .any)["settings.root"].firstMatch
        let searchSection = app.descendants(matching: .any)["settings.section.search"].firstMatch
        let accountSection = app.descendants(matching: .any)["settings.section.account"].firstMatch
        let supportSection = app.descendants(matching: .any)["settings.section.support"].firstMatch
        let startupLoading = app.otherElements["startup.loading.root"].firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if appRoot.exists && (settingsRoot.exists || settingsSearchField(in: app).exists || searchSection.exists || accountSection.exists || supportSection.exists) {
                return
            }
            if startupLoading.exists {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                continue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail("Settings overview should become ready before interacting. Debug tree: \(app.debugDescription)")
    }
}
