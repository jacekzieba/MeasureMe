import Foundation

extension OnboardingView {
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
        case firstMeasurement

        var title: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("MeasureMe")
            case .firstMeasurement:
                return AppLocalization.systemString("Your starting point")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return ""
            case .firstMeasurement:
                return AppLocalization.systemString("One number is all you need to begin.")
            }
        }

        var countsInProgressBar: Bool {
            switch self {
            case .welcome, .firstMeasurement: return true
            }
        }

        /// Steps shown in the progress bar.
        static var progressSteps: [Step] {
            allCases.filter(\.countsInProgressBar)
        }
    }
}
