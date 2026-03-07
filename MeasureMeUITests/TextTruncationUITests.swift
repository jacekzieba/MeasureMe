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

        scanCurrentScreenForTruncatedText(context: "Home", maxSwipes: 6)

        tapTab("tab.measurements", fallbackLabels: ["Measurements", "Pomiary"])
        scanCurrentScreenForTruncatedText(context: "Measurements", maxSwipes: 6)

        tapIfExists(app.buttons["measurements.tab.health"].firstMatch)
        scanCurrentScreenForTruncatedText(context: "Measurements.Health", maxSwipes: 4)

        tapIfExists(app.buttons["measurements.tab.physique"].firstMatch)
        scanCurrentScreenForTruncatedText(context: "Measurements.Physique", maxSwipes: 4)

        tapTab("tab.photos", fallbackLabels: ["Photos", "Zdjęcia"])
        scanCurrentScreenForTruncatedText(context: "Photos", maxSwipes: 6)

        tapTab("tab.settings", fallbackLabels: ["Settings", "Ustawienia"])
        scanCurrentScreenForTruncatedText(context: "Settings", maxSwipes: 8)
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

            let nextButton = app.buttons["onboarding.next"].firstMatch
            if nextButton.waitForExistence(timeout: 2), nextButton.isHittable {
                nextButton.tap()
            } else {
                break
            }
        }
    }

    private func tapTab(_ identifier: String, fallbackLabels: [String]) {
        let tab = app.tabBars.buttons[identifier].firstMatch
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
            return
        }

        for label in fallbackLabels {
            let candidate = app.tabBars.buttons[label].firstMatch
            if candidate.waitForExistence(timeout: 2) {
                candidate.tap()
                return
            }
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

        var offenders: [String] = []

        let elements = app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex
        for element in elements where isVisible(element, inside: window) {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }

            if label.contains("…") {
                let id = element.identifier.isEmpty ? "(no-id)" : element.identifier
                offenders.append("[\(id)] \(label)")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Potentially truncated text found in \(context): \(offenders.joined(separator: " | "))",
            file: file,
            line: line
        )
    }

    private func isVisible(_ element: XCUIElement, inside container: XCUIElement) -> Bool {
        guard element.exists, container.exists else { return false }
        let frame = element.frame
        let containerFrame = container.frame
        guard !frame.isEmpty, !containerFrame.isEmpty else { return false }
        let intersection = frame.intersection(containerFrame)
        return !intersection.isNull && !intersection.isEmpty
    }
}
