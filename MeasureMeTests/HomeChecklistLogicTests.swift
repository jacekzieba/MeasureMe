import XCTest
@testable import MeasureMe

@MainActor
final class HomeChecklistLogicTests: XCTestCase {
    func testShouldAutoHideChecklist_ReturnsTrueWhenBothTrue() {
        XCTAssertTrue(
            HomeChecklistLogic.shouldAutoHideChecklist(
                allChecklistItemsCompleted: true,
                showOnboardingChecklistOnHome: true
            )
        )
    }

    func testShouldAutoHideChecklist_ReturnsFalseWhenItemsNotCompleted() {
        XCTAssertFalse(
            HomeChecklistLogic.shouldAutoHideChecklist(
                allChecklistItemsCompleted: false,
                showOnboardingChecklistOnHome: true
            )
        )
    }

    func testShouldAutoHideChecklist_ReturnsFalseWhenChecklistAlreadyHidden() {
        // If showOnboardingChecklistOnHome is false the checklist is already hidden,
        // so there's nothing to auto-hide regardless of completion state.
        XCTAssertFalse(
            HomeChecklistLogic.shouldAutoHideChecklist(
                allChecklistItemsCompleted: true,
                showOnboardingChecklistOnHome: false
            )
        )
    }

    func testShouldAutoHideChecklist_ReturnsFalseWhenBothFalse() {
        XCTAssertFalse(
            HomeChecklistLogic.shouldAutoHideChecklist(
                allChecklistItemsCompleted: false,
                showOnboardingChecklistOnHome: false
            )
        )
    }
}
