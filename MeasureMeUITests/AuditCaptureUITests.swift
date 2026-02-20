import XCTest

final class AuditCaptureUITests: XCTestCase {
    private enum TabLabel {
        static let home = ["Home", "Start", "Dom"]
        static let measurements = ["Measurements", "Pomiary"]
        static let photos = ["Photos", "Zdjęcia", "Zdjecia"]
        static let settings = ["Settings", "Ustawienia"]
    }

    private lazy var outputDirectory: URL = {
        let env = ProcessInfo.processInfo.environment
        let rawPath = env["AUDIT_OUTPUT_DIR"] ?? "\(NSTemporaryDirectory())MeasureMeAudit"
        let url = URL(fileURLWithPath: rawPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var appearance: String { sanitizePart(ProcessInfo.processInfo.environment["AUDIT_APPEARANCE"] ?? "light") }
    private var dynamicType: String { sanitizePart(ProcessInfo.processInfo.environment["AUDIT_DTYPE"] ?? "default") }
    private var a11yFlags: String { sanitizePart(ProcessInfo.processInfo.environment["AUDIT_A11Y_FLAGS"] ?? "none") }
    private var deviceName: String { sanitizePart(ProcessInfo.processInfo.environment["AUDIT_DEVICE"] ?? "unknown-device") }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureCoreScreens() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "24",
            "-uiTestForcePremium",
            "-uiTestBypassHealthSummaryGuards",
            "-uiTestLongHealthInsight",
            "-auditCapture",
            "-useMockData",
            "-disableAnalytics",
            "-fixedDate", "2026-02-20T12:00:00Z"
        ]
        app.launchEnvironment["AUDIT_CAPTURE"] = "1"
        app.launchEnvironment["MOCK_DATA"] = "1"
        app.launchEnvironment["NETWORK_STUB"] = "1"
        app.launchEnvironment["FIXED_DATE"] = "2026-02-20T12:00:00Z"
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        openTab(app, candidates: TabLabel.home)
        _ = app.buttons["home.quickadd.button"].waitForExistence(timeout: 5)
        saveScreenshot(screen: "home_dashboard")

        openTab(app, candidates: TabLabel.measurements)
        XCTAssertTrue(app.scrollViews["measurements.scroll"].waitForExistence(timeout: 8))
        app.swipeUp()
        saveScreenshot(screen: "measurements_list_scroll")

        if let metricButton = firstExistingMetricTile(in: app) {
            metricButton.tap()
            sleep(1)
            saveScreenshot(screen: "metric_detail")
            navigateBack(app)
        }

        openTab(app, candidates: TabLabel.photos)
        let gridItem = app.buttons["photos.grid.item"].firstMatch
        if gridItem.waitForExistence(timeout: 8) {
            app.swipeUp()
            saveScreenshot(screen: "photos_grid_scroll")
            gridItem.tap()
            sleep(1)
            saveScreenshot(screen: "photo_detail")
            navigateBack(app)
        } else {
            saveScreenshot(screen: "photos_empty")
        }

        openTab(app, candidates: TabLabel.settings)
        sleep(1)
        saveScreenshot(screen: "settings")
    }

