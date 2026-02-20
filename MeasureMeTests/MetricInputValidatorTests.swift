/// Cel testow: Sprawdza walidacje danych wejsciowych metryk (zakresy, przypadki brzegowe).
/// Dlaczego to wazne: Walidacja chroni przed zapisem blednych danych i niestabilnymi obliczeniami.
/// Kryteria zaliczenia: Poprawne dane przechodza, a niepoprawne sa odrzucane z przewidywalnym wynikiem.

import XCTest
@testable import MeasureMe

final class MetricInputValidatorTests: XCTestCase {
    /// Co sprawdza: Sprawdza scenariusz: MetricValueRejectsInfinity.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testMetricValueRejectsInfinity() {
        let result = MetricInputValidator.validateMetricDisplayValue(
            .infinity,
            kind: .weight,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.message)
    }

    /// Co sprawdza: Sprawdza scenariusz: MetricValueRejectsNaN.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testMetricValueRejectsNaN() {
        let result = MetricInputValidator.validateMetricDisplayValue(
            .nan,
            kind: .weight,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.message)
    }

    /// Co sprawdza: Sprawdza scenariusz: MetricValueRejectsOutOfRangeLength.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testMetricValueRejectsOutOfRangeLength() {
        let result = MetricInputValidator.validateMetricDisplayValue(
            999,
            kind: .waist,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
    }

    /// Co sprawdza: Sprawdza scenariusz: AgeValidation.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testAgeValidation() {
        XCTAssertTrue(MetricInputValidator.validateAgeValue(35).isValid)
        XCTAssertFalse(MetricInputValidator.validateAgeValue(2).isValid)
        XCTAssertFalse(MetricInputValidator.validateAgeValue(150).isValid)
    }

    /// Co sprawdza: Sprawdza scenariusz: MetricDisplayRangeAlwaysHasLowerLessOrEqualUpper.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
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

    /// Co sprawdza: Sprawdza scenariusz: HeightValidationMetricAndImperial.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testHeightValidationMetricAndImperial() {
        XCTAssertTrue(MetricInputValidator.validateHeightMetricValue(180).isValid)
        XCTAssertFalse(MetricInputValidator.validateHeightMetricValue(20).isValid)

        XCTAssertTrue(MetricInputValidator.validateHeightImperial(feet: 5, inches: 11).isValid)
        XCTAssertFalse(MetricInputValidator.validateHeightImperial(feet: 0, inches: 8).isValid)
        XCTAssertFalse(MetricInputValidator.validateHeightImperial(feet: 9, inches: 0).isValid)
    }
}
