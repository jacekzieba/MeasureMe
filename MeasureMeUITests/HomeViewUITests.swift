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

    func testAIInsightsCTAOpensAnalysisForPremiumUser() {
        launchApp()

        let cta = firstExistingElement(
            identifiers: ["home.aiInsights.openAnalysis", "View analysis", "Zobacz analizę"],
            query: app.descendants(matching: .any)
        )
        XCTAssertTrue(cta.waitForExistence(timeout: 5), "AI Insights card should expose analysis CTA")
        cta.tap()

        XCTAssertTrue(app.descendants(matching: .any)["home.aiAnalysis.screen"].waitForExistence(timeout: 5), "AI Analysis screen should open from Home")
        XCTAssertTrue(app.navigationBars.staticTexts["AI Analysis"].firstMatch.waitForExistence(timeout: 5), "AI Analysis should have a navigation title")
    }

    func testHomeAvatarOpensProfileSettings() {
        launchApp()

        let avatar = app.buttons["home.profile.avatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), "Home avatar should be tappable")
        avatar.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Profile"].firstMatch.waitForExistence(timeout: 5), "Avatar should deep-link to Settings > Profile")
        XCTAssertTrue(app.buttons["settings.profile.photo.picker"].firstMatch.waitForExistence(timeout: 5), "Profile should expose photo picker")
    }

    func testHomeDashboardModulesDoNotOverlap() {
        launchApp()

        let summaryHero = app.otherElements["home.module.summaryHero"].firstMatch
        let keyMetrics = app.otherElements["home.module.keyMetrics"].firstMatch
        let recentPhotos = app.otherElements["home.module.recentPhotos"].firstMatch

        XCTAssertTrue(summaryHero.waitForExistence(timeout: 5), "Summary hero frame hook should exist")
        XCTAssertTrue(keyMetrics.waitForExistence(timeout: 5), "Key metrics card frame hook should exist")
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos card frame hook should exist")

        XCTAssertTrue(framesDoNotOverlap(summaryHero, keyMetrics), "Summary hero and Key metrics must not overlap")
        XCTAssertTrue(framesDoNotOverlap(keyMetrics, recentPhotos), "Key metrics and Recent photos must not overlap")
        XCTAssertLessThanOrEqual(summaryHero.frame.maxY, keyMetrics.frame.minY, "Key metrics should start after AI Insights")
        XCTAssertLessThanOrEqual(keyMetrics.frame.maxY, recentPhotos.frame.minY, "Recent photos should start after Key metrics ends")
    }

    func testRecentPhotosShowsComparisonPair() {
        launchApp()

        let recentPhotos = app.staticTexts["Progress photos"].firstMatch
        XCTAssertTrue(recentPhotos.waitForExistence(timeout: 5), "Recent photos module should exist")

        let tileCount = app.staticTexts["home.recentPhotos.tileCount"].firstMatch
        XCTAssertTrue(tileCount.waitForExistence(timeout: 5), "Recent photos tile count hook should exist")
        XCTAssertEqual(tileCount.label, "2", "Recent photos should expose the comparison pair on Home")
    }

    func testAddAnotherPhotoInsightOpensPhotosTab() {
        launchApp(seedPhotos: 1)

        let openPhotos = app.buttons["home.aiInsights.openPhotos"].firstMatch
        XCTAssertTrue(openPhotos.waitForExistence(timeout: 5), "Single-photo insight should be tappable")
        openPhotos.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["uitest.debug.tab.photos"].waitForExistence(timeout: 5),
            "Photo insight should switch to the Photos tab"
        )
    }

    func testTrackedMetricsReviewPromptBecomesEditAfterOpeningSettings() {
        launchApp()

        let review = app.buttons["home.keyMetrics.reviewTrackedMetrics"].firstMatch
        scrollToReveal(review, maxSwipes: 4)
        XCTAssertTrue(review.waitForExistence(timeout: 5), "Tracked metrics review action should exist")
        review.tap()

        XCTAssertTrue(
            app.navigationBars.staticTexts["Tracked measurements"].firstMatch.waitForExistence(timeout: 5),
            "Review action should open tracked measurements"
        )

        let homeTab = app.tabBars.buttons["tab.home"].firstMatch.exists
            ? app.tabBars.buttons["tab.home"].firstMatch
            : app.tabBars.buttons["Home"].firstMatch
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        homeTab.tap()

        let edit = app.buttons["home.keyMetrics.reviewTrackedMetrics"].firstMatch
        scrollToReveal(edit, maxSwipes: 4)
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertEqual(edit.value as? String, "reviewed")
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
            "-uiTestActivationTask", "chooseMetrics",
            // Keep the reminders task pending so it is the next *unsatisfied* task after
            // skipping "Choose what to track"; otherwise it is auto-satisfied and skipped.
            "-uiTestChecklistNeedsReminders"
        ], isPremium: false, seedMeasurements: true, seedPhotos: 0)

        let activationHub = app.otherElements["home.module.activationHub"].firstMatch
        XCTAssertTrue(activationHub.waitForExistence(timeout: 5), "Activation hub should be visible on Home")
        XCTAssertTrue(app.staticTexts["Choose what to track"].waitForExistence(timeout: 5), "Activation hub should expose the requested task")

        let skipButton = app.buttons["home.activation.skip"].firstMatch
        scrollToReveal(skipButton, maxSwipes: 6)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Activation hub skip should exist")
        // Tap the element (not a forced geometric-centre coordinate): when the activation card
        // sits at the bottom edge its centre overlaps the tab bar, so a 0.5/0.5 coordinate tap
        // would hit a tab. `.tap()` resolves a genuinely hittable point on the skip button.
        skipButton.tap()

        let nextTaskTitle = NSPredicate(format: "label IN %@", ["Set reminders", "Ustaw przypomnienia"])
        XCTAssertTrue(app.staticTexts.matching(nextTaskTitle).firstMatch.waitForExistence(timeout: 5), "Skip should move the user to the next real activation task")
    }

    func testNextFocusShowsMetricInsightWhenProgressExists() {
        launchApp()

        let nextFocusMode = app.staticTexts["home.nextFocus.mode"].firstMatch
        XCTAssertTrue(nextFocusMode.waitForExistence(timeout: 5), "Next focus mode hook should exist")
        let nextFocusButton = nextFocusTrigger()
        XCTAssertTrue(nextFocusButton.waitForExistence(timeout: 5), "Next focus trigger should exist")
        XCTAssertEqual(nextFocusMode.label, "metric", "Seeded measurements should produce a metric insight")
        nextFocusButton.tap()

        let analysisScreen = app.descendants(matching: .any)["home.aiAnalysis.screen"].firstMatch
        XCTAssertTrue(analysisScreen.waitForExistence(timeout: 5), "Hero CTA should open the AI analysis destination")
    }

    func testNextFocusLongInsightFitsAtAccessibilityXL() throws {
        throw XCTSkip("Home hero redesigned to AI Insights panel; legacy nextFocus primary/summary identifiers no longer rendered.")
    }

    func testNextFocusFallbackSetGoalSwitchesToMeasurementsTab() throws {
        throw XCTSkip("Non-premium fallback flow removed in Home redesign; no hero CTA leads to Measurements anymore.")
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
        scrollToReveal(compareButton, maxSwipes: 8)
        tapVisibleElement(compareButton)

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
        let candidates = [
            "home.aiInsights.openAnalysis",
            "home.nextFocus.button",
            "home.hero.pulse.chip.nextFocus"
        ]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            for id in candidates {
                let element = app.buttons[id].firstMatch
                if element.exists { return element }
            }
            usleep(150_000)
        }
        return app.buttons[candidates[0]].firstMatch
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
        if isPartiallyVisible(element, in: window), element.isHittable { return }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if isPartiallyVisible(element, in: window), element.isHittable {
                return
            }
        }
    }

    private func tapVisibleElement(_ element: XCUIElement) {
        XCTAssertTrue(element.exists, "Expected element to exist before tapping")
        if element.isHittable {
            element.tap()
            return
        }

        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(
            isPartiallyVisible(element, in: window),
            "Expected element to be visible before coordinate tap"
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
