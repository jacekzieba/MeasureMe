import XCTest

final class AppearanceSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-uiTestOpenSettingsTab", "-uiTestOpenExperienceSettings"]
    }

    // MARK: - Tests

    @MainActor
    func testAppearancePickerSegmentsAndSwitching() {
        app.launch()
        waitForAppShell()
        openExperienceSettings()

        assertAppearanceSegmentsExist()

        let lightButton = app.buttons["Light"].firstMatch
        lightButton.tap()
        XCTAssertTrue(lightButton.isSelected, "Light segment should be selected after tapping")

        let darkButton = app.buttons["Dark"].firstMatch
        XCTAssertFalse(darkButton.isSelected, "Dark segment should not be selected after switching to Light")

        darkButton.tap()
        XCTAssertTrue(darkButton.isSelected, "Dark segment should be selected after tapping")
        XCTAssertFalse(lightButton.isSelected, "Light segment should not be selected after switching to Dark")
    }

    // MARK: - Helpers

    private func waitForAppShell(timeout: TimeInterval = 20) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: min(timeout, 10)), "App should enter foreground")

        let appRoot = app.otherElements["app.root.ready"].firstMatch
        let settingsRoot = app.descendants(matching: .any)["settings.root"].firstMatch
        let experienceTitle = app.navigationBars.staticTexts["Appearance, animations and haptics"].firstMatch
        let searchField = app.textFields["settings.search.field"].firstMatch.exists
            ? app.textFields["settings.search.field"].firstMatch
            : app.textFields["settings.section.search"].firstMatch
        let startupLoading = app.otherElements["startup.loading.root"].firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if appRoot.exists && (settingsRoot.exists || searchField.exists || experienceTitle.exists) {
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
        assertExperienceSettingsOpened()
    }

    private func assertExperienceSettingsOpened() {
        XCTAssertTrue(
            app.navigationBars.staticTexts["Appearance, animations and haptics"].firstMatch.waitForExistence(timeout: 5),
            "Experience settings detail should open"
        )
    }

    private func assertAppearanceSegmentsExist() {
        XCTAssertTrue(app.buttons["System"].firstMatch.waitForExistence(timeout: 5), "System segment should be present")
        XCTAssertTrue(app.buttons["Light"].firstMatch.waitForExistence(timeout: 5), "Light segment should be present")
        XCTAssertTrue(app.buttons["Dark"].firstMatch.waitForExistence(timeout: 5), "Dark segment should be present")
    }

    private func scrollToTop(maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes {
            let searchField = app.textFields["settings.search.field"].firstMatch
            if searchField.exists {
                return
            }
            app.swipeDown()
        }
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
