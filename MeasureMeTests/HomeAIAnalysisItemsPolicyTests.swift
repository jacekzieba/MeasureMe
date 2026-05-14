import XCTest
@testable import MeasureMe

final class HomeAIAnalysisItemsPolicyTests: XCTestCase {
    func testVisibleItemsAreCappedAtFive() {
        let items = (0..<7).map { makeItem(title: "Primary \($0)") }

        let visible = HomeAIAnalysisItemsPolicy.visibleItems(
            primary: items,
            fallback: [makeItem(title: "Fallback")]
        )

        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.map(\.title), ["Primary 0", "Primary 1", "Primary 2", "Primary 3", "Primary 4"])
    }

    func testFallbackItemsFillSparseAnalysis() {
        let visible = HomeAIAnalysisItemsPolicy.visibleItems(
            primary: [makeItem(title: "Primary")],
            fallback: [makeItem(title: "Fallback 1"), makeItem(title: "Fallback 2")]
        )

        XCTAssertEqual(visible.map(\.title), ["Primary", "Fallback 1", "Fallback 2"])
    }

    func testPrimaryItemsWinWhenAnalysisIsUseful() {
        let visible = HomeAIAnalysisItemsPolicy.visibleItems(
            primary: [
                makeItem(title: "Primary 1"),
                makeItem(title: "Primary 2"),
                makeItem(title: "Primary 3")
            ],
            fallback: [makeItem(title: "Fallback")]
        )

        XCTAssertEqual(visible.map(\.title), ["Primary 1", "Primary 2", "Primary 3"])
    }

    private func makeItem(title: String) -> HomeAIAnalysisItem {
        HomeAIAnalysisItem(
            symbol: "sparkles",
            title: title,
            detail: "Detail",
            tone: .neutral
        )
    }
}
