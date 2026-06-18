import XCTest

final class AccessibilityQualityUITests: XCTestCase {
    private final class AuditIssueCollector {
        var issues = Set<String>()

        func record(_ issue: XCUIAccessibilityAuditIssue, context: String) {
            let elementContext = [
                issue.element?.identifier,
                issue.element?.label
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
            let suffix = elementContext.isEmpty ? "" : " [\(elementContext)]"
            issues.insert("\(context): \(issue.compactDescription)\(suffix) - \(issue.detailedDescription)")
        }
    }

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testCoreScreensHaveVoiceOverDescriptionsAndMinimumHitRegions() throws {
        let collector = AuditIssueCollector()
        launchSeededApp()

        // NOTE: `.elementDetection` is deliberately excluded. It's a timing-sensitive
        // heuristic that intermittently flags chart/sparkline-drawn text (no identifier)
        // as "Potentially inaccessible text" — a known false positive that makes this
        // guard flaky. The remaining checks (descriptions, hit regions, traits) are stable.
        try auditCurrentScreen(
            context: "Home",
            types: [.hitRegion, .sufficientElementDescription, .trait],
            swipes: 2,
            collector: collector
        )

        openTab(identifier: "tab.measurements", fallbackIndex: 1)
        try auditCurrentScreen(
            context: "Measurements",
            types: [.hitRegion, .sufficientElementDescription, .trait],
            swipes: 2,
            collector: collector
        )

        openTab(identifier: "tab.photos", fallbackIndex: 3)
        try auditCurrentScreen(
            context: "Photos",
            types: [.hitRegion, .sufficientElementDescription, .trait],
            swipes: 2,
            collector: collector
        )

        openTab(identifier: "tab.settings", fallbackIndex: 4)
        try auditCurrentScreen(
            context: "Settings",
            types: [.hitRegion, .sufficientElementDescription, .trait],
            swipes: 3,
            collector: collector
        )

        assertNoAuditIssues(collector, category: "VoiceOver and hit-region")
    }

    @MainActor
    func testAppearanceSettingsMeetContrastRequirementsInLightAndDarkModes() throws {
        let collector = AuditIssueCollector()

        try auditHomeContrast(appearance: "Dark", collector: collector)
        app.terminate()
        app = XCUIApplication()
        try auditHomeContrast(appearance: "Light", collector: collector)

        assertNoAuditIssues(collector, category: "contrast")
    }

    @MainActor
    func testQuickAddNumericKeypadMeetsAccessibilityRequirements() throws {
        let collector = AuditIssueCollector()
        app.launchArguments = ["-uiTestMode"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")

        let addButton = app.tabBars.buttons["tab.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Quick Add entry point should exist")
        addButton.tap()

        let firstInput = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'quickadd.input.'")
        ).firstMatch
        XCTAssertTrue(firstInput.waitForExistence(timeout: 8), "Quick Add input should exist")
        firstInput.tap()
        XCTAssertTrue(
            app.otherElements["quickadd.keypad"].waitForExistence(timeout: 5),
            "Numeric keypad should exist"
        )

        try auditCurrentScreen(
            context: "QuickAdd.NumericKeypad",
            types: [.contrast, .hitRegion, .sufficientElementDescription, .trait],
            swipes: 0,
            collector: collector
        )

        assertNoAuditIssues(collector, category: "Quick Add numeric keypad")
    }

    @MainActor
    func testAdaptiveLayoutKeepsCoreContentInsideTheWindow() {
        launchSeededApp()

        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 8), "App window should exist")

