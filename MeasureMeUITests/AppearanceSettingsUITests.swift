import XCTest

final class AppearanceSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-uiTestOpenSettingsTab"]
    }

    // MARK: - Tests

    @MainActor
    func testExperienceSettingsExposesAppearancePicker() {
        app.launch()
        waitForAppShell()
        openExperienceSettings()

        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Appearance segmented picker should exist in Experience settings")
        XCTAssertEqual(picker.buttons.count, 3, "Appearance picker should have exactly 3 segments (System, Light, Dark)")
    }

    @MainActor
    func testAppearancePickerSegmentLabels() {
        app.launch()
        waitForAppShell()
        openExperienceSettings()

        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Appearance segmented picker should exist")

        let systemButton = picker.buttons["System"].firstMatch
        let lightButton = picker.buttons["Light"].firstMatch
        let darkButton = picker.buttons["Dark"].firstMatch

        XCTAssertTrue(systemButton.exists, "System segment should be present")
        XCTAssertTrue(lightButton.exists, "Light segment should be present")
        XCTAssertTrue(darkButton.exists, "Dark segment should be present")
    }

    @MainActor
    func testSwitchingToLightModeSelectsLightSegment() {
        app.launch()
        waitForAppShell()
        openExperienceSettings()

        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Appearance segmented picker should exist")

        let lightButton = picker.buttons["Light"].firstMatch
        XCTAssertTrue(lightButton.exists, "Light segment should exist")
        lightButton.tap()

        XCTAssertTrue(lightButton.isSelected, "Light segment should be selected after tapping")

        let darkButton = picker.buttons["Dark"].firstMatch
        XCTAssertFalse(darkButton.isSelected, "Dark segment should not be selected after switching to Light")
    }

    @MainActor
    func testSwitchingToDarkModeSelectsDarkSegment() {
        app.launch()
        waitForAppShell()
        openExperienceSettings()

        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Appearance segmented picker should exist")

        // Switch to Light first, then back to Dark
        let lightButton = picker.buttons["Light"].firstMatch
        XCTAssertTrue(lightButton.exists, "Light segment should exist")
        lightButton.tap()
        XCTAssertTrue(lightButton.isSelected, "Light segment should be selected")

        let darkButton = picker.buttons["Dark"].firstMatch
        darkButton.tap()
        XCTAssertTrue(darkButton.isSelected, "Dark segment should be selected after tapping")
        XCTAssertFalse(lightButton.isSelected, "Light segment should not be selected after switching to Dark")
    }

    // MARK: - Helpers

    private func waitForAppShell(timeout: TimeInterval = 20) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: min(timeout, 10)), "App should enter foreground")

        let appRoot = app.otherElements["app.root.ready"].firstMatch
        let settingsRoot = app.descendants(matching: .any)["settings.root"].firstMatch
        let searchField = app.textFields["settings.search.field"].firstMatch.exists
            ? app.textFields["settings.search.field"].firstMatch
            : app.textFields["settings.section.search"].firstMatch
        let startupLoading = app.otherElements["startup.loading.root"].firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if appRoot.exists && (settingsRoot.exists || searchField.exists) {
                return
            }
            if startupLoading.exists {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                continue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail("Settings overview should become ready before interacting with the screen")
    }

    private func openExperienceSettings() {
        // Navigate to Experience settings using its accessibility identifier
        let experienceRow = app.descendants(matching: .any)["settings.row.experience"].firstMatch
        scrollToReveal(experienceRow)
        if experienceRow.waitForExistence(timeout: 2), experienceRow.isHittable {
            experienceRow.tap()
        } else {
            // Fallback for simulator/runtime variants where list row identifiers are not surfaced.
            let searchField = app.textFields["settings.search.field"].firstMatch
            if searchField.waitForExistence(timeout: 3) {
                searchField.tap()
                searchField.typeText("appearance")
            }

            let experienceByTitle = app.buttons["Appearance, animations and haptics"].firstMatch
            if experienceByTitle.waitForExistence(timeout: 5), experienceByTitle.isHittable {
                experienceByTitle.tap()
            } else {
                let experienceText = app.staticTexts["Appearance, animations and haptics"].firstMatch
                scrollToReveal(experienceText)
                XCTAssertTrue(experienceText.waitForExistence(timeout: 5), "Experience settings row should exist")
                experienceText.tap()
            }
        }

        XCTAssertTrue(
            app.navigationBars.staticTexts["Appearance, animations and haptics"].firstMatch.waitForExistence(timeout: 5),
            "Experience settings detail should open"
        )
    }

    private func scrollToReveal(_ element: XCUIElement, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return
            }
            app.swipeUp()
        }
    }
}
