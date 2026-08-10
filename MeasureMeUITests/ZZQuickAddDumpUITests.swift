import XCTest

/// Tymczasowy test diagnostyczny — do usuniecia.
final class ZZQuickAddDumpUITests: XCTestCase {
    @MainActor
    func testDumpQuickAddSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestMode"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let addButton = app.tabBars.buttons["tab.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "tab.add powinien istniec")
        addButton.tap()

        let saveButton = app.buttons["quickadd.save"]
        print("DUMP >>> quickadd.save exists=\(saveButton.waitForExistence(timeout: 10))")

        let inputs = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'quickadd.input.'")
        )
        print("DUMP >>> buttons matching quickadd.input.* = \(inputs.count)")

        let anyInputs = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'quickadd.input.'")
        )
        print("DUMP >>> ANY element matching quickadd.input.* = \(anyInputs.count)")
        for e in anyInputs.allElementsBoundByIndex {
            print("DUMP >>> id=\(e.identifier) type=\(e.elementType.rawValue) hittable=\(e.isHittable) frame=\(e.frame)")
        }

        print("DUMP >>> --- wszystkie identyfikatory quickadd.* ---")
        for e in app.descendants(matching: .any).allElementsBoundByIndex
        where e.identifier.hasPrefix("quickadd") {
            print("DUMP >>> id=\(e.identifier) type=\(e.elementType.rawValue)")
        }
    }
}
