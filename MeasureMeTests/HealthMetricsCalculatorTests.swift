/// Cel testow: Sprawdza kalkulator metryk zdrowotnych (BMI/WHtR/ABSI/Conicity/RFM) na danych referencyjnych.
/// Dlaczego to wazne: To logika domenowa; blad daje falszywe interpretacje wynikow.
/// Kryteria zaliczenia: Dla danych testowych zwracane sa oczekiwane wartosci i kategorie.

import XCTest
import Foundation
@testable import MeasureMe

@MainActor
final class HealthMetricsCalculatorTests: XCTestCase {
    private func waistCmForABSIZScoreMale(_ zScore: Double, heightCm: Double = 180, weightKg: Double = 80) -> Double {
        let mean = 0.0807
        let stdDev = 0.0053
        let targetABSI = mean + zScore * stdDev
        let heightM = heightCm / 100.0
        let bmi = weightKg / (heightM * heightM)
        let waistM = targetABSI * (pow(bmi, 2.0 / 3.0) * sqrt(heightM))
        return waistM * 100.0
    }

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

    /// Co sprawdza: Granice kategorii CFR i poprawna formula CFR = WHtR / 0.50.
    func testCentralFatRiskBoundaries() {
        let low = HealthMetricsCalculator.calculateCentralFatRisk(waistCm: 85, heightCm: 180)
        XCTAssertNotNil(low)
        XCTAssertEqual(low?.category, .low)

        let moderate = HealthMetricsCalculator.calculateCentralFatRisk(waistCm: 90, heightCm: 180) // WHtR 0.50
        XCTAssertNotNil(moderate)
        XCTAssertEqual(moderate?.score ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(moderate?.category, .moderate)

        let high = HealthMetricsCalculator.calculateCentralFatRisk(waistCm: 110, heightCm: 170) // WHtR 0.647
        XCTAssertNotNil(high)
        XCTAssertEqual(high?.category, .high)
    }

    /// Co sprawdza: Wskaźniki zależne od płci zwracają requiresGender dla notSpecified.
    func testGenderDependentIndicatorsRequireGenderWhenNotSpecified() {
        let rfm = HealthMetricsCalculator.calculateRFMWithGenderRequirement(
            waistCm: 85,
            heightCm: 180,
            gender: .notSpecified
        )
        if case .requiresGender? = rfm {
            XCTAssertTrue(true)
        } else {
            XCTFail("RFM should require gender for .notSpecified")
        }

        let whr = HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: 85,
            hipsCm: 95,
            gender: .notSpecified
        )
        if case .requiresGender? = whr {
            XCTAssertTrue(true)
        } else {
            XCTFail("WHR should require gender for .notSpecified")
        }

        let waist = HealthMetricsCalculator.calculateWaistRisk(waistCm: 88, gender: .notSpecified)
        if case .requiresGender? = waist {
            XCTAssertTrue(true)
        } else {
            XCTFail("Waist risk should require gender for .notSpecified")
        }
    }

    /// Co sprawdza: Kategoryzacja Body Shape Risk oparta o ABSI z-score.
    func testBodyShapeRiskUsesZScoreCutoffs() {
        let result = HealthMetricsCalculator.calculateBodyShapeRisk(
            waistCm: 85,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )

        guard case .value(let value)? = result else {
            XCTFail("Expected value for male body shape risk")
            return
        }

        XCTAssertFalse(value.zScore.isNaN)
        XCTAssertFalse(value.score.isNaN)
        XCTAssertGreaterThanOrEqual(value.score, 0)
        XCTAssertLessThanOrEqual(value.score, 2.0)
    }

    func testBodyShapeRiskCategoryBoundaries() {
        let zLowEdge = -0.272
        let zHighEdge = 0.229

        let lowWaist = waistCmForABSIZScoreMale(zLowEdge - 0.001)
        let lowResult = HealthMetricsCalculator.calculateBodyShapeRisk(
            waistCm: lowWaist,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )
        guard case .value(let lowValue)? = lowResult else {
            XCTFail("Expected lowValue")
            return
        }
        XCTAssertEqual(lowValue.category, .low)

        let moderateLowWaist = waistCmForABSIZScoreMale(zLowEdge + 0.001)
        let moderateLow = HealthMetricsCalculator.calculateBodyShapeRisk(
            waistCm: moderateLowWaist,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )
        guard case .value(let moderateLowValue)? = moderateLow else {
            XCTFail("Expected moderateLowValue")
            return
        }
        XCTAssertEqual(moderateLowValue.category, .moderate)

        let moderateHighWaist = waistCmForABSIZScoreMale(zHighEdge - 0.001)
        let moderateHigh = HealthMetricsCalculator.calculateBodyShapeRisk(
            waistCm: moderateHighWaist,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )
        guard case .value(let moderateHighValue)? = moderateHigh else {
            XCTFail("Expected moderateHighValue")
            return
        }
        XCTAssertEqual(moderateHighValue.category, .moderate)

        let highWaist = waistCmForABSIZScoreMale(zHighEdge + 0.001)
        let highResult = HealthMetricsCalculator.calculateBodyShapeRisk(
            waistCm: highWaist,
            heightCm: 180,
            weightKg: 80,
            gender: .male
        )
        guard case .value(let highValue)? = highResult else {
            XCTFail("Expected highValue")
            return
        }
        XCTAssertEqual(highValue.category, .high)
    }

    /// Co sprawdza: Progi ryzyka obwodu pasa (M/F).
    func testWaistRiskThresholdsByGender() {
        guard case .value(let maleLow)? = HealthMetricsCalculator.calculateWaistRisk(waistCm: 94, gender: .male) else {
            XCTFail("Expected maleLow value")
            return
        }
        XCTAssertEqual(maleLow.category, .low)

        guard case .value(let maleModerate)? = HealthMetricsCalculator.calculateWaistRisk(waistCm: 100, gender: .male) else {
            XCTFail("Expected maleModerate value")
            return
        }
        XCTAssertEqual(maleModerate.category, .moderate)

        guard case .value(let femaleHigh)? = HealthMetricsCalculator.calculateWaistRisk(waistCm: 89, gender: .female) else {
            XCTFail("Expected femaleHigh value")
            return
        }
        XCTAssertEqual(femaleHigh.category, .high)
    }

    func testWHRThresholdsByGender() {
        guard case .value(let maleLow)? = HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: 89.9,
            hipsCm: 100,
            gender: .male
        ) else {
            XCTFail("Expected maleLow")
            return
        }
        XCTAssertEqual(maleLow.category, .lowRisk)

        guard case .value(let maleHigh)? = HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: 90,
            hipsCm: 100,
            gender: .male
        ) else {
            XCTFail("Expected maleHigh")
            return
        }
        XCTAssertEqual(maleHigh.category, .increasedRisk)

        guard case .value(let femaleLow)? = HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: 84.9,
            hipsCm: 100,
            gender: .female
        ) else {
            XCTFail("Expected femaleLow")
            return
        }
        XCTAssertEqual(femaleLow.category, .lowRisk)

        guard case .value(let femaleHigh)? = HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: 85,
            hipsCm: 100,
            gender: .female
        ) else {
            XCTFail("Expected femaleHigh")
            return
        }
        XCTAssertEqual(femaleHigh.category, .increasedRisk)
    }
}
