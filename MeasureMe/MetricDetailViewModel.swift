import SwiftUI
import SwiftData

/// Lightweight @Observable ViewModel for MetricDetailView.
/// Holds query results and cached chart state; the view syncs @Query results here
/// and reads all data through the ViewModel.
@Observable @MainActor final class MetricDetailViewModel {

    // MARK: - Query Results

    var samples: [MetricSample] = []
    var goals: [MetricGoal] = []
    var photos: [PhotoEntry] = []

    // MARK: - Cached Chart Calculations (previously @State in MetricDetailView)

    var cachedYDomain: ClosedRange<Double> = 0...1
    var cachedTrendlineSegment: (startDate: Date, startValue: Double, endDate: Date, endValue: Double)? = nil

    // MARK: - Rebuild: Chart Cache

    /// Call when chartRenderSamples, timeframe, or goal change.
    func refreshChartCache(
        computeYDomain: () -> ClosedRange<Double>,
        computeTrendlineSegment: () -> (startDate: Date, startValue: Double, endDate: Date, endValue: Double)?
    ) {
        cachedYDomain = computeYDomain()
        cachedTrendlineSegment = computeTrendlineSegment()
    }
}
