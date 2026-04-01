import XCTest

final class TextTruncationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testMainScreensDoNotShowTruncatedTextAtAccessibilityXLInPolish() {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestForcePremium",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "24",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
            "-AppleLanguages", "(pl)",
            "-AppleLocale", "pl_PL"
        ]
        app.launch()

        scanCurrentScreenForTruncatedText(context: "Home", maxSwipes: 3)

        tapTab("tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])
        scanCurrentScreenForTruncatedText(context: "Measurements", maxSwipes: 3)

        tapIfExists(app.buttons["measurements.tab.health"].firstMatch)
        scanCurrentScreenForTruncatedText(context: "Measurements.Health", maxSwipes: 2)

        tapIfExists(app.buttons["measurements.tab.physique"].firstMatch)
        scanCurrentScreenForTruncatedText(context: "Measurements.Physique", maxSwipes: 2)

        tapTab("tab.photos", fallbackLabels: ["Photos", "Zdjęcia"])
        scanCurrentScreenForTruncatedText(context: "Photos", maxSwipes: 3)

        tapTab("tab.settings", fallbackLabels: ["Settings", "Ustawienia"])
        scanCurrentScreenForTruncatedText(context: "Settings", maxSwipes: 4)
    }

    @MainActor
    func testOnboardingDoesNotShowTruncatedTextAtAccessibilityXLInPolish() {
        app.launchArguments = [
            "-uiTestOnboardingMode",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
            "-AppleLanguages", "(pl)",
            "-AppleLocale", "pl_PL"
        ]
        app.launch()

        for step in 1...2 {
            scanCurrentScreenForTruncatedText(context: "Onboarding.Step\(step)", maxSwipes: 2)

            if step == 1 {
                let nextButton = onboardingNextButton()
                if nextButton.waitForExistence(timeout: 2), nextButton.isHittable {
                    nextButton.tap()
                } else {
                    break
                }
            } else {
                let skipButton = app.buttons["onboarding.skip"].firstMatch
                if skipButton.waitForExistence(timeout: 2), skipButton.isHittable {
                    skipButton.tap()
                } else {
                    break
                }
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

    private func scanCurrentScreenForTruncatedText(context: String, maxSwipes: Int) {
        for swipeIndex in 0...maxSwipes {
            assertNoVisibleTextUsesEllipsis(context: "\(context).screen\(swipeIndex)")
            if swipeIndex < maxSwipes {
                app.swipeUp()
            }
        }
    }

    private func assertNoVisibleTextUsesEllipsis(context: String, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5), "App window should exist before text truncation scan")

        // Parsing one debug dump is much faster than resolving every XCUI element individually.
        let debugLines = app.debugDescription.components(separatedBy: .newlines)
        let offenders = debugLines.filter { line in
            (line.contains("StaticText") || line.contains("Button")) && line.contains("…")
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Potentially truncated text found in \(context): \(offenders.joined(separator: " | "))",
            file: file,
            line: line
        )
    }
}
