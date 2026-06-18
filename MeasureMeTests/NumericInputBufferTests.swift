import XCTest
@testable import MeasureMe

final class NumericInputBufferTests: XCTestCase {
    func testFirstDigitReplacesInitialValue() {
        var buffer = NumericInputBuffer(value: 82.4, locale: Locale(identifier: "en_US"))

        buffer.appendDigit(7)

        XCTAssertEqual(buffer.text, "7")
        XCTAssertEqual(buffer.value, 7)
    }

    func testFirstSeparatorReplacesInitialValue() {
        var buffer = NumericInputBuffer(value: 82.4, locale: Locale(identifier: "pl_PL"))

        buffer.appendDecimalSeparator()

        XCTAssertEqual(buffer.text, "0,")
        XCTAssertEqual(buffer.value, 0)
    }

    func testLocalizedSeparatorsParseToDouble() {
        var english = NumericInputBuffer(value: nil, locale: Locale(identifier: "en_US"))
        english.appendDigit(1)
        english.appendDecimalSeparator()
        english.appendDigit(5)

        var polish = NumericInputBuffer(value: nil, locale: Locale(identifier: "pl_PL"))
        polish.appendDigit(1)
        polish.appendDecimalSeparator()
        polish.appendDigit(5)

        XCTAssertEqual(english.text, "1.5")
        XCTAssertEqual(polish.text, "1,5")
        XCTAssertEqual(english.value, 1.5)
        XCTAssertEqual(polish.value, 1.5)
    }

    func testRejectsSecondSeparatorAndThirdFractionDigit() {
        var buffer = NumericInputBuffer(value: nil, locale: Locale(identifier: "en_US"))
        buffer.appendDigit(1)
        buffer.appendDecimalSeparator()
        buffer.appendDigit(2)
        buffer.appendDecimalSeparator()
        buffer.appendDigit(3)
        buffer.appendDigit(4)

        XCTAssertEqual(buffer.text, "1.23")
    }

    func testNormalizesLeadingZero() {
        var buffer = NumericInputBuffer(value: nil, locale: Locale(identifier: "en_US"))
        buffer.appendDigit(0)
        buffer.appendDigit(0)
        buffer.appendDigit(5)

        XCTAssertEqual(buffer.text, "5")
    }

    func testBackspaceEditsInitialValueWithoutReplacingIt() {
        var buffer = NumericInputBuffer(value: 123, locale: Locale(identifier: "en_US"))

        buffer.deleteBackward()
        buffer.appendDigit(4)

        XCTAssertEqual(buffer.text, "124")
        XCTAssertEqual(buffer.value, 124)
    }

    func testClearProducesNilValue() {
        var buffer = NumericInputBuffer(value: 12.3, locale: Locale(identifier: "en_US"))

        buffer.clear()

        XCTAssertEqual(buffer.text, "")
        XCTAssertNil(buffer.value)
    }

    func testFieldIDReadsSystemAndCustomValues() {
        let metric = QuickAddFieldID.metric(.weight)
        let custom = QuickAddFieldID.custom("custom_test")

        XCTAssertEqual(
            metric.value(metricInputs: [.weight: 82.5], customInputs: [:]),
            82.5
        )
        XCTAssertEqual(
            custom.value(metricInputs: [:], customInputs: ["custom_test": 12]),
            12
        )
    }

    func testFieldIDTracksEditedFlagInCorrectCollection() {
        var editedKinds: Set<MetricKind> = []
        var editedCustomIDs: Set<String> = []
        let metric = QuickAddFieldID.metric(.waist)
        let custom = QuickAddFieldID.custom("custom_test")

        metric.markEdited(metricKinds: &editedKinds, customIDs: &editedCustomIDs)
        XCTAssertTrue(metric.wasEdited(metricKinds: editedKinds, customIDs: editedCustomIDs))
        XCTAssertFalse(custom.wasEdited(metricKinds: editedKinds, customIDs: editedCustomIDs))

        custom.markEdited(metricKinds: &editedKinds, customIDs: &editedCustomIDs)
        XCTAssertTrue(custom.wasEdited(metricKinds: editedKinds, customIDs: editedCustomIDs))
        XCTAssertEqual(editedKinds, [.waist])
        XCTAssertEqual(editedCustomIDs, ["custom_test"])
    }
}
