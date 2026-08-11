/// Cel testu: Weryfikuje wybór zdjęcia-overlaya dla każdej pozy oraz poziomy krycia overlaya w aparacie.
/// Dlaczego to ważne: Overlay pokazywał zawsze najnowsze zdjęcie niezależnie od pozy — ta logika
/// decyduje, że użytkownik widzi ghost właściwej pozy albo nie widzi żadnego.
/// Kryteria zaliczenia: Najnowsze zdjęcie wygrywa w obrębie pozy, tagi niepozowe są ignorowane,
/// a poziomy krycia mapują się na 12/22/35% z bezpiecznym fallbackiem.

@testable import MeasureMe

import XCTest

final class PhotoOverlayCandidatesTests: XCTestCase {

    private func makePhoto(
        marker: UInt8,
        daysAgo: Int,
        tags: [PhotoTag]
    ) -> PhotoEntry {
        PhotoEntry(
            imageData: Data([marker]),
            date: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(-Double(daysAgo) * 86_400),
            tags: tags
        )
    }

    func testMostRecentByPose_emptyInput_returnsEmpty() {
        XCTAssertTrue(PhotoOverlayCandidates.mostRecentByPose(in: []).isEmpty)
    }

    func testMostRecentByPose_newestPhotoWinsWithinPose() {
        // Kolejność malejąca po dacie, tak jak @Query w PhotoView.
        let photos = [
            makePhoto(marker: 1, daysAgo: 1, tags: [.back]),
            makePhoto(marker: 2, daysAgo: 5, tags: [.back]),
            makePhoto(marker: 3, daysAgo: 9, tags: [.front]),
        ]

        let candidates = PhotoOverlayCandidates.mostRecentByPose(in: photos)

        XCTAssertEqual(candidates[.back], Data([1]))
        XCTAssertEqual(candidates[.front], Data([3]))
        XCTAssertNil(candidates[.side])
        XCTAssertNil(candidates[.detail])
    }

    func testMostRecentByPose_photoWithSeveralPosesFillsEachOfThem() {
        let photos = [makePhoto(marker: 7, daysAgo: 0, tags: [.front, .side])]

        let candidates = PhotoOverlayCandidates.mostRecentByPose(in: photos)

        XCTAssertEqual(candidates[.front], Data([7]))
        XCTAssertEqual(candidates[.side], Data([7]))
    }

    func testMostRecentByPose_ignoresNonPrimaryPoseTags() {
        let photos = [makePhoto(marker: 4, daysAgo: 0, tags: [.waist, .wholeBody])]

        XCTAssertTrue(PhotoOverlayCandidates.mostRecentByPose(in: photos).isEmpty)
    }

    func testMostRecentByPose_prefersThumbnailOverFullImage() {
        let photo = PhotoEntry(
            imageData: Data([9, 9, 9]),
            thumbnailData: Data([1]),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [.front]
        )

        XCTAssertEqual(PhotoOverlayCandidates.mostRecentByPose(in: [photo])[.front], Data([1]))
    }

    func testOverlayOpacity_clampsToRange() {
        XCTAssertEqual(CameraOverlayOpacity.clamped(0.22), 0.22, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.clamped(0.05), 0.05, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.clamped(0.50), 0.50, accuracy: 0.0001)

        // Poniżej i powyżej zakresu — przycięcie do krańców, nie do wartości domyślnej.
        XCTAssertEqual(CameraOverlayOpacity.clamped(0.0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.clamped(-3.0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.clamped(1.0), 0.50, accuracy: 0.0001)
    }

    func testOverlayOpacity_nonFiniteFallsBackToDefault() {
        XCTAssertEqual(CameraOverlayOpacity.clamped(.nan), 0.22, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.clamped(.infinity), 0.22, accuracy: 0.0001)
        XCTAssertEqual(CameraOverlayOpacity.clamped(-.infinity), 0.22, accuracy: 0.0001)
    }

    func testOverlayOpacity_percentLabelRoundsAndClamps() {
        XCTAssertEqual(CameraOverlayOpacity.percentLabel(for: 0.22), "22%")
        XCTAssertEqual(CameraOverlayOpacity.percentLabel(for: 0.05), "5%")
        XCTAssertEqual(CameraOverlayOpacity.percentLabel(for: 0.504), "50%")
        XCTAssertEqual(CameraOverlayOpacity.percentLabel(for: 0.2249), "22%")
        XCTAssertEqual(CameraOverlayOpacity.percentLabel(for: .nan), "22%")
    }
}
