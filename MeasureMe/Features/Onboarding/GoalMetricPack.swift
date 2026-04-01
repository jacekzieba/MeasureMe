import Foundation

/// Maps an onboarding goal selection to a recommended set of MetricKind values.
/// Applied automatically at onboarding completion if the user has not customized metrics.
enum GoalMetricPack {
    /// Returns a deduplicated, priority-ordered list of MetricKind for the given goals.
    /// Weight is always first. Empty goals fall back to [.weight].
    static func recommendedKinds(for goals: Set<OnboardingView.WelcomeGoal>) -> [MetricKind] {
        guard !goals.isEmpty else { return [.weight] }

        var result: [MetricKind] = []
        var seen = Set<MetricKind>()

        for goal in goals.sorted(by: { $0.rawValue < $1.rawValue }) {
            for kind in pack(for: goal) where seen.insert(kind).inserted {
                result.append(kind)
            }
        }

        // Ensure weight is always the first metric
        if let weightIndex = result.firstIndex(of: .weight), weightIndex != 0 {
            result.remove(at: weightIndex)
            result.insert(.weight, at: 0)
        } else if !seen.contains(.weight) {
            result.insert(.weight, at: 0)
        }

        return result
    }

    static func pack(for goal: OnboardingView.WelcomeGoal) -> [MetricKind] {
        switch goal {
        case .loseWeight:  return [.weight, .waist, .bodyFat]
        case .buildMuscle: return [.weight, .chest, .waist]
        case .trackHealth: return [.weight, .bodyFat, .leanBodyMass]
        }
    }
}
