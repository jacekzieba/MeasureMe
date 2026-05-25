import SwiftUI
import SwiftData

@Observable @MainActor final class CustomMetricChartTileViewModel {
    var samples: [MetricSample] = []
    var goals: [MetricGoal] = []

    var currentGoal: MetricGoal? { goals.first }
    var latest: MetricSample? { samples.last }
}
