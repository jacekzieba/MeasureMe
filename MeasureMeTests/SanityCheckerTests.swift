/// Cel testow: Sprawdza wykrywanie nierealistycznych zmian pomiarow (sanity check).
/// Dlaczego to wazne: Chroni uzytkownika przed przypadkowym zapisem blednych wartosci.
/// Kryteria zaliczenia: Normalne zmiany nie generuja ostrzezen, a ekstremalne sa wykrywane.

import XCTest
@testable import MeasureMe

final class SanityCheckerTests: XCTestCase {

    // MARK: - Helpers

    private func date(daysAgo days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    private func date(monthsAgo months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -months, to: Date())!
    }

    // MARK: - Tests

    /// 1 kg change over 1 week — well within 3 kg/week threshold.
    func testNormalWeightChange_noWarning() {
        let result = SanityChecker.check(
            entries: [(.weight, 76.0, Date())],
            previousValues: [.weight: (value: 75.0, date: date(daysAgo: 7))]
        )
        XCTAssertTrue(result.isEmpty, "1 kg/week should not trigger a warning")
    }

    /// 10 kg change in 1 day — threshold = 3 * (1/7) = 0.43 kg.
    func testExtremeWeightChange_warning() {
        let result = SanityChecker.check(
            entries: [(.weight, 85.0, Date())],
            previousValues: [.weight: (value: 75.0, date: date(daysAgo: 1))]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .weight)
    }

    /// 15 kg over 6 months (~26 weeks). Allowed = 3 * 26 = 78 kg. 15 < 78 — no warning.
    func testLargeChange_overLongPeriod_noWarning() {
        let result = SanityChecker.check(
            entries: [(.weight, 90.0, Date())],
            previousValues: [.weight: (value: 75.0, date: date(monthsAgo: 6))]
        )
        XCTAssertTrue(result.isEmpty, "15 kg over 6 months should be OK")
    }

    /// 15 kg in 3 days. Allowed = 3 * (3/7) = ~1.29 kg. Warning expected.
    func testLargeChange_overShortPeriod_warning() {
        let result = SanityChecker.check(
            entries: [(.weight, 90.0, Date())],
            previousValues: [.weight: (value: 75.0, date: date(daysAgo: 3))]
        )
        XCTAssertEqual(result.count, 1)
    }

    /// No previous value — first-ever entry. No warning regardless of value.
    func testFirstEntry_noPreviousValue_noWarning() {
        let result = SanityChecker.check(
            entries: [(.weight, 200.0, Date())],
            previousValues: [:]
        )
        XCTAssertTrue(result.isEmpty, "First entry should never trigger a warning")
    }

    /// 10% body fat change in 2 days. Threshold = 3%/week, allowed = 3 * (2/7) = ~0.86%. Warning.
    func testBodyFatExtremeChange_warning() {
        let result = SanityChecker.check(
            entries: [(.bodyFat, 25.0, Date())],
            previousValues: [.bodyFat: (value: 15.0, date: date(daysAgo: 2))]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .bodyFat)
    }

    /// Same-day entry (0 elapsed days). Uses minimum 1-day window.
    /// 5 kg change → allowed = 3 * (1/7) = ~0.43 kg. Warning.
    func testSameDayEntry_usesMinimumWindow() {
        let now = Date()
        let result = SanityChecker.check(
            entries: [(.weight, 80.0, now)],
            previousValues: [.weight: (value: 75.0, date: now)]
        )
        XCTAssertEqual(result.count, 1, "Same-day 5 kg change should trigger warning")
    }

    /// Two metrics: weight normal change + waist extreme change. Only waist flagged.
    func testMultipleMetrics_mixedResults() {
        let result = SanityChecker.check(
            entries: [
                (.weight, 75.5, Date()),   // +0.5 kg in 7 days — OK
                (.waist, 100.0, Date()),   // +20 cm in 7 days — threshold 5 cm/week
            ],
            previousValues: [
                .weight: (value: 75.0, date: date(daysAgo: 7)),
                .waist: (value: 80.0, date: date(daysAgo: 7)),
            ]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .waist)
    }

    /// Change exactly at the allowed threshold — strict `>` means no warning.
    func testExactlyAtThreshold_noWarning() {
        // 3 kg over exactly 1 week. Allowed = 3 * 1 = 3.0. Change = 3.0 → not > 3.0.
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let result = SanityChecker.check(
            entries: [(.weight, 78.0, now)],
            previousValues: [.weight: (value: 75.0, date: oneWeekAgo)]
        )
        XCTAssertTrue(result.isEmpty, "Change exactly at threshold should not trigger")
    }

    /// Every MetricKind must have a positive threshold.
    func testAllMetricsHaveThresholds() {
        for kind in MetricKind.allCases {
            let threshold = SanityChecker.maxChangePerWeek(for: kind)
            XCTAssertGreaterThan(threshold, 0, "\(kind.rawValue) must have a positive threshold")
        }
    }

    /// Waist +20 cm in 2 days. Threshold = 5 cm/week, allowed = 5 * (2/7) = ~1.43 cm. Warning.
    func testLengthMetric_extremeChange() {
        let result = SanityChecker.check(
            entries: [(.waist, 100.0, Date())],
            previousValues: [.waist: (value: 80.0, date: date(daysAgo: 2))]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .waist)
    }
}
