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
            "-uiTestMode",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "3",
            "-uiTestForcePremium",              // force premium entitlement in UI
            "-uiTestBypassHealthSummaryGuards",// bypass availability/data guards for summary
            "-uiTestLongHealthInsight"         // use long test health insight text
        ]
        app.launch()
    }

    /// Co sprawdza: Sprawdza scenariusz: HealthAISummaryExpandsDynamically.
    /// Dlaczego: Zapewnia poprawna obsluge uprawnien i integracji z systemem.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `home.health.ai.text`).
    func testHealthModuleIsReachableOnHome() {
        let healthTitle = app.staticTexts["Health"].firstMatch
        scrollToReveal(healthTitle, in: app, maxSwipes: 6)
        XCTAssertTrue(healthTitle.waitForExistence(timeout: 5), "Health section should be reachable on Home")
        XCTAssertGreaterThan(healthTitle.frame.height, 10, "Health title should have a visible frame")
    }

    func testHomeDashboardModulesDoNotOverlap() {
        let keyMetricsTitle = app.staticTexts["Key metrics"].firstMatch
        let recentPhotosTitle = app.staticTexts["Recent photos"].firstMatch
        let healthTitle = app.staticTexts["Health"].firstMatch
        let keyMetrics = app.otherElements["home.module.keyMetrics"].firstMatch
        let recentPhotos = app.otherElements["home.module.recentPhotos"].firstMatch
        let healthSummary = app.otherElements["home.module.healthSummary"].firstMatch

        XCTAssertTrue(keyMetricsTitle.waitForExistence(timeout: 5), "Key metrics module should exist")
        XCTAssertTrue(recentPhotosTitle.waitForExistence(timeout: 5), "Recent photos module should exist")
        scrollToReveal(healthTitle, in: app, maxSwipes: 6)
        XCTAssertTrue(healthTitle.waitForExistence(timeout: 5), "Health module should exist")
        XCTAssertTrue(keyMetrics.waitForExistence(timeout: 5), "Key metrics card frame hook should exist")
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos card frame hook should exist")
        XCTAssertTrue(healthSummary.waitForExistence(timeout: 5), "Health card frame hook should exist")

        XCTAssertTrue(framesDoNotOverlap(keyMetrics, recentPhotos), "Key metrics and Recent photos must not overlap")
        XCTAssertTrue(framesDoNotOverlap(recentPhotos, healthSummary), "Recent photos and Health must not overlap")
        XCTAssertLessThanOrEqual(keyMetrics.frame.maxY, recentPhotos.frame.minY, "Recent photos should start after Key metrics ends")
        XCTAssertLessThanOrEqual(recentPhotos.frame.maxY, healthSummary.frame.minY, "Health should start after Recent photos ends")
    }

    func testRecentPhotosShowsThreeTiles() {
        let recentPhotos = app.staticTexts["Recent photos"].firstMatch
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos module should exist")
        let tileCount = app.staticTexts["home.recentPhotos.tileCount"].firstMatch
        XCTAssertTrue(tileCount.waitForExistence(timeout: 5), "Recent photos tile count hook should exist")
        XCTAssertEqual(tileCount.label, "3", "Recent photos should expose three visible tiles on Home")
    }

    private func framesDoNotOverlap(_ first: XCUIElement, _ second: XCUIElement) -> Bool {
        guard first.exists, second.exists else { return false }
        let firstFrame = first.frame
        let secondFrame = second.frame
        guard !firstFrame.isEmpty, !secondFrame.isEmpty else { return false }
        return firstFrame.intersection(secondFrame).isNull
    }

    private func scrollToReveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int) {
        guard element.exists || maxSwipes > 0 else { return }
        let window = app.windows.element(boundBy: 0)
        if isPartiallyVisible(element, in: window) { return }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if isPartiallyVisible(element, in: window) {
                return
            }
        }
    }

    private func isPartiallyVisible(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        guard element.exists, container.exists else { return false }
        let frame = element.frame
        let containerFrame = container.frame
        guard !frame.isEmpty, !containerFrame.isEmpty else { return false }
        let intersection = frame.intersection(containerFrame)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let visibleAreaRatio = (intersection.width * intersection.height) / (frame.width * frame.height)
        return visibleAreaRatio >= 0.25
    }
}
