import XCTest
@testable import MeasureMe

final class MetricKindTests: XCTestCase {
    func testWeightConversionRoundTripForImperial() {
        let pounds = 180.0

        let inMetric = MetricKind.weight.valueToMetric(fromDisplay: pounds, unitsSystem: "imperial")
        let backToImperial = MetricKind.weight.valueForDisplay(fromMetric: inMetric, unitsSystem: "imperial")

        XCTAssertEqual(inMetric, 81.6466266, accuracy: 0.0001)
        XCTAssertEqual(backToImperial, pounds, accuracy: 0.0001)
    }

    func testLengthConversionRoundTripForImperial() {
        let inches = 70.0

        let inMetric = MetricKind.height.valueToMetric(fromDisplay: inches, unitsSystem: "imperial")
        let backToImperial = MetricKind.height.valueForDisplay(fromMetric: inMetric, unitsSystem: "imperial")

        XCTAssertEqual(inMetric, 177.8, accuracy: 0.0001)
        XCTAssertEqual(backToImperial, inches, accuracy: 0.0001)
    }

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
}
