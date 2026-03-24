/// Cel testow: Weryfikuje definicje MetricKind (mapowania, jednostki, konwersje, nazwy).
/// Dlaczego to wazne: MetricKind steruje UI i obliczeniami; blad psuje wiele ekranow naraz.
/// Kryteria zaliczenia: Kontrakty enumow i konwersje sa zgodne z oczekiwaniami.

import XCTest
@testable import MeasureMe

final class MetricKindTests: XCTestCase {
    /// Co sprawdza: Sprawdza scenariusz: WeightConversionRoundTripForImperial.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testWeightConversionRoundTripForImperial() {
        let pounds = 180.0

        let inMetric = MetricKind.weight.valueToMetric(fromDisplay: pounds, unitsSystem: "imperial")
        let backToImperial = MetricKind.weight.valueForDisplay(fromMetric: inMetric, unitsSystem: "imperial")

        XCTAssertEqual(inMetric, 81.6466266, accuracy: 0.0001)
        XCTAssertEqual(backToImperial, pounds, accuracy: 0.0001)
    }

    /// Co sprawdza: Sprawdza scenariusz: LengthConversionRoundTripForImperial.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testLengthConversionRoundTripForImperial() {
        let inches = 70.0

        let inMetric = MetricKind.height.valueToMetric(fromDisplay: inches, unitsSystem: "imperial")
        let backToImperial = MetricKind.height.valueForDisplay(fromMetric: inMetric, unitsSystem: "imperial")

        XCTAssertEqual(inMetric, 177.8, accuracy: 0.0001)
        XCTAssertEqual(backToImperial, inches, accuracy: 0.0001)
    }

    /// Co sprawdza: Sprawdza scenariusz: BodyFatUnitAndConversionRemainStableAcrossSystems.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testBodyFatUnitAndConversionRemainStableAcrossSystems() {
        XCTAssertEqual(MetricKind.bodyFat.unitSymbol(unitsSystem: "metric"), "%")
        XCTAssertEqual(MetricKind.bodyFat.unitSymbol(unitsSystem: "imperial"), "%")

        let value = 23.5
        XCTAssertEqual(MetricKind.bodyFat.valueToMetric(fromDisplay: value, unitsSystem: "imperial"), value, accuracy: 0.0001)
        XCTAssertEqual(MetricKind.bodyFat.valueForDisplay(fromMetric: value, unitsSystem: "imperial"), value, accuracy: 0.0001)
    }

    @MainActor func testTrendOutcomeWithoutGoalRespectsMetricDirection() {
        XCTAssertEqual(
            MetricKind.waist.trendOutcome(from: 90, to: 88, goal: nil),
            .positive
        )
        XCTAssertEqual(
            MetricKind.weight.trendOutcome(from: 80, to: 82, goal: nil),
            .negative
        )
        XCTAssertEqual(
            MetricKind.leanBodyMass.trendOutcome(from: 50, to: 52, goal: nil),
            .positive
        )
    }

    /// Co sprawdza: Sprawdza scenariusz: ValueConversionRoundTripStaysFiniteAndStable.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testValueConversionRoundTripStaysFiniteAndStable() {
        let systems = ["metric", "imperial"]
        let sampleValue = 50.0

        for kind in MetricKind.allCases {
            for system in systems {
                let metric = kind.valueToMetric(fromDisplay: sampleValue, unitsSystem: system)
                let back = kind.valueForDisplay(fromMetric: metric, unitsSystem: system)

                XCTAssertTrue(metric.isFinite, "\(kind.rawValue)/\(system): toMetric produced non-finite")
                XCTAssertTrue(back.isFinite, "\(kind.rawValue)/\(system): forDisplay produced non-finite")
                XCTAssertEqual(back, sampleValue, accuracy: 0.0001,
                               "\(kind.rawValue)/\(system): round-trip drift \(sampleValue) → \(back)")
            }
        }
    }

    func testAllLogsFilterBySourceReturnsOnlyHealthKitSamples() {
        let manualSample = MetricSample(kind: .weight, value: 80, date: Date(timeIntervalSince1970: 1_700_000_000), source: .manual)
        let healthKitSample = MetricSample(kind: .weight, value: 79.8, date: Date(timeIntervalSince1970: 1_700_000_100), source: .healthKit)
        let customManualSample = MetricSample(kindRaw: "custom_demo", value: 10, date: Date(timeIntervalSince1970: 1_700_000_200), source: .manual)

        let filtered = AllLogsFilterEngine.filter(
            samples: [manualSample, healthKitSample, customManualSample],
            sourceFilter: .healthKit,
            dateFilter: .all
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.source, .healthKit)
    }

    func testAllLogsCustomRangeIncludesWholeEndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let rangeStart = calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 8, minute: 0))!
        let rangeEnd = calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 10, minute: 0))!
        let endOfRangeDay = calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 23, minute: 59, second: 59))!
        let nextDayStart = calendar.date(from: DateComponents(year: 2023, month: 11, day: 16, hour: 0, minute: 0, second: 0))!

        let inRangeAtStart = MetricSample(kind: .weight, value: 80, date: rangeStart)
        let inRangeAtEnd = MetricSample(kind: .weight, value: 79.9, date: endOfRangeDay)
        let outOfRange = MetricSample(kind: .weight, value: 79.8, date: nextDayStart)

        let filtered = AllLogsFilterEngine.filter(
            samples: [inRangeAtStart, inRangeAtEnd, outOfRange],
            sourceFilter: .all,
            dateFilter: .custom(start: rangeStart, end: rangeEnd),
            calendar: calendar
        )

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.date == rangeStart })
        XCTAssertTrue(filtered.contains { $0.date == endOfRangeDay })
    }

    func testMetricSampleSourceFallsBackToManualForLegacyUnknownRawValue() {
        let sample = MetricSample(kind: .weight, value: 80, date: .now)
        sample.sourceRaw = ""

        XCTAssertEqual(sample.source, .manual)
    }
}
