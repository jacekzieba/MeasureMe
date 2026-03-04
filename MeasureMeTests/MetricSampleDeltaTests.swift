import XCTest
import SwiftData
@testable import MeasureMe

/// Tests for [MetricSample].deltaText(days:kind:unitsSystem:now:)
/// Edge cases not covered by HomeStartupOptimizationTests.
@MainActor
final class MetricSampleDeltaTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - Nil cases

    func testDeltaText_EmptyArray_ReturnsNil() {
        let result = [MetricSample]().deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "metric",
            now: fixedNow
        )
        XCTAssertNil(result)
    }

    func testDeltaText_AllSamplesOutsideWindow_ReturnsNil() {
        // Both samples are 30 days old — outside the 7-day window.
        let old1 = MetricSample(kind: .weight, value: 80, date: fixedNow.addingTimeInterval(-30 * 86_400))
        let old2 = MetricSample(kind: .weight, value: 81, date: fixedNow.addingTimeInterval(-29 * 86_400))

        let result = [old1, old2].deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "metric",
            now: fixedNow
        )
        XCTAssertNil(result)
    }

    func testDeltaText_OnlySampleExactlyOnWindowBoundary_SingleSample_ReturnsNil() {
        // Exactly at the window start boundary; still a single unique sample.
        let boundaryDate = Calendar.current.date(byAdding: .day, value: -7, to: fixedNow)!
        let sample = MetricSample(kind: .weight, value: 80, date: boundaryDate)

        let result = [sample].deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "metric",
            now: fixedNow
        )
        XCTAssertNil(result)
    }

    // MARK: - Positive delta

    func testDeltaText_PositiveDelta_FormatsWithPlusSign() {
        // newer > older → positive delta
        let older = MetricSample(kind: .weight, value: 79.0, date: fixedNow.addingTimeInterval(-6 * 86_400))
        let newer = MetricSample(kind: .weight, value: 80.5, date: fixedNow.addingTimeInterval(-1 * 86_400))

        let result = [older, newer].deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "metric",
            now: fixedNow
        )
        XCTAssertEqual(result, "+1.5 kg")
    }

    // MARK: - Imperial conversion

    func testDeltaText_ImperialWeight_ConvertsDeltaToLbs() {
        // 1 kg gain: delta_lb = 1 / 0.45359237 ≈ 2.20462 → "+2.2 lb"
        let older = MetricSample(kind: .weight, value: 79.0, date: fixedNow.addingTimeInterval(-6 * 86_400))
        let newer = MetricSample(kind: .weight, value: 80.0, date: fixedNow.addingTimeInterval(-1 * 86_400))

        let result = [older, newer].deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "imperial",
            now: fixedNow
        )
        XCTAssertEqual(result, "+2.2 lb")
    }

    func testDeltaText_ImperialLength_ConvertsDeltaToInches() {
        // 2.54 cm = 1 in exactly, so a 2.54 cm increase → "+1.0 in"
        let older = MetricSample(kind: .waist, value: 87.00, date: fixedNow.addingTimeInterval(-6 * 86_400))
        let newer = MetricSample(kind: .waist, value: 89.54, date: fixedNow.addingTimeInterval(-1 * 86_400))

        let result = [older, newer].deltaText(
            days: 7,
            kind: .waist,
            unitsSystem: "imperial",
            now: fixedNow
        )
        XCTAssertEqual(result, "+1.0 in")
    }

    // MARK: - Window boundary

    func testDeltaText_SampleExactlyOnWindowBoundary_IsIncluded() {
        // The filter is `>= start`, so a sample exactly on the boundary counts.
        let boundaryDate = Calendar.current.date(byAdding: .day, value: -7, to: fixedNow)!
        let boundary = MetricSample(kind: .weight, value: 78.0, date: boundaryDate)
        let recent = MetricSample(kind: .weight, value: 79.5, date: fixedNow.addingTimeInterval(-1 * 86_400))

        let result = [boundary, recent].deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "metric",
            now: fixedNow
        )
        XCTAssertEqual(result, "+1.5 kg")
    }

    func testDeltaText_SampleJustBeforeWindowBoundary_IsExcluded() {
        // 1 second before boundary → excluded; only one sample in window → nil.
        let justBefore = Calendar.current.date(byAdding: .day, value: -7, to: fixedNow)!
            .addingTimeInterval(-1)
        let outside = MetricSample(kind: .weight, value: 78.0, date: justBefore)
        let recent = MetricSample(kind: .weight, value: 79.5, date: fixedNow.addingTimeInterval(-1 * 86_400))

        let result = [outside, recent].deltaText(
            days: 7,
            kind: .weight,
            unitsSystem: "metric",
            now: fixedNow
        )
        XCTAssertNil(result)
    }
}
