import XCTest
@testable import MeasureMe

@MainActor
final class HomeKeyMetricTileWidthTests: XCTestCase {
    /// Key-metric tiles must fill the carousel exactly, so no sliver of a further tile shows
    /// at the edge (it read as clipped next to the trend charts on iPhone Duo).
    func testTilesFillTheCarouselExactly() {
        for width in [358.0, 400.0, 408.0, 520.0, 900.0] as [CGFloat] {
            let tile = HomeView.keyMetricTileWidth(forCarouselWidth: width)
            let count = ((width + 12) / (tile + 12)).rounded()
            XCTAssertEqual(count * tile + (count - 1) * 12, width, accuracy: 0.001, "width \(width)")
            XCTAssertGreaterThanOrEqual(tile, 156, "width \(width)")
        }
    }

    func testA390PointIPhoneKeepsTwo173PointTiles() {
        XCTAssertEqual(HomeView.keyMetricTileWidth(forCarouselWidth: 358), 173)
    }

    /// Layout passes a zero width before the carousel is sized; a negative frame logs "Invalid frame dimension".
    func testAZeroWidthCarouselNeverGivesANegativeTile() {
        XCTAssertEqual(HomeView.keyMetricTileWidth(forCarouselWidth: 0), 0)
    }
}
