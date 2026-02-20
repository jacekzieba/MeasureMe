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
        XCTAssertTrue(openQuickAdd(app))

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

        XCTAssertTrue(openQuickAdd(emptyApp))
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

    @MainActor
    func testAccessibilityXLRegressionGuards() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestSeedMeasurements",
            "-auditCapture",
            "-useMockData",
            "-fixedDate", "2026-02-20T12:00:00Z",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"
        ]
        app.launchEnvironment["AUDIT_CAPTURE"] = "1"
        app.launchEnvironment["MOCK_DATA"] = "1"
        app.launchEnvironment["FIXED_DATE"] = "2026-02-20T12:00:00Z"
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openTab(app, candidates: TabLabel.measurements)

        let tileButton = app.buttons["metric.tile.open.weight"].firstMatch
        XCTAssertTrue(tileButton.waitForExistence(timeout: 8))
        XCTAssertTrue(tileButton.isHittable)

        openTab(app, candidates: TabLabel.home)
        XCTAssertTrue(openQuickAdd(app))

        let saveButton = app.buttons["quickadd.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 8))

        let validationHint = app.staticTexts["quickadd.validation.hint"]
        XCTAssertTrue(validationHint.waitForExistence(timeout: 4))
        scrollToReveal(validationHint, in: app)
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(isPartiallyVisible(validationHint, in: window))
        XCTAssertTrue(framesDoNotOverlap(validationHint, saveButton))

        app.terminate()

        let onboardingApp = XCUIApplication()
        onboardingApp.launchArguments = [
            "-uiTestOnboardingMode",
            "-auditCapture",
            "-useMockData",
            "-fixedDate", "2026-02-20T12:00:00Z",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"
        ]
        onboardingApp.launch()

        XCTAssertTrue(onboardingApp.wait(for: .runningForeground, timeout: 10))
        let onboardingNext = onboardingApp.buttons["onboarding.next"]
        XCTAssertTrue(onboardingNext.waitForExistence(timeout: 8))
        onboardingNext.tap()
        onboardingNext.tap()
        onboardingNext.tap()

        let onboardingBack = onboardingApp.buttons["onboarding.back"]
        let onboardingTrial = onboardingApp.buttons["onboarding.premium.trial"]
        XCTAssertTrue(onboardingBack.waitForExistence(timeout: 8))
        XCTAssertTrue(onboardingBack.isHittable)
        XCTAssertTrue(onboardingTrial.waitForExistence(timeout: 8))
        scrollToReveal(onboardingTrial, in: onboardingApp, maxSwipes: 6)
        XCTAssertTrue(onboardingTrial.isHittable)
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

        for label in candidates {
            let prefixQuery = tabBar.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", label))
            if prefixQuery.firstMatch.exists {
                prefixQuery.firstMatch.tap()
                return
            }

            let containsQuery = tabBar.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label))
            if containsQuery.firstMatch.exists {
                containsQuery.firstMatch.tap()
                return
            }
        }

        if let fallbackIndex = fallbackTabIndex(for: candidates) {
            let buttons = tabBar.buttons.allElementsBoundByIndex
            if buttons.indices.contains(fallbackIndex) {
                buttons[fallbackIndex].tap()
                return
            }

            if let normalizedX = fallbackTabNormalizedX(for: fallbackIndex) {
                let coordinate = tabBar.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5))
                coordinate.tap()
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
            return 3
        }
        if candidates.contains(where: { $0.caseInsensitiveCompare("Settings") == .orderedSame || $0.caseInsensitiveCompare("Ustawienia") == .orderedSame }) {
            return 4
        }
        return nil
    }

    private func fallbackTabNormalizedX(for tabIndex: Int) -> CGFloat? {
        switch tabIndex {
        case 0: return 0.10 // Home
        case 1: return 0.30 // Measurements
        case 3: return 0.70 // Photos
        case 4: return 0.90 // Settings
        default: return nil
        }
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

    private func openQuickAdd(_ app: XCUIApplication) -> Bool {
        let quickAddButton = app.buttons["home.quickadd.button"].firstMatch
        if quickAddButton.waitForExistence(timeout: 4) {
            quickAddButton.tap()
            return true
        }

        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            let addCandidates = ["Add", "Dodaj", "+"]
            for candidate in addCandidates {
                let button = tabBar.buttons[candidate]
                if button.exists {
                    button.tap()
                    return true
                }
            }

            let addByPrefix = tabBar.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Add")).firstMatch
            if addByPrefix.exists {
                addByPrefix.tap()
                return true
            }
        }

        return false
    }

    private func scrollToReveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 4) {
        guard element.exists else { return }
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

    private func framesDoNotOverlap(_ first: XCUIElement, _ second: XCUIElement) -> Bool {
        guard first.exists, second.exists else { return false }
        let firstFrame = first.frame
        let secondFrame = second.frame
        guard !firstFrame.isEmpty, !secondFrame.isEmpty else { return false }
        return firstFrame.intersection(secondFrame).isNull
    }

    private func sanitizePart(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "__", with: "-")
    }
}
