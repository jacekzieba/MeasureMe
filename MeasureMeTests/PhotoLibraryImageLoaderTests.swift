/// Cel testów: Weryfikuje logikę wyciągania daty tworzenia zdjęcia z PHAsset.
/// Dlaczego to ważne: Auto-fill daty w formularzu dodawania zdjęcia opiera się na tej funkcji —
/// błąd skutkowałby zawsze dzisiejszą datą zamiast rzeczywistej daty wykonania.
/// Kryteria zaliczenia: nil assetIdentifier → nil; nieznany identyfikator → nil.
///
/// UWAGA: Ścieżka "realny PHAsset z datą" jest niemożliwa w unit testach —
/// PHAsset.fetchAssets wymaga realnej biblioteki zdjęć. Pokryte testy sprawdzają
/// wszystkie gałęzie logiki, które nie wymagają fizycznego dostępu do biblioteki.

import XCTest
@testable import MeasureMe

final class PhotoLibraryImageLoaderTests: XCTestCase {

    // MARK: - Helpers

    private func makeSource(assetIdentifier: String?) -> PhotoLibraryImageSource {
        PhotoLibraryImageSource(
            id: UUID(),
            assetIdentifier: assetIdentifier,
            itemProvider: NSItemProvider(),
            selectionIndex: 0
        )
    }

    // MARK: - fetchCreationDate

    /// Co sprawdza: assetIdentifier == nil zwraca nil bez odpytywania PHAsset.
    /// Dlaczego: Zdjęcia z kamery nie mają identyfikatora — fallback na AppClock.now.
    /// Kryteria: Wynik to nil.
    func testFetchCreationDate_nilAssetIdentifier_returnsNil() {
        let source = makeSource(assetIdentifier: nil)
        XCTAssertNil(PhotoLibraryImageLoader.fetchCreationDate(from: source))
    }

    /// Co sprawdza: Nieznany identyfikator (nie pasuje do żadnego PHAsset) zwraca nil.
    /// Dlaczego: PHAsset.fetchAssets z nieznanym ID zwraca pusty wynik — funkcja musi
    ///           obsłużyć brak firstObject.
    /// Kryteria: Wynik to nil.
    func testFetchCreationDate_unknownAssetIdentifier_returnsNil() {
        let source = makeSource(assetIdentifier: UUID().uuidString)
        XCTAssertNil(PhotoLibraryImageLoader.fetchCreationDate(from: source))
    }

    /// Co sprawdza: Pusty string jako identyfikator zwraca nil.
    /// Dlaczego: Defensywne sprawdzenie na wypadek pustego stringa z PHPickerResult.
    /// Kryteria: Wynik to nil.
    func testFetchCreationDate_emptyAssetIdentifier_returnsNil() {
        let source = makeSource(assetIdentifier: "")
        XCTAssertNil(PhotoLibraryImageLoader.fetchCreationDate(from: source))
    }
}
