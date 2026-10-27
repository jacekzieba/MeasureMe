import XCTest

/// iPhone Duo layouts. XCTest cannot change the device pose, so each test reads the layout the
/// app reports (`uitest.layout.<regular|compact>.<verticalBars|bottomBar>`) and checks what applies
/// to it: run the suite once on the folded Duo, once unfolded, and once on a regular iPhone.
final class DuoLayoutUITests: XCTestCase {
    private var app: XCUIApplication!
    private let customMetric = "custom_uitest_neck"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private struct Layout {
        let isRegular: Bool
        let hasVerticalBars: Bool
    }

    private func launch(_ extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForceOnboardingComplete",
            "-uiTestSeedMeasurements",
            "-uiTestForcePremium",
        ] + extraArguments
        app.launch()
    }

    /// The marker comes from the iOS 26+ tab bar code; earlier systems have neither FabBar nor
    /// vertical bars, so these layout checks do not apply there.
    private func currentLayout() throws -> Layout {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Layout marker exists from iOS 26")
        }
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'uitest.layout.'"))
            .firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15), "The app should report its layout")
        let identifier = marker.identifier
        return Layout(
            isRegular: identifier.contains(".regular."),
            hasVerticalBars: identifier.hasSuffix(".verticalBars")
        )
    }

    private func openTab(_ identifier: String) {
        let button = app.tabButton(identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 8), "\(identifier) should be in the tab bar")
        button.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Swipes `container` until `target` is on screen.
    private func scroll(_ container: XCUIElement, toReveal target: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !(target.exists && target.isHittable) && swipes < maxSwipes {
            container.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(target.exists && target.isHittable, "\(target) should be reachable by scrolling")
    }

    // MARK: - Tab bar

    @MainActor
    func testTabBarMatchesTheLayout() throws {
        launch()
        let layout = try currentLayout()

        if layout.hasVerticalBars {
            // HIG: on iPhone Duo the system tab bar moves to the side (it reports as part of a
            // toolbar there); the custom FabBar can't, so it must be hidden.
            XCTAssertTrue(
                app.toolbars.buttons["Settings"].waitForExistence(timeout: 8),
                "The system tab bar should be on the side"
            )
            XCTAssertFalse(app.segmentedControls.firstMatch.exists, "FabBar should be hidden")
        } else if !layout.isRegular {
            XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 8), "FabBar should be shown")
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "System tab bar should be shown")
        }
    }

    @MainActor
    func testEveryTabIsReachableFromTheTabBar() throws {
        launch()
        _ = try currentLayout()

        for (tab, title) in [
            ("tab.measurements", "measurements"),
            ("tab.photos", "photos"),
            ("tab.settings", "settings"),
            ("tab.home", "home"),
        ] {
            openTab(tab)
            XCTAssertTrue(
                element("uitest.debug.tab.\(title)").waitForExistence(timeout: 5),
                "\(tab) should select the \(title) tab"
            )
        }
    }

    // MARK: - Measurements

    @MainActor
    func testOpeningAMetricKeepsTheListBesideItOnTheWideScreen() throws {
        launch()
        try XCTSkipUnless(try currentLayout().isRegular, "List-and-detail split only appears at regular width")
        openTab("tab.measurements")

        let list = element("measurements.scroll")
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let waist = element("metric.tile.open.waist")
        scroll(list, toReveal: waist)
        waist.tap()

        XCTAssertTrue(element("metric.detail.waist").waitForExistence(timeout: 5), "Waist should open in the detail column")
        XCTAssertTrue(list.isHittable, "The metric list should stay visible beside the detail")
    }

    @MainActor
    func testOpeningACustomMetricKeepsTheListBesideItOnTheWideScreen() throws {
        launch(["-uiTestSeedCustomMetric"])
        try XCTSkipUnless(try currentLayout().isRegular, "List-and-detail split only appears at regular width")
        openTab("tab.measurements")

        let list = element("measurements.scroll")
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let tile = element("custom.metric.tile.open.\(customMetric)")
        scroll(list, toReveal: tile)
        tile.tap()

        XCTAssertTrue(
            element("custom.metric.detail.\(customMetric)").waitForExistence(timeout: 5),
            "The custom metric should open in the detail column"
        )
        XCTAssertTrue(list.isHittable, "The metric list should stay visible beside the detail")
    }

    @MainActor
    func testOpeningACustomMetricPushesItOnTheNarrowScreen() throws {
        launch(["-uiTestSeedCustomMetric"])
        try XCTSkipIf(try currentLayout().isRegular, "Covered by the wide-screen test")
        openTab("tab.measurements")

        let list = element("measurements.scroll")
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let tile = element("custom.metric.tile.open.\(customMetric)")
        scroll(list, toReveal: tile)
        tile.tap()

        let detail = element("custom.metric.detail.\(customMetric)")
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "The custom metric detail should be pushed")

        // Edge swipe rather than the Back button: on iPhone Duo Back sits on the vertical bar,
        // which is not a navigation bar.
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Back should return to the list")
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5), "Closing the detail should clear it")
    }

    // MARK: - Settings

    @MainActor
    func testSettingsShowsTheOpenSectionBesideTheListOnTheWideScreen() throws {
        launch()
        try XCTSkipUnless(try currentLayout().isRegular, "Settings split only appears at regular width")
        openTab("tab.settings")

        let list = element("settings.root")
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        XCTAssertTrue(
            element("settings.home.detail").waitForExistence(timeout: 5),
            "The first section should be open before anything is picked"
        )

        let units = element("settings.row.units")
        scroll(list, toReveal: units)
        units.tap()
        XCTAssertTrue(app.buttons["Imperial"].waitForExistence(timeout: 5), "Units should open beside the list")
        XCTAssertTrue(units.isHittable, "The settings list should stay visible")
    }

    @MainActor
    func testPremiumEditionRowOpensItsSection() throws {
        launch()
        _ = try currentLayout()
        openTab("tab.settings")

        let row = element("settings.row.premiumBenefits")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(
            app.staticTexts["Unlimited AI Body Insights"].waitForExistence(timeout: 5),
            "Premium Edition should open in both layouts"
        )
    }
}
