/// Cel testu: Weryfikuje decyzję o prezentacji ekranu porównania — natychmiast albo po zamknięciu
/// poprzedniego sheeta.
/// Dlaczego to ważne: Compare bywał otwierany dopiero za drugim naciśnięciem, bo stan był zapisywany
/// w dwóch osobnych cyklach aktualizacji. Ta logika zastępuje tamten wyścig.
/// Kryteria zaliczenia: Żądanie spoza sheeta aktywuje od razu, żądanie z sheeta czeka na dismiss,
/// a każde żądanie tworzy nową tożsamość prezentacji.

@testable import MeasureMe

import XCTest

final class ComparePresentationStateTests: XCTestCase {

    private func makePair() -> PhotoComparePair {
        let older = PhotoEntry(
            imageData: Data([1]),
            date: Date(timeIntervalSince1970: 1_600_000_000),
            tags: [.front]
        )
        let newer = PhotoEntry(
            imageData: Data([2]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [.front]
        )
        return PhotoComparePair(olderPhoto: older, newerPhoto: newer)
    }

    func testDirectRequestActivatesImmediately() {
        var state = ComparePresentationState()
        let pair = makePair()

        state.request(pair, presentedFromSheet: false)

        XCTAssertEqual(state.active?.id, pair.id)
        XCTAssertNil(state.pending)
    }

    func testSheetSourcedRequestOnlyParksPending() {
        var state = ComparePresentationState()
        let pair = makePair()

        state.request(pair, presentedFromSheet: true)

        XCTAssertNil(state.active)
        XCTAssertEqual(state.pending?.id, pair.id)
    }

    func testSheetDismissedPromotesPending() {
        var state = ComparePresentationState()
        let pair = makePair()
        state.request(pair, presentedFromSheet: true)

        state.sheetDismissed()

        XCTAssertEqual(state.active?.id, pair.id)
        XCTAssertNil(state.pending)
    }

    func testSheetDismissedWithoutPendingIsNoOp() {
        var state = ComparePresentationState()

        state.sheetDismissed()

        XCTAssertNil(state.active)
        XCTAssertNil(state.pending)
    }

    func testSheetDismissedDoesNotClobberAnActivePair() {
        var state = ComparePresentationState()
        let pair = makePair()
        state.request(pair, presentedFromSheet: false)

        state.sheetDismissed()

        XCTAssertEqual(state.active?.id, pair.id)
    }

    func testActiveDismissedClearsActive() {
        var state = ComparePresentationState()
        state.request(makePair(), presentedFromSheet: false)

        state.activeDismissed()

        XCTAssertNil(state.active)
    }

    func testRepeatedRequestForTheSamePhotosProducesANewIdentity() {
        var state = ComparePresentationState()
        let older = PhotoEntry(
            imageData: Data([1]),
            date: Date(timeIntervalSince1970: 1_600_000_000),
            tags: [.front]
        )
        let newer = PhotoEntry(
            imageData: Data([2]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [.front]
        )

        state.request(PhotoComparePair(olderPhoto: older, newerPhoto: newer), presentedFromSheet: false)
        let firstID = state.active?.id
        state.activeDismissed()
        state.request(PhotoComparePair(olderPhoto: older, newerPhoto: newer), presentedFromSheet: false)

        XCTAssertNotNil(firstID)
        XCTAssertNotEqual(firstID, state.active?.id)
    }
}
