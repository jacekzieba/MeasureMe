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
        case profile
        case metrics
        case photos
        case health

        var analyticsName: String {
            switch self {
            case .welcome:
                return "welcome"
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
                return FlowLocalization.app(
                    "Save your starting point",
                    "Zapisz punkt startowy",
                    "Guarda tu punto de partida",
                    "Speichere deinen Startpunkt",
                    "Enregistrez votre point de départ",
                    "Salve seu ponto de partida"
                )
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return AppLocalization.systemString("Set your goal and preview your progress")
            case .firstMeasurement:
                return FlowLocalization.app(
                    "This is not a score. It is your baseline.",
                    "To nie wynik. To punkt startowy.",
                    "No es una nota. Es tu línea base.",
                    "Das ist keine Bewertung. Es ist dein Ausgangspunkt.",
                    "Ce n'est pas un score. C'est votre point de départ.",
                    "Isto não é uma nota. É sua linha de base."
                )
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
