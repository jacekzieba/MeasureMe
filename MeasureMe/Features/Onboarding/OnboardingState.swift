import Foundation

extension OnboardingView {
    enum WelcomeGoal: String, CaseIterable {
        case loseWeight
        case buildMuscle
        case recomposition
        case trackHealth

        var priority: OnboardingPriority {
            switch self {
            case .loseWeight:
                return .loseWeight
            case .buildMuscle:
                return .buildMuscle
            case .recomposition:
                return .improveHealth
            case .trackHealth:
                return .trackHealth
            }
        }
    }

    enum InputStep: Int, CaseIterable {
        case welcome
        case goal
        case startingPoint
        case healthImport

        var analyticsName: String {
            switch self {
            case .welcome:
                return "welcome"
            case .goal:
                return "goal"
            case .startingPoint:
                return "starting_point"
            case .healthImport:
                return "health_import"
            }
        }
    }

    enum Step {
        case welcome
        case firstMeasurement

        var title: String {
            switch self {
            case .welcome:
                return FlowLocalization.app(
                    "Track your body change without obsessing over the scale",
                    "Śledź zmiany sylwetki bez obsesji na punkcie wagi",
                    "Sigue el cambio de tu cuerpo sin obsesionarte con la báscula",
                    "Verfolge Körperveränderung ohne Waagen-Obsession",
                    "Suivez votre corps sans obsession de la balance",
                    "Acompanhe mudanças no corpo sem obsessão pela balança"
                )
            case .firstMeasurement:
                return AppLocalization.systemString("Add your first measurements")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome:
                return FlowLocalization.app(
                    "MeasureMe helps you track weight, waist, photos and trends in one private place.",
                    "MeasureMe pomaga śledzić wagę, pas, zdjęcia i trendy w jednym prywatnym miejscu.",
                    "MeasureMe te ayuda a seguir peso, cintura, fotos y tendencias en un lugar privado.",
                    "MeasureMe hilft dir, Gewicht, Taille, Fotos und Trends an einem privaten Ort zu verfolgen.",
                    "MeasureMe vous aide à suivre poids, taille, photos et tendances dans un espace privé.",
                    "O MeasureMe ajuda a acompanhar peso, cintura, fotos e tendências em um lugar privado."
                )
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
        case .recomposition:
            return AppLocalization.systemString("Recomposition")
        case .trackHealth:
            return AppLocalization.systemString("Track health")
        }
    }
}
