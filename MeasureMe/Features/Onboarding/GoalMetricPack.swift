import Foundation

enum GoalMetricPack {
    static func recommendedKinds(for priority: OnboardingPriority) -> [MetricKind] {
        switch priority {
        case .loseWeight:
            return [.weight, .waist, .bodyFat]
        case .buildMuscle:
            return [.weight, .chest, .leftBicep, .rightBicep, .leftThigh, .rightThigh]
        case .improveHealth:
            return [.weight, .waist, .bodyFat, .leanBodyMass]
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

        if !result.contains(.weight) {
            result.insert(.weight, at: 0)
        } else if let index = result.firstIndex(of: .weight), index != 0 {
            result.remove(at: index)
            result.insert(.weight, at: 0)
        }

        return result
    }
}
