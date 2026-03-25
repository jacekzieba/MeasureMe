import XCTest
@testable import MeasureMe

final class MetricFrequencyAnalyzerTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Helpers

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    private func sample(_ kind: String, _ dateString: String) -> MetricFrequencyAnalyzer.Sample {
        MetricFrequencyAnalyzer.Sample(kindRaw: kind, date: date(dateString))
    }

    // MARK: - Last Log Date Tests

    func testLastLogDateReturnsLatestSample() {
        let samples = [
            sample("weight", "2026-03-01 10:00"),
            sample("weight", "2026-03-10 10:00"),
            sample("weight", "2026-03-05 10:00"),
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertEqual(result.lastLogDates["weight"], date("2026-03-10 10:00"))
    }

    func testMultipleMetricsTrackedIndependently() {
        let samples = [
            sample("weight", "2026-03-01 10:00"),
            sample("waist", "2026-03-05 10:00"),
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertNotNil(result.lastLogDates["weight"])
        XCTAssertNotNil(result.lastLogDates["waist"])
    }

    // MARK: - Average Interval Tests

    func testAverageIntervalCalculation() {
        // 3 samples, 5 days apart each
        let samples = [
            sample("weight", "2026-03-01 10:00"),
            sample("weight", "2026-03-06 10:00"),
            sample("weight", "2026-03-11 10:00"),
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        let avgDays = result.averageIntervals["weight"]! / 86400.0
        XCTAssertEqual(avgDays, 5.0, accuracy: 0.01)
    }

    func testNoAverageIntervalWithTooFewSamples() {
        let samples = [
            sample("weight", "2026-03-01 10:00"),
            sample("weight", "2026-03-06 10:00"),
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertNil(result.averageIntervals["weight"])
    }

    // MARK: - Pattern Detection Tests

    func testDetectsWeeklyPattern() {
        // 5 Saturdays at ~10:00 AM (dayOfWeek 7 in Gregorian)
        let samples = [
            sample("weight", "2026-01-03 10:30"), // Saturday
            sample("weight", "2026-01-10 10:15"), // Saturday
            sample("weight", "2026-01-17 10:45"), // Saturday
            sample("weight", "2026-01-24 10:00"), // Saturday
            sample("weight", "2026-01-31 10:20"), // Saturday
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertEqual(result.patterns.count, 1)
        let pattern = result.patterns[0]
        XCTAssertEqual(pattern.kindRaw, "weight")
        XCTAssertEqual(pattern.dayOfWeek, 7) // Saturday
        XCTAssertEqual(pattern.hourBucketStart, 9) // 9-12 bucket
        XCTAssertEqual(pattern.occurrenceCount, 5)
        XCTAssertEqual(pattern.confidence, 1.0, accuracy: 0.01)
    }

    func testNoPatternWithInsufficientSamples() {
        let samples = [
            sample("weight", "2026-01-03 10:00"), // Saturday
            sample("weight", "2026-01-10 10:00"), // Saturday
            sample("weight", "2026-01-17 10:00"), // Saturday
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertTrue(result.patterns.isEmpty)
    }

    func testNoPatternWhenRandomDays() {
        let samples = [
            sample("weight", "2026-01-05 10:00"), // Monday
            sample("weight", "2026-01-13 14:00"), // Tuesday
            sample("weight", "2026-01-18 08:00"), // Sunday
            sample("weight", "2026-01-22 20:00"), // Thursday
            sample("weight", "2026-01-28 11:00"), // Wednesday
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertTrue(result.patterns.isEmpty)
    }

    func testPatternConfidenceWithNoise() {
        // 4 Saturdays + 3 other days = 4/7 ≈ 57% > 40% threshold
        let samples = [
            sample("weight", "2026-01-03 10:00"), // Saturday
            sample("weight", "2026-01-05 14:00"), // Monday
            sample("weight", "2026-01-10 10:00"), // Saturday
            sample("weight", "2026-01-14 08:00"), // Wednesday
            sample("weight", "2026-01-17 10:00"), // Saturday
            sample("weight", "2026-01-20 16:00"), // Tuesday
            sample("weight", "2026-01-24 10:00"), // Saturday
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertEqual(result.patterns.count, 1)
        let pattern = result.patterns[0]
        XCTAssertEqual(pattern.occurrenceCount, 4)
        XCTAssertEqual(pattern.confidence, 4.0 / 7.0, accuracy: 0.01)
    }

    func testSamplesOutsideWindowExcluded() {
        // All samples > 90 days old
        let samples = [
            sample("weight", "2025-11-01 10:00"),
            sample("weight", "2025-11-08 10:00"),
            sample("weight", "2025-11-15 10:00"),
            sample("weight", "2025-11-22 10:00"),
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertTrue(result.patterns.isEmpty)
    }

    func testEmptySamplesReturnsEmptyResult() {
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: [], now: now, calendar: calendar)

        XCTAssertTrue(result.lastLogDates.isEmpty)
        XCTAssertTrue(result.averageIntervals.isEmpty)
        XCTAssertTrue(result.patterns.isEmpty)
    }

    func testMultipleMetricsPatternsDetectedSeparately() {
        let samples = [
            // Weight on Saturdays
            sample("weight", "2026-01-03 10:00"),
            sample("weight", "2026-01-10 10:00"),
            sample("weight", "2026-01-17 10:00"),
            sample("weight", "2026-01-24 10:00"),
            // Waist on Mondays
            sample("waist", "2026-01-05 18:00"),
            sample("waist", "2026-01-12 18:00"),
            sample("waist", "2026-01-19 18:00"),
            sample("waist", "2026-01-26 18:00"),
        ]
        let now = date("2026-03-20 12:00")
        let result = MetricFrequencyAnalyzer.analyze(samples: samples, now: now, calendar: calendar)

        XCTAssertEqual(result.patterns.count, 2)
        let kinds = Set(result.patterns.map(\.kindRaw))
        XCTAssertTrue(kinds.contains("weight"))
        XCTAssertTrue(kinds.contains("waist"))
    }
}
