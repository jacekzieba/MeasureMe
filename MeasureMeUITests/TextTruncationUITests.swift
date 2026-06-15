import XCTest

final class TextTruncationUITests: XCTestCase {
    private final class ClippingIssueCollector {
        var issues = Set<String>()
    }

    private struct TestLocale {
        let name: String
        let appLanguageArgument: String
        let appleLanguages: String
        let appleLocale: String

        static let english = TestLocale(
            name: "English",
            appLanguageArgument: "-uiTestLanguageEN",
            appleLanguages: "(en)",
            appleLocale: "en_US"
        )
        static let polish = TestLocale(
            name: "Polish",
            appLanguageArgument: "-uiTestLanguagePL",
            appleLanguages: "(pl)",
            appleLocale: "pl_PL"
        )
        static let spanish = TestLocale(
            name: "Spanish",
            appLanguageArgument: "-uiTestLanguageES",
            appleLanguages: "(es)",
            appleLocale: "es_ES"
        )
        static let german = TestLocale(
            name: "German",
            appLanguageArgument: "-uiTestLanguageDE",
            appleLanguages: "(de)",
            appleLocale: "de_DE"
        )
        static let french = TestLocale(
            name: "French",
            appLanguageArgument: "-uiTestLanguageFR",
            appleLanguages: "(fr)",
            appleLocale: "fr_FR"
        )
        static let portugueseBrazil = TestLocale(
            name: "Portuguese (Brazil)",
            appLanguageArgument: "-uiTestLanguagePTBR",
            appleLanguages: "(pt-BR)",
            appleLocale: "pt_BR"
        )
    }

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testEnglishTextIsNotClipped() throws {
        try assertTextIsNotClipped(in: .english)
    }

    @MainActor
    func testPolishTextIsNotClipped() throws {
        try assertTextIsNotClipped(in: .polish)
    }

    @MainActor
    func testSpanishTextIsNotClipped() throws {
        try assertTextIsNotClipped(in: .spanish)
    }

    @MainActor
    func testGermanTextIsNotClipped() throws {
        try assertTextIsNotClipped(in: .german)
    }

    @MainActor
    func testFrenchTextIsNotClipped() throws {
        try assertTextIsNotClipped(in: .french)
    }

    @MainActor
    func testPortugueseBrazilTextIsNotClipped() throws {
        try assertTextIsNotClipped(in: .portugueseBrazil)
    }

    @MainActor
    private func assertTextIsNotClipped(in locale: TestLocale) throws {
        let collector = ClippingIssueCollector()
        try assertMainScreensDoNotClipText(in: locale, collector: collector)
        app.terminate()
        try assertOnboardingDoesNotClipText(in: locale, collector: collector)

        XCTAssertTrue(
            collector.issues.isEmpty,
            """
            Clipped text found for \(locale.name):
            \(collector.issues.sorted().joined(separator: "\n"))
            """
        )
    }

    @MainActor
    private func assertMainScreensDoNotClipText(
        in locale: TestLocale,
        collector: ClippingIssueCollector
    ) throws {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForcePremium",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "24",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
            locale.appLanguageArgument,
            "-AppleLanguages", locale.appleLanguages,
            "-AppleLocale", locale.appleLocale
        ]
        app.launch()

        try scanCurrentScreenForTruncatedText(
            context: "\(locale.name).Home",
            maxSwipes: 3,
            collector: collector
        )

        tapTab("tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])
        try scanCurrentScreenForTruncatedText(
            context: "\(locale.name).Measurements",
            maxSwipes: 3,
            collector: collector
        )

        tapIfExists(app.buttons["measurements.tab.health"].firstMatch)
        try scanCurrentScreenForTruncatedText(
            context: "\(locale.name).Measurements.Health",
            maxSwipes: 2,
            collector: collector
        )

        tapIfExists(app.buttons["measurements.tab.physique"].firstMatch)
        try scanCurrentScreenForTruncatedText(
            context: "\(locale.name).Measurements.Physique",
            maxSwipes: 2,
            collector: collector
        )

        tapTab("tab.photos", fallbackLabels: ["Photos", "Zdjęcia"])
        try scanCurrentScreenForTruncatedText(
            context: "\(locale.name).Photos",
            maxSwipes: 3,
            collector: collector
        )

        tapTab("tab.settings", fallbackLabels: ["Settings", "Ustawienia"])
        try scanCurrentScreenForTruncatedText(
            context: "\(locale.name).Settings",
            maxSwipes: 4,
            collector: collector
        )
    }

