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
        case name
        case greeting
        case priority
        case personalizing
        case health
        case notifications
        case completion

        var analyticsName: String {
            switch self {
            case .name:
                return "name"
            case .greeting:
                return "greeting"
            case .priority:
                return "priority"
            case .personalizing:
                return "personalizing"
            case .health:
                return "health"
            case .notifications:
                return "notifications"
            case .completion:
                return "completion"
            }
        }
    }
}
