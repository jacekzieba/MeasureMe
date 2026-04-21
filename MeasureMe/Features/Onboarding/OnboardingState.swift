import Foundation

extension OnboardingView {
    enum WelcomeGoal: String, CaseIterable {
        case loseWeight
        case buildMuscle
        case trackHealth

        var priority: OnboardingPriority {
            switch self {
            case .loseWeight:
                return .loseWeight
            case .buildMuscle:
                return .buildMuscle
            case .trackHealth:
                return .improveHealth
            }
        }
    }

    enum InputStep: Int, CaseIterable {
        case profile
        case metrics
        case photos
        case health

        var analyticsName: String {
            switch self {
            case .profile:
                return "profile"
            case .metrics:
                return "metrics"
            case .photos:
                return "photos"
            case .health:
                return "health"
            }
        }
    }

    enum Step {
        case welcome
        case firstMeasurement

        var title: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("Welcome")
            case .firstMeasurement:
                return AppLocalization.systemString("Add your first measurements")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("Set your goal and preview your progress")
            case .firstMeasurement:
                return AppLocalization.systemString("Just a few values to personalize your insights")
            }
        }
    }
}
extension OnboardingView.WelcomeGoal {
    var title: String {
        switch self {
        case .loseWeight:
            return AppLocalization.systemString("Lose weight")
        case .buildMuscle:
            return AppLocalization.systemString("Build muscle")
        case .trackHealth:
            return AppLocalization.systemString("Maintain / recomp")
        }
    }
}
