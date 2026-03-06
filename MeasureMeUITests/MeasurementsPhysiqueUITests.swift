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
        let tab = app.tabBars.buttons["tab.measurements"]
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
        }
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
        launchApp(arguments: ["-uiTestMode", "-uiTestForcePremium", "-uiTestGenderMale", "-uiTestPhysiqueSWROff"])

        let settingsTab = app.tabBars.buttons["tab.settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should exist")
        settingsTab.tap()

        let searchField = app.searchFields.firstMatch
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

        openMeasurementsTab()
        app.buttons["measurements.tab.physique"].tap()

        let measurementsScroll = app.scrollViews["measurements.scroll"]
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 5), "Measurements scroll should exist")
        XCTAssertFalse(
            measurementsScroll.staticTexts["Shoulder-to-Waist Ratio"].exists,
            "SWR row should be hidden when toggle is disabled"
        )
    }
}
