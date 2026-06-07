import Foundation

enum GoalMetricPack {
    static let defaultTrackedKinds: [MetricKind] = [.weight, .bodyFat]

    static func recommendedKinds(for priority: OnboardingPriority) -> [MetricKind] {
        let goalSpecificKinds: [MetricKind]
        switch priority {
        case .loseWeight:
            goalSpecificKinds = [.weight, .waist]
        case .buildMuscle:
            goalSpecificKinds = [.chest, .leftBicep, .rightBicep]
        case .improveHealth:
            goalSpecificKinds = [.waist, .chest]
        }

        return mergedKinds(goalSpecificKinds)
    }

    static func trackedKinds(for priority: OnboardingPriority) -> [MetricKind] {
        mergedKinds(defaultTrackedKinds + recommendedKinds(for: priority))
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

    private static func mergedKinds(_ kinds: [MetricKind]) -> [MetricKind] {
        var seen = Set<MetricKind>()
        return kinds.filter { seen.insert($0).inserted }
    }
}
