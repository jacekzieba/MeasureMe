import Foundation

enum SettingsDataActions {
    static func runPremiumAction(
        isPremium: Bool,
        feature: String,
        onAllowed: () -> Void,
        onLocked: (_ feature: String) -> Void
    ) {
        if isPremium {
            onAllowed()
        } else {
            onLocked(feature)
        }
    }
}
