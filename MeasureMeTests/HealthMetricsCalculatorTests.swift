/// Cel testow: Sprawdza kalkulator metryk zdrowotnych (BMI/WHtR/ABSI/Conicity/RFM) na danych referencyjnych.
/// Dlaczego to wazne: To logika domenowa; blad daje falszywe interpretacje wynikow.
/// Kryteria zaliczenia: Dla danych testowych zwracane sa oczekiwane wartosci i kategorie.

import XCTest
@testable import MeasureMe

@MainActor
final class HealthMetricsCalculatorTests: XCTestCase {
    /// Co sprawdza: Sprawdza scenariusz: WHtRAndBMICalculations.
    /// Dlaczego: Utrzymuje poprawny kontrakt logiki domenowej (wyniki i kategorie).
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testWHtRAndBMICalculations() {
        let whtr = HealthMetricsCalculator.calculateWHtR(waistCm: 85, heightCm: 180)
        XCTAssertNotNil(whtr)
        XCTAssertEqual(whtr?.ratio ?? 0, 85.0 / 180.0, accuracy: 0.0001)

        let bmiAdult = HealthMetricsCalculator.calculateBMI(weightKg: 80, heightCm: 180, age: 30)
        XCTAssertNotNil(bmiAdult)
        XCTAssertEqual(bmiAdult?.bmi ?? 0, 24.69, accuracy: 0.05)
        XCTAssertEqual(bmiAdult?.category, .normal)
    }

    /// Co sprawdza: Sprawdza scenariusz: BMIAgeGroupsAndRFM.
    /// Dlaczego: Utrzymuje poprawny kontrakt logiki domenowej (wyniki i kategorie).
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testBMIAgeGroupsAndRFM() {
        let bmiChild = HealthMetricsCalculator.calculateBMI(weightKg: 65, heightCm: 160, age: 15)
        XCTAssertEqual(bmiChild?.ageGroup, .child)

        let bmiSenior = HealthMetricsCalculator.calculateBMI(weightKg: 72, heightCm: 165, age: 70)
        XCTAssertEqual(bmiSenior?.ageGroup, .senior)

        let rfmMale = HealthMetricsCalculator.calculateRFM(waistCm: 85, heightCm: 180, gender: .male)
        XCTAssertNotNil(rfmMale)
        XCTAssertEqual(rfmMale?.rfm ?? 0, 21.65, accuracy: 0.1)
        XCTAssertEqual(rfmMale?.category, .increased)
    }

    /// Co sprawdza: Sprawdza scenariusz: ABSIAndConicityNominalAndEdgeCases.
    /// Dlaczego: Utrzymuje poprawny kontrakt logiki domenowej (wyniki i kategorie).
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testABSIAndConicityNominalAndEdgeCases() {
        let absi = HealthMetricsCalculator.calculateABSI(
            waistCm: 85,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )
        XCTAssertNotNil(absi)
        XCTAssertTrue((absi?.absi ?? 0) > 0)

        let conicity = HealthMetricsCalculator.calculateConicity(
            waistCm: 85,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )
        XCTAssertNotNil(conicity)
        XCTAssertTrue((conicity?.conicity ?? 0) > 0)

        XCTAssertNil(HealthMetricsCalculator.calculateABSI(waistCm: nil, heightCm: 180, weightKg: 80, gender: .male))
        XCTAssertNil(HealthMetricsCalculator.calculateConicity(waistCm: 85, heightCm: 0, weightKg: 80, gender: .male))
    }
}
