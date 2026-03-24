import XCTest
@testable import MeasureMe

final class MetricDetailChartSamplingTests: XCTestCase {
    func testSamplerDoesNotExceedLimitAndKeepsEndpoints() {
        let samples = makeSamples(count: 1000)
        let sampled = MetricDetailView.sampledChartSamples(from: samples, maxPoints: 320)

        XCTAssertLessThanOrEqual(sampled.count, 320)
        XCTAssertEqual(sampled.first?.persistentModelID, samples.first?.persistentModelID)
        XCTAssertEqual(sampled.last?.persistentModelID, samples.last?.persistentModelID)
    }

    func testSamplerMaintainsMonotonicDateOrder() {
        let samples = makeSamples(count: 750)
        let sampled = MetricDetailView.sampledChartSamples(from: samples, maxPoints: 260)

        for (lhs, rhs) in zip(sampled, sampled.dropFirst()) {
            XCTAssertLessThanOrEqual(lhs.date, rhs.date)
        }
    }

    func testSamplerPerformanceForLargeDataset() {
        let samples = makeSamples(count: 20_000)

        measure {
            _ = MetricDetailView.sampledChartSamples(from: samples, maxPoints: 320)
        }
    }

    func testSamplerReturnsBoundedInteractiveSubset() {
        let samples = makeSamples(count: 2_500)
        let renderSamples = MetricDetailView.sampledChartSamples(from: samples, maxPoints: 320)
        let interactionSamples = MetricDetailView.sampledChartSamples(from: renderSamples, maxPoints: 96)

        XCTAssertLessThanOrEqual(interactionSamples.count, 96)
        XCTAssertEqual(interactionSamples.first?.persistentModelID, renderSamples.first?.persistentModelID)
        XCTAssertEqual(interactionSamples.last?.persistentModelID, renderSamples.last?.persistentModelID)
    }

    func testRenderPointLimitScalesWithAvailableWidth() {
        let narrow = MetricDetailView.chartRenderPointLimit(for: .all, availableWidth: 260)
        let wide = MetricDetailView.chartRenderPointLimit(for: .all, availableWidth: 420)

        XCTAssertLessThan(narrow, wide)
        XCTAssertGreaterThanOrEqual(narrow, 112)
        XCTAssertLessThanOrEqual(wide, 320)
    }

    func testInteractionLimitRemainsBoundedForSmallAndLargeCharts() {
        let narrow = MetricDetailView.chartInteractionPointLimit(for: .month, availableWidth: 240)
        let wide = MetricDetailView.chartInteractionPointLimit(for: .month, availableWidth: 600)

        XCTAssertGreaterThanOrEqual(narrow, 36)
        XCTAssertLessThanOrEqual(wide, 96)
        XCTAssertLessThanOrEqual(narrow, wide)
    }

    func testRemapPreservesSourceEndpoints() {
        let mappedLower = MetricDetailView.remap(10, from: 10...20, to: 100...200)
        let mappedUpper = MetricDetailView.remap(20, from: 10...20, to: 100...200)

        XCTAssertEqual(mappedLower, 100, accuracy: 0.0001)
        XCTAssertEqual(mappedUpper, 200, accuracy: 0.0001)
    }

    func testRemapMapsMidpointLinearly() {
        let mapped = MetricDetailView.remap(15, from: 10...20, to: 100...200)

        XCTAssertEqual(mapped, 150, accuracy: 0.0001)
    }

    private func makeSamples(count: Int) -> [MetricSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            let date = start.addingTimeInterval(TimeInterval(index * 86_400))
            let value = 80.0 + sin(Double(index) / 9.0) * 2.0 + Double(index % 17) * 0.02
            return MetricSample(kind: .weight, value: value, date: date)
        }
    }
}
