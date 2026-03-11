import XCTest

final class SettingsViewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-uiTestOpenSettingsTab"]
    }

    @MainActor
    func testSettingsNavigationReturnsDirectlyToOverviewAfterMultipleDetails() {
        app.launch()
        waitForAppShell()
        tapSettingsTab()

        let homeRow = app.staticTexts["Home"].firstMatch
        scrollToReveal(homeRow)
        XCTAssertTrue(homeRow.waitForExistence(timeout: 5), "Home row should exist in Settings")
        homeRow.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Home"].firstMatch.waitForExistence(timeout: 5), "Home detail should open")

        app.navigationBars.buttons.firstMatch.tap()
        let metricsRow = app.staticTexts["Metrics"].firstMatch
        scrollToReveal(metricsRow)
        XCTAssertTrue(metricsRow.waitForExistence(timeout: 5), "Back from Home should return to Settings overview")

        metricsRow.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Tracked measurements"].firstMatch.waitForExistence(timeout: 5), "Tracked measurements should open")

        app.navigationBars.buttons.firstMatch.tap()
        scrollToReveal(metricsRow)
        XCTAssertTrue(app.staticTexts["Metrics"].firstMatch.waitForExistence(timeout: 5), "Settings overview should remain visible after returning from Metrics")
        XCTAssertFalse(app.navigationBars.staticTexts["Tracked measurements"].firstMatch.exists, "Tracked measurements detail should be dismissed after going back")
        XCTAssertFalse(app.navigationBars.staticTexts["Home"].firstMatch.exists, "Settings should not backtrack through Home detail")
    }

    @MainActor
    func testDataSettingsExposeICloudBackupControls() {
        app.launch()
        waitForAppShell()
        openDataSettings()

        let backupToggle = app.descendants(matching: .any)["settings.data.icloud.toggle"].firstMatch
        XCTAssertTrue(backupToggle.waitForExistence(timeout: 5), "Expected iCloud backup toggle")

        let backupNowButton = app.descendants(matching: .any)["settings.data.icloud.backupNow"].firstMatch
        XCTAssertTrue(backupNowButton.exists, "Expected backup-now control")

        let restoreLatestButton = app.descendants(matching: .any)["settings.data.icloud.restoreLatest"].firstMatch
        XCTAssertTrue(restoreLatestButton.exists, "Expected restore-latest control")
    }

    @MainActor
    func testICloudBackupActionsArePremiumGated() {
        app.launchArguments = ["-uiTestMode", "-uiTestForceNonPremium"]
        app.launchArguments += ["-uiTestOpenSettingsTab"]
        app.launch()
        waitForAppShell()
        openDataSettings()

        let backupNowButton = app.descendants(matching: .any)["settings.data.icloud.backupNow"].firstMatch
        XCTAssertTrue(backupNowButton.waitForExistence(timeout: 5), "Expected backup-now control")
        backupNowButton.tap()

        let paywallCloseButton = app.buttons["Close Premium screen"].firstMatch
        XCTAssertTrue(paywallCloseButton.waitForExistence(timeout: 5), "Backup action should open paywall for non-premium users")

        let iCloudBenefit = app.descendants(matching: .any)["premium.carousel.unlock.item.icloud"].firstMatch
        for _ in 0..<4 where !iCloudBenefit.exists {
            app.swipeLeft()
        }
        XCTAssertTrue(iCloudBenefit.waitForExistence(timeout: 5), "Premium paywall should mention iCloud sync/backup on the last card")
    }

    @MainActor
    func testSettingsSearchOpensDetailAndBackReturnsToOverview() {
        app.launch()
        waitForAppShell()
        tapSettingsTab()

        let searchField = app.textFields["settings.search.field"].firstMatch.exists
            ? app.textFields["settings.search.field"].firstMatch
            : app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Settings search field should exist")
        searchField.tap()
        searchField.typeText("Health")

        let healthRow = app.staticTexts["Health"].firstMatch
        XCTAssertTrue(healthRow.waitForExistence(timeout: 5), "Health search result should exist")
        healthRow.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Health"].firstMatch.waitForExistence(timeout: 5), "Health detail should open from search")
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Back from searched detail should return to Settings overview")
        XCTAssertTrue(app.staticTexts["Home"].firstMatch.waitForExistence(timeout: 5), "Settings overview should be visible after returning from searched detail")
    }

    @MainActor
    func testSettingsPrimaryRoutesOpenRepresentativeDetails() {
        app.launch()
        waitForAppShell()
        tapSettingsTab()

        assertRoute("Home", opens: "Home")
        assertRoute("Notifications", opens: "Notifications")
        assertRoute("Data", opens: "Data")
        assertRoute("About", opens: "About")
    }

    private func tapSettingsTab() {
        if app.textFields["settings.search.field"].firstMatch.exists
            || app.textFields["settings.section.search"].firstMatch.exists
            || app.descendants(matching: .any)["settings.root"].firstMatch.exists {
            return
        }

        let candidates = ["tab.settings", "Settings", "Ustawienia"]
        for candidate in candidates {
            let button = app.buttons[candidate].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }

        for candidate in candidates {
            let element = app.descendants(matching: .any)[candidate].firstMatch
            if element.waitForExistence(timeout: 2) {
                element.tap()
                return
            }
        }

        XCTFail("Settings tab should exist")
    }

    private func waitForAppShell(timeout: TimeInterval = 20) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: min(timeout, 10)), "App should enter foreground before interacting with Settings")

        let appRoot = app.otherElements["app.root.ready"].firstMatch
        let settingsRoot = app.descendants(matching: .any)["settings.root"].firstMatch
        let searchField = app.textFields["settings.search.field"].firstMatch.exists
            ? app.textFields["settings.search.field"].firstMatch
            : app.textFields["settings.section.search"].firstMatch
        let searchSection = app.descendants(matching: .any)["settings.section.search"].firstMatch
        let accountSection = app.descendants(matching: .any)["settings.section.account"].firstMatch
        let supportSection = app.descendants(matching: .any)["settings.section.support"].firstMatch
        let startupLoading = app.otherElements["startup.loading.root"].firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if appRoot.exists && (settingsRoot.exists || searchField.exists || searchSection.exists || accountSection.exists || supportSection.exists) {
                return
            }
            if startupLoading.exists {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                continue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail("Settings overview should become ready before interacting with the screen. Debug tree: \(app.debugDescription)")
    }

    private func openDataSettings() {
        tapSettingsTab()
        let dataRowLabel = app.staticTexts["Data"].firstMatch
        scrollToReveal(dataRowLabel)
        XCTAssertTrue(dataRowLabel.waitForExistence(timeout: 5), "Data row should exist in Settings")
        dataRowLabel.tap()
    }

    private func assertRoute(_ rowTitle: String, opens navigationTitle: String) {
        let row = app.staticTexts[rowTitle].firstMatch
        scrollToReveal(row)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(rowTitle) row should exist in Settings")
        row.tap()
        XCTAssertTrue(app.navigationBars.staticTexts[navigationTitle].firstMatch.waitForExistence(timeout: 5), "\(navigationTitle) detail should open")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts[rowTitle].firstMatch.waitForExistence(timeout: 5), "Back from \(navigationTitle) should return to Settings overview")
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
