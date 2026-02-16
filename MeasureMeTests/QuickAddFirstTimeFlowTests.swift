import XCTest
@testable import MeasureMe

/// Tests for the first-time flow logic: ruler visibility based on whether
/// a previous measurement exists or the user has typed a value.
final class QuickAddFirstTimeFlowTests: XCTestCase {

    // MARK: - shouldShowRuler

    func testShouldShowRulerFalseWhenNoLatestAndNoInput() {
        // First-time user, hasn't typed anything → ruler hidden
        XCTAssertFalse(
            QuickAddMath.shouldShowRuler(hasLatest: false, currentInput: nil),
            "Ruler should be hidden when there is no history and no user input"
        )
    }

    func testShouldShowRulerTrueWhenHasLatest() {
        // Returning user with previous measurement → ruler visible
        XCTAssertTrue(
            QuickAddMath.shouldShowRuler(hasLatest: true, currentInput: nil),
            "Ruler should be visible when a previous measurement exists"
        )
    }

    func testShouldShowRulerTrueWhenUserTypedValue() {
        // First-time user who just typed a value → ruler appears
        XCTAssertTrue(
            QuickAddMath.shouldShowRuler(hasLatest: false, currentInput: 80.0),
            "Ruler should appear after user types their first value"
        )
    }

    func testShouldShowRulerTrueWhenBothExist() {
        // Returning user who also typed a new value → ruler stays visible
        XCTAssertTrue(
            QuickAddMath.shouldShowRuler(hasLatest: true, currentInput: 85.0),
            "Ruler should remain visible when both history and input exist"
        )
    }
}
