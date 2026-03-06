import XCTest
@testable import MeasureMe

@MainActor
final class PhysiqueIndicatorsCalculatorTests: XCTestCase {

    func testSWRAndCWRCalculations() {
        let swr = PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: 120, waistCm: 80)
        XCTAssertNotNil(swr)
        XCTAssertEqual(swr?.value ?? 0, 1.5, accuracy: 0.0001)

        let cwr = PhysiqueIndicatorsCalculator.calculateCWR(chestCm: 105, waistCm: 84, gender: .male)
        guard case .value(let cwrValue)? = cwr else {
            XCTFail("Expected CWR value for male")
            return
        }
        XCTAssertEqual(cwrValue.value, 1.25, accuracy: 0.01)
    }

    func testHWRAndBWRCalculations() {
        let hwr = PhysiqueIndicatorsCalculator.calculateHWR(hipsCm: 104, waistCm: 74, gender: .female)
        guard case .value(let hwrValue)? = hwr else {
            XCTFail("Expected HWR value for female")
            return
        }
        XCTAssertEqual(hwrValue.value, 104.0 / 74.0, accuracy: 0.0001)

        let bwr = PhysiqueIndicatorsCalculator.calculateBWR(bustCm: 96, chestCm: nil, waistCm: 74, gender: .female)
        guard case .value(let bwrValue)? = bwr else {
            XCTFail("Expected BWR value for female")
            return
        }
        XCTAssertEqual(bwrValue.value, 96.0 / 74.0, accuracy: 0.0001)
    }

    func testRequiresGenderForGenderDependentPhysiqueMetrics() {
        let cwr = PhysiqueIndicatorsCalculator.calculateCWR(chestCm: 100, waistCm: 80, gender: .notSpecified)
        if case .requiresGender? = cwr {
            XCTAssertTrue(true)
        } else {
            XCTFail("CWR should require gender")
        }

        let bwr = PhysiqueIndicatorsCalculator.calculateBWR(bustCm: 95, chestCm: 98, waistCm: 75, gender: .notSpecified)
        if case .requiresGender? = bwr {
            XCTAssertTrue(true)
        } else {
            XCTFail("BWR should require gender")
        }

        let bodyFat = PhysiqueIndicatorsCalculator.classifyBodyFat(percent: 22, gender: .notSpecified)
        if case .requiresGender? = bodyFat {
            XCTAssertTrue(true)
        } else {
            XCTFail("Body fat classification should require gender")
        }
    }

    func testBWRFallbackUsesChestWhenBustMissing() {
        let bwr = PhysiqueIndicatorsCalculator.calculateBWR(bustCm: nil, chestCm: 98, waistCm: 74, gender: .female)
        guard case .value(let value)? = bwr else {
            XCTFail("Expected fallback to chest value")
            return
        }

        XCTAssertEqual(value.value, 98.0 / 74.0, accuracy: 0.0001)
    }

    func testWHtRVisualAndRFMClassification() {
        let whtr = PhysiqueIndicatorsCalculator.classifyWHtRVisual(waistCm: 80, heightCm: 180)
        XCTAssertNotNil(whtr)
        XCTAssertEqual(whtr?.category, .visibleDefinition)

        let rfmClass = PhysiqueIndicatorsCalculator.classifyRFM(rfm: 22, gender: .male)
        guard case .value(let result)? = rfmClass else {
            XCTFail("Expected RFM classification value")
            return
        }
        XCTAssertEqual(result.category, .average)
    }

    func testRatioCategoryThresholds() {
        let swrAverage = PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: 144, waistCm: 100)
        XCTAssertEqual(swrAverage?.category, .average)

        let swrAthletic = PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: 145, waistCm: 100)
        XCTAssertEqual(swrAthletic?.category, .athletic)

        let swrTop = PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: 160, waistCm: 100)
        XCTAssertEqual(swrTop?.category, .top)

        let cwrTop = PhysiqueIndicatorsCalculator.calculateCWR(chestCm: 130, waistCm: 100, gender: .male)
        guard case .value(let cwrTopValue)? = cwrTop else {
            XCTFail("Expected cwrTopValue")
            return
        }
        XCTAssertEqual(cwrTopValue.category, .top)

        let hwrAthletic = PhysiqueIndicatorsCalculator.calculateHWR(hipsCm: 140, waistCm: 100, gender: .female)
        guard case .value(let hwrAthleticValue)? = hwrAthletic else {
            XCTFail("Expected hwrAthleticValue")
            return
        }
        XCTAssertEqual(hwrAthleticValue.category, .athletic)
    }

    func testSHRBalanceCategories() {
        guard case .value(let lower)? = PhysiqueIndicatorsCalculator.calculateSHR(shouldersCm: 95, hipsCm: 100, gender: .male) else {
            XCTFail("Expected lower")
            return
        }
        XCTAssertEqual(lower.category, .lowerDominant)

        guard case .value(let balanced)? = PhysiqueIndicatorsCalculator.calculateSHR(shouldersCm: 115, hipsCm: 100, gender: .female) else {
            XCTFail("Expected balanced")
            return
        }
        XCTAssertEqual(balanced.category, .balanced)

        guard case .value(let upper)? = PhysiqueIndicatorsCalculator.calculateSHR(shouldersCm: 130, hipsCm: 100, gender: .female) else {
            XCTFail("Expected upper")
            return
        }
        XCTAssertEqual(upper.category, .upperDominant)
    }

    func testBodyFatThresholdsByGender() {
        guard case .value(let maleAthlete)? = PhysiqueIndicatorsCalculator.classifyBodyFat(percent: 13, gender: .male) else {
            XCTFail("Expected maleAthlete")
            return
        }
        XCTAssertEqual(maleAthlete.category, .athletes)

        guard case .value(let maleHigh)? = PhysiqueIndicatorsCalculator.classifyBodyFat(percent: 25, gender: .male) else {
            XCTFail("Expected maleHigh")
            return
        }
        XCTAssertEqual(maleHigh.category, .high)

        guard case .value(let femaleFitness)? = PhysiqueIndicatorsCalculator.classifyBodyFat(percent: 24, gender: .female) else {
            XCTFail("Expected femaleFitness")
            return
        }
        XCTAssertEqual(femaleFitness.category, .fitness)

        guard case .value(let femaleHigh)? = PhysiqueIndicatorsCalculator.classifyBodyFat(percent: 32, gender: .female) else {
            XCTFail("Expected femaleHigh")
            return
        }
        XCTAssertEqual(femaleHigh.category, .high)
    }

    func testMissingInputHandling() {
        XCTAssertNil(PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: nil, waistCm: 80))
        XCTAssertNil(PhysiqueIndicatorsCalculator.calculateCWR(chestCm: nil, waistCm: 80, gender: .male))
        XCTAssertNil(PhysiqueIndicatorsCalculator.calculateHWR(hipsCm: nil, waistCm: 80, gender: .female))
        XCTAssertNil(PhysiqueIndicatorsCalculator.calculateBWR(bustCm: nil, chestCm: nil, waistCm: 80, gender: .female))
        XCTAssertNil(PhysiqueIndicatorsCalculator.calculateSHR(shouldersCm: nil, hipsCm: 100, gender: .male))
        XCTAssertNil(PhysiqueIndicatorsCalculator.classifyWHtRVisual(waistCm: nil, heightCm: 180))
        XCTAssertNil(PhysiqueIndicatorsCalculator.classifyBodyFat(percent: nil, gender: .male))
    }
}