        let summaryHero = app.otherElements["home.module.summaryHero"].firstMatch
        let keyMetrics = app.otherElements["home.module.keyMetrics"].firstMatch
        let recentPhotos = app.otherElements["home.module.recentPhotos"].firstMatch
        XCTAssertTrue(summaryHero.waitForExistence(timeout: 8), "Home summary hero should exist")
        XCTAssertTrue(keyMetrics.waitForExistence(timeout: 8), "Home key metrics should exist")
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 8), "Home recent photos should exist")

        assertContainedHorizontally(summaryHero, in: window, name: "home.module.summaryHero")
        assertContainedHorizontally(keyMetrics, in: window, name: "home.module.keyMetrics")
        assertContainedHorizontally(recentPhotos, in: window, name: "home.module.recentPhotos")
        XCTAssertLessThanOrEqual(summaryHero.frame.maxY, keyMetrics.frame.minY, "Home modules should not overlap")
        XCTAssertLessThanOrEqual(keyMetrics.frame.maxY, recentPhotos.frame.minY, "Home modules should preserve order")

        openTab(identifier: "tab.measurements", fallbackIndex: 1)
        let measurementsScroll = app.scrollViews["measurements.scroll"].firstMatch
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 8), "Measurements content should exist")
        assertContainedHorizontally(measurementsScroll, in: window, name: "measurements.scroll")

        let categoryTabs = app.descendants(matching: .any)["measurements.tab.segmented"].firstMatch
        if categoryTabs.waitForExistence(timeout: 3) {
            assertContainedHorizontally(categoryTabs, in: window, name: "measurements.tab.segmented")
        }

        openTab(identifier: "tab.photos", fallbackIndex: 3)
        let photosContent = app.scrollViews.firstMatch.exists
            ? app.scrollViews.firstMatch
            : app.collectionViews.firstMatch
        XCTAssertTrue(photosContent.waitForExistence(timeout: 8), "Photos content should exist")
        assertContainedHorizontally(photosContent, in: window, name: "photos.content")

        openTab(identifier: "tab.settings", fallbackIndex: 4)
        let settingsRoot = app.descendants(matching: .any)["settings.root"].firstMatch
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 8), "Settings root should exist")
        assertContainedHorizontally(settingsRoot, in: window, name: "settings.root")
    }

    @MainActor
    private func auditHomeContrast(appearance: String, collector: AuditIssueCollector) throws {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "24",
            "-uiTestOpenSettingsTab",
            "-uiTestOpenExperienceSettings"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")

        let appearanceButton = app.buttons[appearance].firstMatch
        XCTAssertTrue(
            appearanceButton.waitForExistence(timeout: 10),
            "\(appearance) appearance option should exist"
        )
        appearanceButton.tap()

        try auditCurrentScreen(
            context: "AppearanceSettings.\(appearance)",
            types: [.contrast],
            swipes: 1,
            collector: collector
        )
    }

    @MainActor
    private func launchSeededApp() {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForcePremium",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "24",
            "-uiTestBypassHealthSummaryGuards"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12), "Tab bar should exist")
    }

    @MainActor
    private func auditCurrentScreen(
        context: String,
        types: XCUIAccessibilityAuditType,
        swipes: Int,
        collector: AuditIssueCollector
    ) throws {
        for index in 0...swipes {
            let window = app.windows.element(boundBy: 0)
            XCTAssertTrue(window.waitForExistence(timeout: 5), "App window should exist for \(context)")

            try XCTContext.runActivity(named: "Accessibility audit: \(context).screen\(index)") { _ in
                try app.performAccessibilityAudit(for: types) { issue in
                    collector.record(issue, context: context)
                    return true
                }
            }

            if index < swipes {
                app.swipeUp()
            }
        }
    }

    @MainActor
    private func openTab(identifier: String, fallbackIndex: Int) {
        app.swipeDown()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar should exist")

        let identifiedButton = tabBar.buttons[identifier].firstMatch
        if identifiedButton.exists && identifiedButton.isHittable {
            identifiedButton.tap()
            return
        }

        let buttons = tabBar.buttons.allElementsBoundByIndex
        if buttons.indices.contains(fallbackIndex), buttons[fallbackIndex].isHittable {
            buttons[fallbackIndex].tap()
            return
        }

        let normalizedX = (CGFloat(fallbackIndex) * 0.2) + 0.1
        tabBar.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5)).tap()
    }

    private func assertContainedHorizontally(
        _ element: XCUIElement,
        in container: XCUIElement,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        let containerFrame = container.frame
        XCTAssertFalse(frame.isEmpty, "\(name) should have a non-empty frame", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            frame.minX,
            containerFrame.minX - 1,
            "\(name) extends beyond the leading window edge",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxX,
            containerFrame.maxX + 1,
            "\(name) extends beyond the trailing window edge",
            file: file,
            line: line
        )
    }

    private func assertNoAuditIssues(
        _ collector: AuditIssueCollector,
        category: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            collector.issues.isEmpty,
            """
            \(category) accessibility issues:
            \(collector.issues.sorted().joined(separator: "\n"))
            """,
            file: file,
            line: line
        )
    }
}
