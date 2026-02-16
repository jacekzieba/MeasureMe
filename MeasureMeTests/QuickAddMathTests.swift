import XCTest
@testable import MeasureMe

final class QuickAddMathTests: XCTestCase {
    func testRulerRangeFallsBackForNonFiniteBase() {
        let valid = 0.1...300.0

        // NaN base → lo/hi are NaN → guard fails → returns validRange
        let nanResult = QuickAddMath.rulerRange(base: .nan, span: 30, validRange: valid)
        XCTAssertEqual(nanResult, valid)

        // +Infinity base → hi overflows → guard fails → returns validRange
        let infResult = QuickAddMath.rulerRange(base: .infinity, span: 30, validRange: valid)
        XCTAssertEqual(infResult, valid)

        // -Infinity base → lo underflows → guard fails → returns validRange
        let negInfResult = QuickAddMath.rulerRange(base: -.infinity, span: 30, validRange: valid)
        XCTAssertEqual(negInfResult, valid)
    }

    func testStepIndexHandlesNonFiniteWithoutCrash() {
        // NaN value → raw is NaN → returns 0
        XCTAssertEqual(QuickAddMath.stepIndex(value: .nan, lowerBound: 0, step: 0.1), 0)

        // Zero step → division by zero → raw is inf → returns 0
        XCTAssertEqual(QuickAddMath.stepIndex(value: 5, lowerBound: 0, step: 0), 0)

        // Infinity value → raw is inf → returns 0
        XCTAssertEqual(QuickAddMath.stepIndex(value: .infinity, lowerBound: 0, step: 0.1), 0)
    }

    // MARK: - rulerRange clamping

    func testRulerRangeClampsToBounds() {
        let valid = 0.1...300.0

        // Base near lower bound → lo clamped to validRange.lowerBound
        let lowResult = QuickAddMath.rulerRange(base: 5, span: 30, validRange: valid)
        XCTAssertEqual(lowResult.lowerBound, 0.1, accuracy: 0.001)
        XCTAssertEqual(lowResult.upperBound, 35, accuracy: 0.001)

        // Base near upper bound → hi clamped to validRange.upperBound
        let highResult = QuickAddMath.rulerRange(base: 295, span: 30, validRange: valid)
        XCTAssertEqual(highResult.lowerBound, 265, accuracy: 0.001)
        XCTAssertEqual(highResult.upperBound, 300, accuracy: 0.001)
    }

    func testRulerRangeNormalCase() {
        let valid = 0.1...300.0
        let result = QuickAddMath.rulerRange(base: 80, span: 30, validRange: valid)
        XCTAssertEqual(result.lowerBound, 50, accuracy: 0.001)
        XCTAssertEqual(result.upperBound, 110, accuracy: 0.001)
    }

    // MARK: - tickCount bounds

    func testTickCountStaysInBounds() {
        // Zero span → raw ≈ 1 → clamped to minimum 8
        XCTAssertEqual(QuickAddMath.tickCount(span: 0, step: 0.1), 8)

        // Huge span / tiny step → raw very large → clamped to maximum 40
        XCTAssertEqual(QuickAddMath.tickCount(span: 10000, step: 0.1), 40)

        // Normal case → should be between 8 and 40
        let normal = QuickAddMath.tickCount(span: 60, step: 0.1)
        XCTAssertGreaterThanOrEqual(normal, 8)
        XCTAssertLessThanOrEqual(normal, 40)
    }
}
