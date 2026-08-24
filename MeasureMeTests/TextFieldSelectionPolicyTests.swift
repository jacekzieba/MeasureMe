/// Cel testow: Auto-zaznaczanie całej treści przy fokusie ma dotyczyć wyłącznie pól liczbowych.
/// Dlaczego to wazne: Globalny hook kasował treść pola wyszukiwania i kompozytora pytań do AI.
/// Kryteria zaliczenia: Tylko klawiatury liczbowe kwalifikują się do selectAll.

import XCTest
import UIKit
@testable import MeasureMe

final class TextFieldSelectionPolicyTests: XCTestCase {
    func testNumericKeyboardsSelectAllOnFocus() {
        XCTAssertTrue(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .decimalPad))
        XCTAssertTrue(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .numberPad))
    }

    func testTextKeyboardsKeepTheCaretWhereTheUserTapped() {
        // The Settings search field, the AI question composer, the profile name and the
        // custom-metric name all use a text keyboard; selecting all discards what they typed.
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .default))
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .emailAddress))
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .webSearch))
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .asciiCapable))
    }
}
