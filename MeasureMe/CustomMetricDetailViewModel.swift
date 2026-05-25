import SwiftUI
import SwiftData

@Observable @MainActor final class CustomMetricDetailViewModel {
    var samples: [MetricSample] = []
    var goals: [MetricGoal] = []

    var currentGoal: MetricGoal? { goals.first }
}
