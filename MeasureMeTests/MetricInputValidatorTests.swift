import XCTest
@testable import MeasureMe

final class MetricInputValidatorTests: XCTestCase {
    func testMetricValueRejectsInfinity() {
        let result = MetricInputValidator.validateMetricDisplayValue(
            .infinity,
            kind: .weight,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.message)
    }

    func testMetricValueRejectsNaN() {
        let result = MetricInputValidator.validateMetricDisplayValue(
            .nan,
            kind: .weight,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.message)
    }

    func testMetricValueRejectsOutOfRangeLength() {
        let result = MetricInputValidator.validateMetricDisplayValue(
            999,
            kind: .waist,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
    }

    func testAgeValidation() {
        XCTAssertTrue(MetricInputValidator.validateAgeValue(35).isValid)
        XCTAssertFalse(MetricInputValidator.validateAgeValue(2).isValid)
        XCTAssertFalse(MetricInputValidator.validateAgeValue(150).isValid)
    }

    func testMetricDisplayRangeAlwaysHasLowerLessOrEqualUpper() {
        let systems = ["metric", "imperial"]
        for kind in MetricKind.allCases {
            for system in systems {
                let range = MetricInputValidator.metricDisplayRange(for: kind, unitsSystem: system)
                XCTAssertLessThanOrEqual(
                    range.lowerBound,
                    range.upperBound,
                    "\(kind.rawValue) / \(system): lower \(range.lowerBound) > upper \(range.upperBound)"
                )
            }
        }
    }

    func testHeightValidationMetricAndImperial() {
        XCTAssertTrue(MetricInputValidator.validateHeightMetricValue(180).isValid)
        XCTAssertFalse(MetricInputValidator.validateHeightMetricValue(20).isValid)

        XCTAssertTrue(MetricInputValidator.validateHeightImperial(feet: 5, inches: 11).isValid)
        XCTAssertFalse(MetricInputValidator.validateHeightImperial(feet: 0, inches: 8).isValid)
        XCTAssertFalse(MetricInputValidator.validateHeightImperial(feet: 9, inches: 0).isValid)
    }
}
