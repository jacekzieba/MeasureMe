import Foundation

enum HomeChecklistLogic {
    static func shouldAutoHideChecklist(
        allChecklistItemsCompleted: Bool,
        showOnboardingChecklistOnHome: Bool
    ) -> Bool {
        allChecklistItemsCompleted && showOnboardingChecklistOnHome
    }
}
