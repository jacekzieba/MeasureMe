import XCTest
import SwiftUI
@testable import MeasureMe

final class PhotoGridLayoutModeTests: XCTestCase {
    func testCompactWidthKeepsTheModeColumnCount() {
        XCTAssertEqual(PhotoGridLayoutMode.review.columnCount(for: .compact), 2)
        XCTAssertEqual(PhotoGridLayoutMode.compact.columnCount(for: .compact), 3)
        XCTAssertEqual(PhotoGridLayoutMode.review.columnCount(for: nil), 2)
    }

    /// An open iPhone Duo reports regular width; the grid doubles to an even count so it
    /// splits cleanly around the fold.
    func testRegularWidthDoublesToAnEvenColumnCount() {
        XCTAssertEqual(PhotoGridLayoutMode.review.columnCount(for: .regular), 4)
        XCTAssertEqual(PhotoGridLayoutMode.compact.columnCount(for: .regular), 6)
    }
}
