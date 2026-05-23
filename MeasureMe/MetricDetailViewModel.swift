import SwiftUI
import SwiftData

/// Lightweight @Observable ViewModel for MetricDetailView.
/// Holds the expensive cached chart state that was previously @State in the view.
/// The view still owns @Query, @AppSetting, and all SwiftUI presentation state.
@Observable @MainActor final class MetricDetailViewModel {

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
