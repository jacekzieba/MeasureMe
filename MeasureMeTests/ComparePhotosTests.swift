/// Cel testu: Weryfikuje logikę obliczania zmian metryk oraz clamp skali ghost overlay.
/// Dlaczego to ważne: MetricChange.changes() jest kluczową logiką porównywania zdjęć — musi poprawnie
/// dopasowywać metryki, liczyć różnice i sortować wyniki.
/// Kryteria zaliczenia: Wszystkie scenariusze (wspólne metryki, brak wspólnych, puste dane, clamp) przechodzą.

@testable import MeasureMe

import XCTest

final class MetricChangeTests: XCTestCase {

    // MARK: - MetricChange.changes()

    func testChanges_matchesCommonMetrics() throws {
        let older = [
            MetricValueSnapshot(kind: .weight, value: 90.0, unit: "kg"),
            MetricValueSnapshot(kind: .waist, value: 85.0, unit: "cm"),
        ]
        let newer = [
            MetricValueSnapshot(kind: .weight, value: 82.0, unit: "kg"),
            MetricValueSnapshot(kind: .waist, value: 80.0, unit: "cm"),
        ]

        let changes = MetricChange.changes(older: older, newer: newer)

        XCTAssertEqual(changes.count, 2)

        let waist = try XCTUnwrap(changes.first { $0.kind == .waist })
        XCTAssertEqual(waist.oldValue, 85.0)
        XCTAssertEqual(waist.newValue, 80.0)
        XCTAssertEqual(waist.difference, -5.0, accuracy: 0.001)

        let weight = try XCTUnwrap(changes.first { $0.kind == .weight })
        XCTAssertEqual(weight.difference, -8.0, accuracy: 0.001)
    }

    func testChanges_sortedByTitle() {
        let older = [
            MetricValueSnapshot(kind: .weight, value: 80.0, unit: "kg"),
            MetricValueSnapshot(kind: .bodyFat, value: 20.0, unit: "%"),
            MetricValueSnapshot(kind: .hips, value: 100.0, unit: "cm"),
        ]
        let newer = [
            MetricValueSnapshot(kind: .weight, value: 78.0, unit: "kg"),
            MetricValueSnapshot(kind: .bodyFat, value: 18.0, unit: "%"),
            MetricValueSnapshot(kind: .hips, value: 98.0, unit: "cm"),
        ]

        let changes = MetricChange.changes(older: older, newer: newer)
        let titles = changes.map { $0.kind.title }

        XCTAssertEqual(titles, titles.sorted())
    }

    func testChanges_onlyCommonMetricsIncluded() {
        let older = [
            MetricValueSnapshot(kind: .weight, value: 80.0, unit: "kg"),
            MetricValueSnapshot(kind: .waist, value: 85.0, unit: "cm"),
        ]
        let newer = [
            MetricValueSnapshot(kind: .weight, value: 78.0, unit: "kg"),
            MetricValueSnapshot(kind: .chest, value: 100.0, unit: "cm"),
        ]

        let changes = MetricChange.changes(older: older, newer: newer)

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .weight)
    }

    func testChanges_noCommonMetrics_returnsEmpty() {
        let older = [MetricValueSnapshot(kind: .weight, value: 80.0, unit: "kg")]
        let newer = [MetricValueSnapshot(kind: .waist, value: 85.0, unit: "cm")]

        let changes = MetricChange.changes(older: older, newer: newer)

        XCTAssertTrue(changes.isEmpty)
    }

    func testChanges_bothEmpty_returnsEmpty() {
        let changes = MetricChange.changes(older: [], newer: [])
        XCTAssertTrue(changes.isEmpty)
    }

    func testChanges_noChange_differenceIsZero() throws {
        let older = [MetricValueSnapshot(kind: .weight, value: 80.0, unit: "kg")]
        let newer = [MetricValueSnapshot(kind: .weight, value: 80.0, unit: "kg")]

        let changes = MetricChange.changes(older: older, newer: newer)

        XCTAssertEqual(changes.count, 1)
        let weight = try XCTUnwrap(changes.first)
        XCTAssertEqual(weight.difference, 0.0, accuracy: 0.001)
    }

    // MARK: - MetricChange.percentageChange

    func testPercentageChange_normalCase() throws {
        let change = MetricChange(kind: .weight, oldValue: 100.0, newValue: 90.0, difference: -10.0, storedUnit: "kg")
        let pct = try XCTUnwrap(change.percentageChange)
        XCTAssertEqual(pct, -10.0, accuracy: 0.001)
    }

    func testPercentageChange_zeroOldValue_returnsNil() {
        let change = MetricChange(kind: .bodyFat, oldValue: 0.0, newValue: 5.0, difference: 5.0, storedUnit: "%")
        XCTAssertNil(change.percentageChange)
    }

    // MARK: - Ghost Scale Clamp

    func testClampedGhostScale_withinBounds() {
        let result = MetricChange.clampedGhostScale(1.0, magnification: 1.5)
        XCTAssertEqual(result, 1.5, accuracy: 0.001)
    }

    func testClampedGhostScale_clampedToMinimum() {
        let result = MetricChange.clampedGhostScale(0.6, magnification: 0.1)
        XCTAssertEqual(result, 0.5, accuracy: 0.001)
    }

    func testClampedGhostScale_clampedToMaximum() {
        let result = MetricChange.clampedGhostScale(2.0, magnification: 5.0)
        XCTAssertEqual(result, 3.0, accuracy: 0.001)
    }

    func testClampedGhostScale_atExactBoundaries() {
        XCTAssertEqual(MetricChange.clampedGhostScale(0.5, magnification: 1.0), 0.5, accuracy: 0.001)
        XCTAssertEqual(MetricChange.clampedGhostScale(3.0, magnification: 1.0), 3.0, accuracy: 0.001)
    }
}