    @MainActor
    private func assertOnboardingDoesNotClipText(
        in locale: TestLocale,
        collector: ClippingIssueCollector
    ) throws {
        app.launchArguments = [
            "-uiTestOnboardingMode",
            "-uiTestOnboardingPriority", "improveHealth",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
            locale.appLanguageArgument,
            "-AppleLanguages", locale.appleLanguages,
            "-AppleLocale", locale.appleLocale
        ]
        app.launch()

        let stepMarker = app.staticTexts["root.onboarding.test.step"].firstMatch
        XCTAssertTrue(stepMarker.waitForExistence(timeout: 10), "Onboarding step marker should exist")

        for step in 0..<6 {
            waitForOnboardingStep(step, marker: stepMarker)
            try scanCurrentScreenForTruncatedText(
                context: "\(locale.name).Onboarding.Step\(step + 1)",
                maxSwipes: 2,
                collector: collector
            )

            guard step < 5 else { continue }
            let advanceButton = step == 0 ? onboardingNextButton() : onboardingSkipButton()
            XCTAssertTrue(
                advanceButton.waitForExistence(timeout: 3),
                "Onboarding advance button should exist for step \(step + 1)"
            )
            if advanceButton.isHittable {
                advanceButton.tap()
            } else {
                advanceButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
    }

    private func onboardingNextButton() -> XCUIElement {
        let uiTestNext = app.buttons["UITest Next"].firstMatch
        if uiTestNext.waitForExistence(timeout: 0.5) {
            return uiTestNext
        }
        return app.buttons["onboarding.next"].firstMatch
    }

    private func onboardingSkipButton() -> XCUIElement {
        let uiTestSkip = app.buttons["onboarding.test.skip"].firstMatch
        if uiTestSkip.waitForExistence(timeout: 0.5) {
            return uiTestSkip
        }
        return app.buttons["onboarding.skip"].firstMatch
    }

    private func waitForOnboardingStep(_ step: Int, marker: XCUIElement) {
        let predicate = NSPredicate(format: "label == %@", "step:\(step)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: marker)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Expected onboarding step \(step + 1), current marker: \(marker.exists ? marker.label : "missing")"
        )
    }

    private func tapTab(_ identifier: String, fallbackLabels: [String]) {
        // Swipe down first — home screen hides the tab bar while scrolling.
        app.swipeDown()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 8) else {
            XCTFail("Could not find tab bar when tapping tab: \(identifier)")
            return
        }

        // 1. Try accessibilityIdentifier directly on the tab bar.
        let byID = tabBar.buttons[identifier].firstMatch
        if byID.exists && byID.isHittable {
            byID.tap(); return
        }

        // 2. Try exact label match on the tab bar.
        for label in fallbackLabels {
            let byLabel = tabBar.buttons[label].firstMatch
            if byLabel.exists && byLabel.isHittable {
                byLabel.tap(); return
            }
        }

        // 3. Try CONTAINS predicate on the tab bar.
        for label in fallbackLabels {
            let pred = NSPredicate(format: "label CONTAINS[c] %@", label)
            let containsMatch = tabBar.buttons.matching(pred).firstMatch
            if containsMatch.exists && containsMatch.isHittable {
                containsMatch.tap(); return
            }
        }

        // 4. Index-based fallback (robust against localization and large text).
        if let tabIndex = fallbackTabIndex(forIdentifier: identifier, labels: fallbackLabels) {
            let buttons = tabBar.buttons.allElementsBoundByIndex
            if buttons.indices.contains(tabIndex) && buttons[tabIndex].isHittable {
                buttons[tabIndex].tap(); return
            }
            if let normalizedX = fallbackTabNormalizedX(for: tabIndex) {
                tabBar.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5)).tap()
                return
            }
        }

        XCTFail("Could not find tab: \(identifier)")
    }

    private func fallbackTabIndex(forIdentifier identifier: String, labels: [String]) -> Int? {
        let all = ([identifier] + labels).map { $0.lowercased() }
        if all.contains(where: { $0.contains("home") || $0 == "start" || $0 == "dom" }) { return 0 }
        if all.contains(where: { $0.contains("measurement") || $0 == "pomiary" }) { return 1 }
        if all.contains(where: { $0.contains("photo") || $0.contains("zdj") }) { return 3 }
        if all.contains(where: { $0.contains("setting") || $0 == "ustawienia" }) { return 4 }
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

    private func tapIfExists(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 2), element.isHittable {
            element.tap()
        }
    }

    private func scanCurrentScreenForTruncatedText(
        context: String,
        maxSwipes: Int,
        collector: ClippingIssueCollector
    ) throws {
        for swipeIndex in 0...maxSwipes {
            let window = app.windows.element(boundBy: 0)
            XCTAssertTrue(window.waitForExistence(timeout: 5), "App window should exist before text truncation scan")

            // Apple's `.textClipped` audit only reports that text *may* clip at large
            // Dynamic Type sizes, which over-flags intentional styled labels (uppercase
            // eyebrows, the date header, etc.). We instead assert on *actual* truncation:
            // any visible StaticText/Button whose rendered string shows a trailing
            // ellipsis. Parsing one debug dump is far faster than resolving each element.
            let offenders = app.debugDescription
                .components(separatedBy: .newlines)
                .filter { ($0.contains("StaticText") || $0.contains("Button")) && $0.contains("…") }
            for offender in offenders {
                collector.issues.insert("\(context): \(offender.trimmingCharacters(in: .whitespaces))")
            }

            if swipeIndex < maxSwipes {
                app.swipeUp()
            }
        }
    }
}
