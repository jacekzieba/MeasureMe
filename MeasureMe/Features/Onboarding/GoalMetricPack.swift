import Foundation

enum GoalMetricPack {
    static func recommendedKinds(for priority: OnboardingPriority) -> [MetricKind] {
        switch priority {
        case .loseWeight:
            return [.weight, .waist]
        case .buildMuscle:
            return [.weight, .chest, .leftBicep, .waist]
        case .improveHealth:
            return [.weight, .waist, .chest, .leftBicep]
        case .trackHealth:
            return [.weight, .waist]
        }
    }

    static func recommendedKinds(for goals: Set<OnboardingView.WelcomeGoal>) -> [MetricKind] {
        let priorities = goals.compactMap(\.priority)
        guard !priorities.isEmpty else { return recommendedKinds(for: .improveHealth) }

        var seen = Set<MetricKind>()
        var result: [MetricKind] = []

        for priority in priorities {
            for kind in recommendedKinds(for: priority) where seen.insert(kind).inserted {
                result.append(kind)
            }
        }

        return result
    }
}
