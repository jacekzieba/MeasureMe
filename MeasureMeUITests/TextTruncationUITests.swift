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

        for step in 1...4 {
            scanCurrentScreenForTruncatedText(context: "Onboarding.Step\(step)", maxSwipes: 2)

            let nextButton = onboardingNextButton()
            if nextButton.waitForExistence(timeout: 2), nextButton.isHittable {
                nextButton.tap()
            } else {
                break
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
        for _ in 0..<6 {
            let tab = app.buttons[identifier].firstMatch
            if tab.exists && tab.isHittable {
                tab.tap()
                return
            }

            for label in fallbackLabels {
                let candidate = app.buttons[label].firstMatch
                if candidate.exists && candidate.isHittable {
                    candidate.tap()
                    return
                }
            }

            // Home can hide the tab bar while scrolling; swipe down to reveal it again.
            app.swipeDown()
        }

        XCTFail("Could not find tab: \(identifier)")
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
