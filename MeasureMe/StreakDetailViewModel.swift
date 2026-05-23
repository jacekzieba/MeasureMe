import SwiftUI
import SwiftData

@Observable @MainActor final class StreakDetailViewModel {
    var thisWeekSamples: [MetricSample] = []

    func activeDaysInWeek() -> Set<Int> {
        let calendar = Calendar(identifier: .iso8601)
        return Set(thisWeekSamples.compactMap { sample in
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: sample.date)?.start else { return nil }
            return calendar.dateComponents([.day], from: weekStart, to: sample.date).day
        })
    }
}

@Observable @MainActor final class AllLogsViewModel {
    var customDefinitions: [CustomMetricDefinition] = []
}
