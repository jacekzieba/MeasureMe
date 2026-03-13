import XCTest

final class MeasurementsPhysiqueUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    private func launchApp(arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private func openMeasurementsTab() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar should exist")

        let idTab = app.tabBars.buttons["tab.measurements"]
        if idTab.waitForExistence(timeout: 3) {
            idTab.tap()
            return
        }

        let fallbackEN = app.tabBars.buttons["Measurements"]
        if fallbackEN.waitForExistence(timeout: 2) {
            fallbackEN.tap()
            return
        }

        let fallbackPL = app.tabBars.buttons["Pomiary"]
        if fallbackPL.waitForExistence(timeout: 2) {
            fallbackPL.tap()
            return
        }

        XCTFail("Measurements tab should exist (identifier: tab.measurements or fallback label)")
    }

    private func scrollToVisible(_ element: XCUIElement, maxSwipes: Int = 6) {
        var attempts = 0
        while !element.exists && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    @MainActor
    func testMeasurementsSegmentContainsPhysique() {
        launchApp(arguments: ["-uiTestMode"])
        openMeasurementsTab()

        XCTAssertTrue(app.buttons["measurements.tab.physique"].waitForExistence(timeout: 5), "Physique tab should exist")
        XCTAssertTrue(app.buttons["measurements.tab.metrics"].exists, "Metrics tab should exist")
        XCTAssertTrue(app.buttons["measurements.tab.health"].exists, "Health tab should exist")
    }

    @MainActor
    func testPhysiqueTabShowsPremiumLockWhenNotPremium() {
        launchApp(arguments: ["-uiTestMode", "-uiTestForceNonPremium"])
        openMeasurementsTab()

        let physiqueButton = app.buttons["measurements.tab.physique"]
        if physiqueButton.waitForExistence(timeout: 5) {
            physiqueButton.tap()
        }

        // Tapping Physique when not premium triggers the paywall sheet and reverts to Metrics tab.
        // The paywall sheet has a close button with accessibility label "Close Premium screen".
        let paywallCloseButton = app.buttons["Close Premium screen"]
        XCTAssertTrue(paywallCloseButton.waitForExistence(timeout: 5), "Paywall should be presented when non-premium user taps Physique tab")
    }

    @MainActor
    func testPhysiqueRequiresGenderCardAndCTA() {
        launchApp(arguments: ["-uiTestMode", "-uiTestForcePremium", "-uiTestGenderNotSpecified"])
        openMeasurementsTab()

        let physiqueButton = app.buttons["measurements.tab.physique"]
        XCTAssertTrue(physiqueButton.waitForExistence(timeout: 5), "Physique tab should exist")
        physiqueButton.tap()

        XCTAssertTrue(app.staticTexts["Set gender to unlock these indicators"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open profile settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhysiqueToggleInSettingsAffectsMeasurementsVisibility() {
        launchApp(arguments: ["-uiTestMode", "-uiTestForcePremium", "-uiTestGenderMale", "-uiTestPhysiqueSWROff", "-uiTestOpenSettingsTab"])
        waitForSettingsOverview()
        tapSettingsTabIfNeeded()

        let searchField = settingsSearchField()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Settings search should exist")
        searchField.tap()
        searchField.typeText("physique")

        let physiqueEntry = app.staticTexts["Physique indicators"].firstMatch
        XCTAssertTrue(physiqueEntry.waitForExistence(timeout: 5), "Physique indicators settings entry should exist")
        physiqueEntry.tap()

        let swrToggle = app.switches["Shoulder-to-Waist Ratio"].firstMatch
        scrollToVisible(swrToggle)
        XCTAssertTrue(swrToggle.waitForExistence(timeout: 5), "SWR toggle should exist")
        XCTAssertEqual(swrToggle.value as? String, "0", "SWR toggle should be OFF")

        app.terminate()
        launchApp(arguments: ["-uiTestMode", "-uiTestForcePremium", "-uiTestGenderMale", "-uiTestPhysiqueSWROff"])
        openMeasurementsTab()
        app.buttons["measurements.tab.physique"].tap()

        let measurementsScroll = app.scrollViews["measurements.scroll"]
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 5), "Measurements scroll should exist")
        XCTAssertFalse(
            measurementsScroll.staticTexts["Shoulder-to-Waist Ratio"].exists,
            "SWR row should be hidden when toggle is disabled"
        )
    }

    private func settingsSearchField() -> XCUIElement {
        if app.textFields["settings.search.field"].firstMatch.exists {
            return app.textFields["settings.search.field"].firstMatch
        }
        if app.descendants(matching: .any)["settings.search.field"].firstMatch.exists {
            return app.descendants(matching: .any)["settings.search.field"].firstMatch
        }
        return app.textFields.firstMatch
    }

    private func tapSettingsTabIfNeeded() {
        if app.descendants(matching: .any)["settings.root"].firstMatch.exists
            || app.descendants(matching: .any)["settings.section.search"].firstMatch.exists
            || settingsSearchField().exists {
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

    private func waitForSettingsOverview(timeout: TimeInterval = 20) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: min(timeout, 10)))

        let appRoot = app.otherElements["app.root.ready"].firstMatch
        let settingsRoot = app.descendants(matching: .any)["settings.root"].firstMatch
        let searchSection = app.descendants(matching: .any)["settings.section.search"].firstMatch
        let accountSection = app.descendants(matching: .any)["settings.section.account"].firstMatch
        let supportSection = app.descendants(matching: .any)["settings.section.support"].firstMatch
        let startupLoading = app.otherElements["startup.loading.root"].firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if appRoot.exists && (settingsRoot.exists || settingsSearchField().exists || searchSection.exists || accountSection.exists || supportSection.exists) {
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