    @MainActor
    func testCaptureQuickAddStates() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-auditCapture",
            "-useMockData",
            "-fixedDate", "2026-02-20T12:00:00Z"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        openTab(app, candidates: TabLabel.home)
        let quickAddButton = app.buttons["home.quickadd.button"].firstMatch
        XCTAssertTrue(quickAddButton.waitForExistence(timeout: 8))
        quickAddButton.tap()

        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8))

        let anyInput = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'quickadd.input.'")).firstMatch
        if anyInput.waitForExistence(timeout: 4) {
            anyInput.tap()
            anyInput.typeText("9999")
            saveScreenshot(screen: "quickadd_form_keyboard")

            _ = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'quickadd.error.'")).firstMatch.waitForExistence(timeout: 2)
            saveScreenshot(screen: "quickadd_error")
        } else {
            saveScreenshot(screen: "quickadd_form")
        }

        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else {
            app.swipeDown()
        }

        app.terminate()

        let emptyApp = XCUIApplication()
        emptyApp.launchArguments = [
            "-uiTestMode",
            "-uiTestNoActiveMetrics",
            "-auditCapture",
            "-useMockData",
            "-fixedDate", "2026-02-20T12:00:00Z"
        ]
        emptyApp.launch()
        XCTAssertTrue(emptyApp.wait(for: .runningForeground, timeout: 10))

        let emptyQuickAddButton = emptyApp.buttons["home.quickadd.button"]
        XCTAssertTrue(emptyQuickAddButton.waitForExistence(timeout: 8))
        emptyQuickAddButton.tap()
        _ = emptyApp.otherElements["quickadd.empty"].waitForExistence(timeout: 8)
        saveScreenshot(screen: "quickadd_empty")
    }

    @MainActor
    func testCaptureOnboardingAndPaywall() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestOnboardingMode",
            "-auditCapture",
            "-useMockData",
            "-fixedDate", "2026-02-20T12:00:00Z"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
        saveScreenshot(screen: "onboarding_welcome")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.textFields["onboarding.profile.name"].waitForExistence(timeout: 8))
        saveScreenshot(screen: "onboarding_profile")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.booster.reminders"].waitForExistence(timeout: 8))
        saveScreenshot(screen: "onboarding_boosters")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.premium.restore"].waitForExistence(timeout: 8))
        saveScreenshot(screen: "paywall_onboarding")
    }

    private func openTab(_ app: XCUIApplication, candidates: [String]) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Expected tab bar.")
        for label in candidates {
            let button = tabBar.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }

        let prefixQuery = tabBar.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", candidates.first ?? ""))
        if prefixQuery.firstMatch.exists {
            prefixQuery.firstMatch.tap()
            return
        }

        if let fallbackIndex = fallbackTabIndex(for: candidates) {
            let buttons = tabBar.buttons.allElementsBoundByIndex
            if buttons.indices.contains(fallbackIndex) {
                buttons[fallbackIndex].tap()
                return
            }
        }

        XCTFail("Could not find tab with labels: \(candidates.joined(separator: ", "))")
    }

    private func fallbackTabIndex(for candidates: [String]) -> Int? {
        if candidates.contains(where: { $0.caseInsensitiveCompare("Home") == .orderedSame || $0.caseInsensitiveCompare("Start") == .orderedSame || $0.caseInsensitiveCompare("Dom") == .orderedSame }) {
            return 0
        }
        if candidates.contains(where: { $0.caseInsensitiveCompare("Measurements") == .orderedSame || $0.caseInsensitiveCompare("Pomiary") == .orderedSame }) {
            return 1
        }
        if candidates.contains(where: { $0.caseInsensitiveCompare("Photos") == .orderedSame || $0.caseInsensitiveCompare("Zdjęcia") == .orderedSame || $0.caseInsensitiveCompare("Zdjecia") == .orderedSame }) {
            return 2
        }
        if candidates.contains(where: { $0.caseInsensitiveCompare("Settings") == .orderedSame || $0.caseInsensitiveCompare("Ustawienia") == .orderedSame }) {
            return 3
        }
        return nil
    }

    private func firstExistingMetricTile(in app: XCUIApplication) -> XCUIElement? {
        let preferred = app.buttons["metric.tile.open.weight"]
        if preferred.waitForExistence(timeout: 2) {
            return preferred
        }

        let allMetricTiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'metric.tile.open.'"))
        guard allMetricTiles.firstMatch.waitForExistence(timeout: 3) else { return nil }
        return allMetricTiles.firstMatch
    }

    private func navigateBack(_ app: XCUIApplication) {
        let navBar = app.navigationBars.firstMatch
        let candidates = [TabLabel.measurements, TabLabel.photos, TabLabel.settings, TabLabel.home]
            .flatMap { $0 }

        let preferredSystemBackLabels = ["Close", "Done", "Back", "Cancel", "Zamknij", "Gotowe", "Wstecz"]
        for label in preferredSystemBackLabels {
            let button = navBar.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }

        for candidate in candidates {
            let button = navBar.buttons[candidate]
            if button.exists {
                button.tap()
                return
            }
        }

        if navBar.buttons.firstMatch.exists {
            navBar.buttons.firstMatch.tap()
        }
    }

    private func saveScreenshot(screen: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let fileName = "\(sanitizePart(screen))__\(appearance)__\(dynamicType)__\(a11yFlags)__\(deviceName).png"
        let url = outputDirectory.appendingPathComponent(fileName)
        do {
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Failed to save screenshot to \(url.path): \(error)")
        }
    }

    private func sanitizePart(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "__", with: "-")
    }
}
