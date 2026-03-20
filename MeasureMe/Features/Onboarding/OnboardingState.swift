import Foundation

extension OnboardingView {
    struct ICloudBackupOfferDecision: Equatable {
        let viewedOffer: Bool
        let skippedBackup: Bool

        nonisolated static func persistState(isBackupEnabled: Bool) -> Self {
            .init(
                viewedOffer: true,
                skippedBackup: !isBackupEnabled
            )
        }
    }

    enum FocusField: Hashable {
        case name
        case age
        case height
        case feet
        case inches
    }

    enum WelcomeGoal: String, CaseIterable {
        case loseWeight
        case buildMuscle
        case trackHealth

        var title: String {
            switch self {
            case .loseWeight:
                return AppLocalization.systemString("Lose weight")
            case .buildMuscle:
                return AppLocalization.systemString("Build muscles")
            case .trackHealth:
                return AppLocalization.systemString("Improve my health")
            }
        }
    }

    enum Step: Int, CaseIterable {
        case welcome
        case profile
        case boosters
        case premium

        var title: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("MeasureMe")
            case .profile:
                return AppLocalization.systemString("A few details")
            case .boosters:
                return AppLocalization.systemString("Boosters")
            case .premium:
                return AppLocalization.systemString("Premium Edition")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return ""
            case .profile:
                return AppLocalization.systemString("Optional details for more accurate health indicators.")
            case .boosters:
                return AppLocalization.systemString("Optional automations to keep momentum.")
            case .premium:
                return ""
            }
        }
    }
}
