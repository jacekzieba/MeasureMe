import Foundation

enum GoalMetricPack {
    static func recommendedKinds(for priority: OnboardingPriority) -> [MetricKind] {
        switch priority {
        case .loseWeight:
            return [.weight, .waist]
        case .buildMuscle:
            return [.chest, .leftBicep]
        case .improveHealth:
            return [.waist, .chest]
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
