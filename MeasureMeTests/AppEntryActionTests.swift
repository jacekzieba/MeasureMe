import XCTest
@testable import MeasureMe

final class AppEntryActionTests: XCTestCase {
    func testShortcutTypeMapping() {
        XCTAssertEqual(
            AppEntryAction(shortcutItemType: "com.jacek.measureme.quickAdd"),
            .openQuickAdd
        )
        XCTAssertEqual(
            AppEntryAction(shortcutItemType: "com.jacek.measureme.addPhoto"),
            .openAddPhoto
        )
    }

    func testUnknownShortcutTypeReturnsNil() {
        XCTAssertNil(AppEntryAction(shortcutItemType: "com.jacek.measureme.unknown"))
    }
}
