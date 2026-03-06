import XCTest
@testable import MeasureMe

final class SinglePhotoSaveMergeTests: XCTestCase {

    func testInsertRecentlySavedPhoto_WhenMatchesFilter_InsertsWithoutDuplicate() {
        let baseline = Date(timeIntervalSince1970: 1_730_000_000)
        let newest = makeItem(id: "n", date: baseline.addingTimeInterval(-10))
        let oldest = makeItem(id: "o", date: baseline.addingTimeInterval(-30))
        let saved = makeItem(id: "s", date: baseline.addingTimeInterval(-20))

        let result = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: saved,
            matchesFilter: true,
            items: [newest, oldest],
            hasMore: false,
            pageSize: 60,
            fetchOffset: 2
        )

        XCTAssertTrue(result.didUpdateList)
        XCTAssertEqual(result.orderedIDs, ["n", "s", "o"])
        XCTAssertEqual(result.fetchOffset, 2)
        XCTAssertEqual(result.orderedIDs.filter { $0 == "s" }.count, 1)
    }

    func testInsertRecentlySavedPhoto_WhenHasMoreAndWithinWindow_IncrementsOffset() {
        let baseline = Date(timeIntervalSince1970: 1_730_500_000)
        let page = (0..<60).map { offset in
            makeItem(id: "p\(offset)", date: baseline.addingTimeInterval(TimeInterval(-offset - 1)))
        }
        let saved = makeItem(id: "saved", date: baseline.addingTimeInterval(5))

        let result = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: saved,
            matchesFilter: true,
            items: page,
            hasMore: true,
            pageSize: 60,
            fetchOffset: 60
        )

        XCTAssertTrue(result.didUpdateList)
        XCTAssertEqual(result.fetchOffset, 61)
        XCTAssertEqual(result.orderedIDs.count, 60)
        XCTAssertEqual(result.orderedIDs.first, "saved")
    }

    func testInsertRecentlySavedPhoto_WhenOutsideCurrentWindow_DoesNotInsert() {
        let baseline = Date(timeIntervalSince1970: 1_731_000_000)
        let page = (0..<60).map { offset in
            makeItem(id: "p\(offset)", date: baseline.addingTimeInterval(TimeInterval(-offset)))
        }
        let saved = makeItem(id: "saved", date: baseline.addingTimeInterval(-10_000))

        let result = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: saved,
            matchesFilter: true,
            items: page,
            hasMore: true,
            pageSize: 60,
            fetchOffset: 60
        )

        XCTAssertFalse(result.didUpdateList)
        XCTAssertEqual(result.fetchOffset, 60)
        XCTAssertEqual(result.orderedIDs, page.map(\.id))
    }

    func testInsertRecentlySavedPhoto_WhenFilterMismatch_DoesNothing() {
        let baseline = Date(timeIntervalSince1970: 1_732_000_000)
        let existing = [
            makeItem(id: "a", date: baseline.addingTimeInterval(-10)),
            makeItem(id: "b", date: baseline.addingTimeInterval(-20))
        ]
        let saved = makeItem(id: "saved", date: baseline)

        let result = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: saved,
            matchesFilter: false,
            items: existing,
            hasMore: false,
            pageSize: 60,
            fetchOffset: 2
        )

        XCTAssertFalse(result.didUpdateList)
        XCTAssertEqual(result.fetchOffset, 2)
        XCTAssertEqual(result.orderedIDs, existing.map(\.id))
    }

    func testInsertRecentlySavedPhoto_WhenExistingSameID_ReplacesNotDuplicates() {
        let baseline = Date(timeIntervalSince1970: 1_733_000_000)
        let existing = [
            makeItem(id: "peer", date: baseline.addingTimeInterval(-60)),
            makeItem(id: "target", date: baseline.addingTimeInterval(-120))
        ]
        let saved = makeItem(id: "target", date: baseline)

        let result = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: saved,
            matchesFilter: true,
            items: existing,
            hasMore: false,
            pageSize: 60,
            fetchOffset: 2
        )

        XCTAssertTrue(result.didUpdateList)
        XCTAssertEqual(result.orderedIDs.first, "target")
        XCTAssertEqual(result.orderedIDs.filter { $0 == "target" }.count, 1)
    }

    func testPhotoFeedMergePlanner_WhenPendingAndPersistedHaveSameID_Deduplicates() {
        let baseline = Date(timeIntervalSince1970: 1_734_000_000)
        let ordered = PhotoFeedMergePlanner.orderedIDs(
            persisted: [
                PhotoFeedMergeItem(id: "A", date: baseline.addingTimeInterval(-10)),
                PhotoFeedMergeItem(id: "B", date: baseline.addingTimeInterval(-20))
            ],
            pending: [
                PhotoFeedMergeItem(id: "A", date: baseline),
                PhotoFeedMergeItem(id: "C", date: baseline.addingTimeInterval(-5))
            ]
        )

        XCTAssertEqual(ordered, ["A", "C", "B"])
    }

    func testPhotoFeedMergePlanner_OrdersByDateDescendingWithLimit() {
        let baseline = Date(timeIntervalSince1970: 1_734_500_000)
        let ordered = PhotoFeedMergePlanner.orderedIDs(
            persisted: [
                PhotoFeedMergeItem(id: "P1", date: baseline.addingTimeInterval(-40)),
                PhotoFeedMergeItem(id: "P2", date: baseline.addingTimeInterval(-15))
            ],
            pending: [
                PhotoFeedMergeItem(id: "Q1", date: baseline.addingTimeInterval(-5)),
                PhotoFeedMergeItem(id: "Q2", date: baseline.addingTimeInterval(-25))
            ],
            limit: 3
        )

        XCTAssertEqual(ordered, ["Q1", "P2", "Q2"])
    }
}

private extension SinglePhotoSaveMergeTests {
    func makeItem(id: String, date: Date) -> SinglePhotoSaveMergeItem {
        SinglePhotoSaveMergeItem(id: id, date: date)
    }
}
