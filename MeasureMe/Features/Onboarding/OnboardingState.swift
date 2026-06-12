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
        case welcome
        case goal
        case startingPoint
        case rhythm
        case boosters
        case plan

        var analyticsName: String {
            switch self {
            case .welcome:
                return "welcome"
            case .goal:
                return "goal"
            case .startingPoint:
                return "starting_point"
            case .rhythm:
                return "rhythm"
            case .boosters:
                return "boosters"
            case .plan:
                return "plan"
            }
        }
    }

    enum Step {
        case welcome

        var title: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("Welcome")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("Set your goal and preview your progress")
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
