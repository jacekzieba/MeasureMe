/// Cel testow: Weryfikuje kluczowe interakcje Home po przebudowie do widget board.
/// Dlaczego to wazne: Home jest teraz ekranem decyzji, nie tylko lista sekcji.
/// Kryteria zaliczenia: Layout jest stabilny, CTA dzialaja, a premium/non-premium flow nie regresuje.

import XCTest

final class HomeViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testHealthModuleIsReachableOnHome() {
        launchApp(isPremium: false)

        let healthTitle = app.staticTexts["Health"].firstMatch
        scrollToReveal(healthTitle, maxSwipes: 6)

        XCTAssertTrue(healthTitle.waitForExistence(timeout: 5), "Health section should be reachable on Home")
        XCTAssertGreaterThan(healthTitle.frame.height, 10, "Health title should have a visible frame")
        XCTAssertTrue(app.buttons["home.health.premium.button"].waitForExistence(timeout: 5), "Health preview should upsell the full module without premium")
        XCTAssertEqual(app.staticTexts["home.health.preview.label"].firstMatch.label, "BMI (Body Mass Index)", "Non-premium Health preview should prefer expanded BMI copy on Home")
        XCTAssertEqual(app.staticTexts["home.health.preview.badge"].firstMatch.label, "Normal weight", "Non-premium BMI preview should expose the BMI range classification on Home")
    }

    func testHomeDashboardModulesDoNotOverlap() {
        launchApp()

        let keyMetrics = app.otherElements["home.module.keyMetrics"].firstMatch
        let recentPhotos = app.otherElements["home.module.recentPhotos"].firstMatch
        let healthSummary = app.otherElements["home.module.healthSummary"].firstMatch

        XCTAssertTrue(keyMetrics.waitForExistence(timeout: 5), "Key metrics card frame hook should exist")
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos card frame hook should exist")
        scrollToReveal(healthSummary, maxSwipes: 6)
        XCTAssertTrue(healthSummary.waitForExistence(timeout: 5), "Health card frame hook should exist")

        XCTAssertTrue(framesDoNotOverlap(keyMetrics, recentPhotos), "Key metrics and Recent photos must not overlap")
        XCTAssertTrue(framesDoNotOverlap(recentPhotos, healthSummary), "Recent photos and Health must not overlap")
        XCTAssertLessThanOrEqual(keyMetrics.frame.maxY, recentPhotos.frame.minY, "Recent photos should start after Key metrics ends")
        XCTAssertLessThanOrEqual(recentPhotos.frame.maxY, healthSummary.frame.minY, "Health should start after Recent photos ends")
    }

    func testRecentPhotosShowsThreeTiles() {
        launchApp()

        let recentPhotos = app.staticTexts["Recent photos"].firstMatch
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos module should exist")

        let tileCount = app.staticTexts["home.recentPhotos.tileCount"].firstMatch
        XCTAssertTrue(tileCount.waitForExistence(timeout: 5), "Recent photos tile count hook should exist")
        XCTAssertEqual(tileCount.label, "3", "Recent photos should expose three visible tiles on Home")
    }

    func testActivationHubStartsAfterFirstMeasurementOnPhotoTask() {
        launchApp(extraArguments: [
            "-uiTestActivationHub",
            "-uiTestActivationTask", "addPhoto"
        ], isPremium: false, seedMeasurements: true, seedPhotos: 0)

        XCTAssertTrue(app.otherElements["home.module.activationHub"].waitForExistence(timeout: 5), "Activation hub should be visible on Home")
        XCTAssertTrue(app.staticTexts["Add your first photo"].waitForExistence(timeout: 5), "Activation hub should start after the first measurement, on the photo task")
    }

    func testActivationHubSkipAdvancesToNextTask() {
        launchApp(extraArguments: [
            "-uiTestActivationHub",
            "-uiTestActivationTask", "chooseMetrics"
        ], isPremium: false, seedMeasurements: true, seedPhotos: 0)

        let activationHub = app.otherElements["home.module.activationHub"].firstMatch
        XCTAssertTrue(activationHub.waitForExistence(timeout: 5), "Activation hub should be visible on Home")
        XCTAssertTrue(app.staticTexts["Choose what to track"].waitForExistence(timeout: 5), "Activation hub should expose the requested task")

        let skipButton = app.buttons["home.activation.skip"].firstMatch
        scrollToReveal(skipButton, maxSwipes: 6)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Activation hub skip should exist")
        skipButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Set your first goal"].waitForExistence(timeout: 5), "Skip should move the user to the next real activation task")
    }

    func testNextFocusShowsMetricInsightWhenProgressExists() {
        launchApp()

        let nextFocusMode = app.staticTexts["home.nextFocus.mode"].firstMatch
        XCTAssertTrue(nextFocusMode.waitForExistence(timeout: 5), "Next focus mode hook should exist")
        let nextFocusButton = nextFocusTrigger()
        XCTAssertTrue(nextFocusButton.waitForExistence(timeout: 5), "Next focus trigger should exist")
        XCTAssertEqual(nextFocusMode.label, "metric", "Seeded measurements should produce a metric insight")
        nextFocusButton.tap()

        let measurementsScroll = app.scrollViews["measurements.scroll"].firstMatch
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 5), "Metric insight should open Measurements")
    }

    func testNextFocusLongInsightFitsAtAccessibilityXL() {
        launchApp(extraArguments: [
            "-uiTestLongNextFocusInsight",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
            "-AppleLanguages", "(pl)",
            "-AppleLocale", "pl_PL"
        ])

        let primaryValue = app.staticTexts["home.nextFocus.primaryValue"].firstMatch
        let summary = app.staticTexts["home.nextFocus.summary"].firstMatch

        XCTAssertTrue(nextFocusTrigger().waitForExistence(timeout: 5), "Next focus trigger should exist")
        XCTAssertTrue(primaryValue.waitForExistence(timeout: 5), "Primary stat should exist")
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Summary should exist")

        let buttonFrame = nextFocusTrigger().frame
        let primaryValueFrame = primaryValue.frame
        let summaryFrame = summary.frame

        XCTAssertFalse(buttonFrame.isEmpty, "Next focus button should have a visible frame")
        XCTAssertFalse(primaryValueFrame.isEmpty, "Primary stat should have a visible frame")
        XCTAssertFalse(summaryFrame.isEmpty, "Summary should have a visible frame")
        XCTAssertGreaterThan(primaryValueFrame.width, 40, "Primary stat should remain readable")
        XCTAssertLessThan(primaryValueFrame.height, 42, "Primary stat should stay compact and one-line")
        XCTAssertGreaterThan(summaryFrame.height, 16, "Summary should remain visible at larger text sizes")
        XCTAssertLessThan(summaryFrame.height, 90, "Summary should stay within a compact two-line block")
        XCTAssertGreaterThanOrEqual(primaryValueFrame.minY, buttonFrame.minY, "Primary stat should stay inside the card")
        XCTAssertLessThanOrEqual(summaryFrame.maxY, buttonFrame.maxY, "Summary should stay inside the card")
        XCTAssertLessThan(primaryValueFrame.maxY, summaryFrame.minY, "Primary stat and summary should not overlap")
        XCTAssertLessThan(buttonFrame.height, 150, "Stat-first layout should keep the card shorter than the previous version")
    }

    func testNextFocusFallbackSetGoalSwitchesToMeasurementsTab() {
        launchApp(isPremium: false, seedMeasurements: false)

        let nextFocusMode = app.staticTexts["home.nextFocus.mode"].firstMatch
        XCTAssertTrue(nextFocusMode.waitForExistence(timeout: 5), "Next focus mode hook should exist")
        let nextFocusButton = nextFocusTrigger()
        XCTAssertTrue(nextFocusButton.waitForExistence(timeout: 5), "Next focus trigger should exist")
        XCTAssertEqual(nextFocusMode.label, "setGoal", "No positive measurement insight should fall back to Set goal")
        nextFocusButton.tap()

        let measurementsScroll = app.scrollViews["measurements.scroll"].firstMatch
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 5), "Set goal fallback should open Measurements")
    }

    func testNoGoalsStatusChipOpensMeasurements() {
        launchApp(isPremium: false, seedMeasurements: false)

        let goalStatusButton = app.buttons["home.goalStatus.button"].firstMatch
        XCTAssertTrue(goalStatusButton.waitForExistence(timeout: 5), "No-goals status chip should become tappable")
        goalStatusButton.tap()

        let measurementsScroll = app.scrollViews["measurements.scroll"].firstMatch
        XCTAssertTrue(measurementsScroll.waitForExistence(timeout: 5), "Tapping the no-goals chip should open Measurements")
    }

    func testTrialReminderPromptShowsDeclineAndConfirm() {
        launchApp(extraArguments: ["-uiTestShowTrialReminderPrompt"])

        let decline = app.buttons["premium.trial.reminder.prompt.decline"].firstMatch.exists
            ? app.buttons["premium.trial.reminder.prompt.decline"].firstMatch
            : app.descendants(matching: .any)["premium.trial.reminder.prompt.decline"].firstMatch
        let confirm = app.buttons["premium.trial.reminder.prompt.confirm"].firstMatch.exists
            ? app.buttons["premium.trial.reminder.prompt.confirm"].firstMatch
            : app.descendants(matching: .any)["premium.trial.reminder.prompt.confirm"].firstMatch

        XCTAssertTrue(
            decline.waitForExistence(timeout: 8) || app.buttons["No"].firstMatch.exists || app.buttons["Nie"].firstMatch.exists,
            "Trial reminder prompt should show No"
        )
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 8)
                || app.buttons["Yes, remind me"].firstMatch.exists
                || app.buttons["Tak, przypomnij mi"].firstMatch.exists,
            "Trial reminder prompt should show confirm action"
        )
    }

    func testRecentPhotosCompareOpensPaywallForNonPremiumUsers() {
        launchApp(isPremium: false)

        let compareButton = app.buttons["home.recentPhotos.compare.button"].firstMatch
        XCTAssertTrue(compareButton.waitForExistence(timeout: 5), "Recent photos compare card should exist")
        compareButton.tap()

        XCTAssertTrue(app.buttons["Close Premium screen"].waitForExistence(timeout: 5), "Non-premium compare tap should open the paywall")
    }

    func testRecentPhotosCompareOpensChooserAndCompareForPremiumUsers() {
        launchApp(seedPhotos: 24)

        let compareButton = app.buttons["home.recentPhotos.compare.button"].firstMatch
        XCTAssertTrue(compareButton.waitForExistence(timeout: 5), "Recent photos compare card should exist")
        compareButton.tap()

        let filteredCount = app.staticTexts["home.compare.filteredCount"].firstMatch
        XCTAssertTrue(filteredCount.waitForExistence(timeout: 5), "Chooser should expose filtered photo count")
        XCTAssertEqual(filteredCount.label, "24", "Chooser should start with the full photo library")
        XCTAssertTrue(app.buttons["home.compare.filter.all"].waitForExistence(timeout: 5), "Chooser should expose the time filter")
        XCTAssertTrue(app.buttons["home.compare.selectTwoHook"].waitForExistence(timeout: 5), "UI test hook should exist in chooser")
        app.buttons["home.compare.selectTwoHook"].tap()

        XCTAssertTrue(app.buttons["photos.compare.done"].waitForExistence(timeout: 5), "Choosing two photos should open compare view")
    }

    func testSecondaryMetricExpandsInlineWithoutOverlappingRecentPhotos() {
        launchApp()

        let secondaryMetricToggle = firstExistingElement(
            identifiers: [
                "home.keyMetrics.secondary.bodyFat.toggle",
                "home.keyMetrics.secondary.leanBodyMass.toggle",
                "home.keyMetrics.secondary.waist.toggle"
            ],
            query: app.buttons
        )
        XCTAssertTrue(secondaryMetricToggle.waitForExistence(timeout: 5), "A secondary key metric row should exist")
        secondaryMetricToggle.tap()

        let expandedPanel = firstExistingElement(
            identifiers: [
                "home.keyMetrics.secondary.bodyFat.expanded",
                "home.keyMetrics.secondary.leanBodyMass.expanded",
                "home.keyMetrics.secondary.waist.expanded"
            ],
            query: app.otherElements
        )
        XCTAssertTrue(expandedPanel.waitForExistence(timeout: 5), "Secondary metric should expand inline")

        let keyMetrics = app.otherElements["home.module.keyMetrics"].firstMatch
        let recentPhotos = app.otherElements["home.module.recentPhotos"].firstMatch
        XCTAssertTrue(keyMetrics.waitForExistence(timeout: 5), "Key metrics module should exist")
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos module should exist")

        XCTAssertTrue(framesDoNotOverlap(keyMetrics, recentPhotos), "Expanded key metrics should not overlap Recent photos")
        XCTAssertLessThanOrEqual(keyMetrics.frame.maxY, recentPhotos.frame.minY, "Recent photos should still start after Key metrics")
    }

    func testSecondaryMetricsCanStayExpandedTogether() {
        launchApp()

        let expandedCount = app.staticTexts["home.keyMetrics.secondary.expandedCount"].firstMatch
        let expandedIDs = app.staticTexts["home.keyMetrics.secondary.expandedIDs"].firstMatch
        XCTAssertTrue(expandedCount.waitForExistence(timeout: 5), "Expanded secondary metric count hook should exist")
        XCTAssertTrue(expandedIDs.waitForExistence(timeout: 5), "Expanded secondary metric id hook should exist")

        let candidates = [
            "home.keyMetrics.secondary.bodyFat.toggle",
            "home.keyMetrics.secondary.leanBodyMass.toggle",
            "home.keyMetrics.secondary.waist.toggle"
        ]

        let firstToggleID = firstExistingIdentifier(
            identifiers: candidates,
            query: app.buttons
        )
        let firstToggle = app.buttons[firstToggleID].firstMatch

        XCTAssertTrue(firstToggle.waitForExistence(timeout: 5), "First secondary metric toggle should exist")
        firstToggle.tap()
        XCTAssertEqual(expandedCount.label, "1", "Opening one secondary metric should keep it expanded")

        let firstExpanded = app.otherElements[firstToggleID.replacingOccurrences(of: ".toggle", with: ".expanded")].firstMatch
        XCTAssertTrue(firstExpanded.waitForExistence(timeout: 5), "First secondary metric should expand")

        let remainingCandidates = candidates.filter { $0 != firstToggleID }
        let secondToggleID = firstExistingIdentifier(
            identifiers: remainingCandidates,
            query: app.buttons
        )
        let secondToggle = app.buttons[secondToggleID].firstMatch

        XCTAssertTrue(secondToggle.waitForExistence(timeout: 5), "Second secondary metric toggle should exist")
        secondToggle.tap()

        let secondExpanded = app.otherElements[secondToggleID.replacingOccurrences(of: ".toggle", with: ".expanded")].firstMatch
        XCTAssertTrue(secondExpanded.waitForExistence(timeout: 5), "Second secondary metric should expand")
        XCTAssertEqual(expandedCount.label, "2", "Two secondary metrics should be able to stay expanded together")
        XCTAssertTrue(firstExpanded.exists, "First expanded metric should remain expanded after opening another one")
        XCTAssertTrue(expandedIDs.label.contains(metricKindFromToggleIdentifier(firstToggleID)), "First metric id should remain in the expanded set")
        XCTAssertTrue(expandedIDs.label.contains(metricKindFromToggleIdentifier(secondToggleID)), "Second metric id should appear in the expanded set")
    }

    private func metricKindFromToggleIdentifier(_ identifier: String) -> String {
        let components = identifier.components(separatedBy: ".")
        return components.count >= 4 ? components[3] : identifier
    }

    private func firstExistingIdentifier(
        identifiers: [String],
        query: XCUIElementQuery
    ) -> String {
        for identifier in identifiers {
            if query[identifier].firstMatch.exists {
                return identifier
            }
        }
        return identifiers[0]
    }

    private func launchApp(
        extraArguments: [String] = [],
        isPremium: Bool = true,
        seedMeasurements: Bool = true,
        seedPhotos: Int = 3
    ) {
        var launchArguments = [
            "-uiTestMode",
            "-uiTestBypassHealthSummaryGuards",
            "-uiTestLongHealthInsight"
        ]

        if seedMeasurements {
            launchArguments.append("-uiTestSeedMeasurements")
        }
        if seedPhotos > 0 {
            launchArguments += ["-uiTestSeedPhotos", "\(seedPhotos)"]
        }

        launchArguments.append(isPremium ? "-uiTestForcePremium" : "-uiTestForceNonPremium")
        launchArguments += extraArguments
        app.launchArguments = launchArguments
        app.launch()
    }

    private func firstExistingElement(
        identifiers: [String],
        query: XCUIElementQuery
    ) -> XCUIElement {
        for identifier in identifiers {
            let element = query[identifier].firstMatch
            if element.exists {
                return element
            }
        }
        return query[identifiers[0]].firstMatch
    }

    private func nextFocusTrigger() -> XCUIElement {
        let cardButton = app.buttons["home.nextFocus.button"].firstMatch
        if cardButton.exists {
            return cardButton
        }
        return app.buttons["home.hero.pulse.chip.nextFocus"].firstMatch
    }

    private func framesDoNotOverlap(_ first: XCUIElement, _ second: XCUIElement) -> Bool {
        guard first.exists, second.exists else { return false }
        let firstFrame = first.frame
        let secondFrame = second.frame
        guard !firstFrame.isEmpty, !secondFrame.isEmpty else { return false }
        return firstFrame.intersection(secondFrame).isNull
    }

    private func scrollToReveal(_ element: XCUIElement, maxSwipes: Int) {
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
