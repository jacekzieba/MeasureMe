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
            250,   // waist max = 200 cm
            kind: .waist,
            unitsSystem: "metric"
        )

        XCTAssertFalse(result.isValid)
    }

    func testWeightRangeMetric() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(75, kind: .weight, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(10, kind: .weight, unitsSystem: "metric").isValid)   // < 20 kg
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(400, kind: .weight, unitsSystem: "metric").isValid) // > 300 kg
    }

    func testNeckRangeMetric() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(38, kind: .neck, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(5, kind: .neck, unitsSystem: "metric").isValid)  // < 15 cm
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(80, kind: .neck, unitsSystem: "metric").isValid) // > 70 cm
    }

    func testBicepRangeImperial() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(15, kind: .leftBicep, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(2, kind: .rightBicep, unitsSystem: "imperial").isValid)  // < 6 in
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(35, kind: .leftBicep, unitsSystem: "imperial").isValid) // > 28 in
    }

    func testBodyFatRange() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(20, kind: .bodyFat, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(0, kind: .bodyFat, unitsSystem: "metric").isValid)   // < 1 %
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(75, kind: .bodyFat, unitsSystem: "metric").isValid) // > 70 %
    }

    func testThighRangeMetric() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(60, kind: .leftThigh, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(10, kind: .rightThigh, unitsSystem: "metric").isValid)  // < 20 cm
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(130, kind: .leftThigh, unitsSystem: "metric").isValid) // > 120 cm
    }

    // MARK: - Boundary values (exact min/max must pass, just outside must fail)

    func testWeightBoundaries() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(20.0, kind: .weight, unitsSystem: "metric").isValid)    // min
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(300.0, kind: .weight, unitsSystem: "metric").isValid)   // max
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(19.9, kind: .weight, unitsSystem: "metric").isValid)   // just below min
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(300.1, kind: .weight, unitsSystem: "metric").isValid)  // just above max
        // Imperial
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(44.0, kind: .weight, unitsSystem: "imperial").isValid)
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(660.0, kind: .weight, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(43.9, kind: .weight, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(660.1, kind: .weight, unitsSystem: "imperial").isValid)
    }

    func testBodyFatBoundaries() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(1.0, kind: .bodyFat, unitsSystem: "metric").isValid)    // min
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(70.0, kind: .bodyFat, unitsSystem: "metric").isValid)   // max
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(0.9, kind: .bodyFat, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(70.1, kind: .bodyFat, unitsSystem: "metric").isValid)
    }

    func testLeanBodyMassRange() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(70, kind: .leanBodyMass, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(9.9, kind: .leanBodyMass, unitsSystem: "metric").isValid)   // < 10 kg
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(200.1, kind: .leanBodyMass, unitsSystem: "metric").isValid) // > 200 kg
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(150, kind: .leanBodyMass, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(21.9, kind: .leanBodyMass, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(440.1, kind: .leanBodyMass, unitsSystem: "imperial").isValid)
    }

    func testWaistRange() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(80, kind: .waist, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(29.9, kind: .waist, unitsSystem: "metric").isValid)   // < 30 cm
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(200.1, kind: .waist, unitsSystem: "metric").isValid)  // > 200 cm
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(32, kind: .waist, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(11.9, kind: .waist, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(79.1, kind: .waist, unitsSystem: "imperial").isValid)
    }

    func testShouldersRange() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(120, kind: .shoulders, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(59.9, kind: .shoulders, unitsSystem: "metric").isValid)  // < 60 cm
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(200.1, kind: .shoulders, unitsSystem: "metric").isValid)
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(48, kind: .shoulders, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(23.9, kind: .shoulders, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(79.1, kind: .shoulders, unitsSystem: "imperial").isValid)
    }

    func testBustChestRange() {
        for kind: MetricKind in [.bust, .chest] {
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(90, kind: kind, unitsSystem: "metric").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(49.9, kind: kind, unitsSystem: "metric").isValid)   // < 50 cm
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(200.1, kind: kind, unitsSystem: "metric").isValid)
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(36, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(19.9, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(79.1, kind: kind, unitsSystem: "imperial").isValid)
        }
    }

    func testBicepRangeMetric() {
        for kind: MetricKind in [.leftBicep, .rightBicep] {
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(35, kind: kind, unitsSystem: "metric").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(14.9, kind: kind, unitsSystem: "metric").isValid)  // < 15 cm
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(70.1, kind: kind, unitsSystem: "metric").isValid) // > 70 cm
        }
    }

    func testForearmRange() {
        for kind: MetricKind in [.leftForearm, .rightForearm] {
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(30, kind: kind, unitsSystem: "metric").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(9.9, kind: kind, unitsSystem: "metric").isValid)   // < 10 cm
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(60.1, kind: kind, unitsSystem: "metric").isValid) // > 60 cm
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(12, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(3.9, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(24.1, kind: kind, unitsSystem: "imperial").isValid)
        }
    }

    func testHipsRange() {
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(100, kind: .hips, unitsSystem: "metric").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(49.9, kind: .hips, unitsSystem: "metric").isValid)   // < 50 cm
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(200.1, kind: .hips, unitsSystem: "metric").isValid)
        XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(40, kind: .hips, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(19.9, kind: .hips, unitsSystem: "imperial").isValid)
        XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(79.1, kind: .hips, unitsSystem: "imperial").isValid)
    }

    func testThighRangeImperial() {
        for kind: MetricKind in [.leftThigh, .rightThigh] {
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(20, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(7.9, kind: kind, unitsSystem: "imperial").isValid)  // < 8 in
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(47.1, kind: kind, unitsSystem: "imperial").isValid) // > 47 in
        }
    }

    func testCalfRange() {
        for kind: MetricKind in [.leftCalf, .rightCalf] {
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(38, kind: kind, unitsSystem: "metric").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(14.9, kind: kind, unitsSystem: "metric").isValid)  // < 15 cm
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(80.1, kind: kind, unitsSystem: "metric").isValid) // > 80 cm
            XCTAssertTrue(MetricInputValidator.validateMetricDisplayValue(15, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(5.9, kind: kind, unitsSystem: "imperial").isValid)
            XCTAssertFalse(MetricInputValidator.validateMetricDisplayValue(31.1, kind: kind, unitsSystem: "imperial").isValid)
        }
    }

    func testValidationMessageNonNilWhenInvalid() {
        // Każda niepoprawna wartość powinna zwracać message != nil
        let result = MetricInputValidator.validateMetricDisplayValue(0, kind: .neck, unitsSystem: "metric")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.message)
    }

    func testAllKindsHaveValidRangeInBothSystems() {
        // Smoke test — każdy kind w obu systemach musi mieć poprawny zakres i przejść walidację wartością środkową
        let systems = ["metric", "imperial"]
        for kind in MetricKind.allCases {
            for system in systems {
                let range = MetricInputValidator.metricDisplayRange(for: kind, unitsSystem: system)
                let midpoint = (range.lowerBound + range.upperBound) / 2
                let result = MetricInputValidator.validateMetricDisplayValue(midpoint, kind: kind, unitsSystem: system)
                XCTAssertTrue(result.isValid, "\(kind.rawValue)/\(system): midpoint \(midpoint) should be valid")
            }
        }
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
