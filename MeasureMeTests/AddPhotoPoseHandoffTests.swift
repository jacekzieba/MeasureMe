/// Cel testu: Weryfikuje czystą logikę decyzyjną `AddPhotoView.poseApplication` w obu kierunkach — poza
/// wybrana ręcznie zostaje zachowana, poza zostaje podmieniona sugestią, gdy użytkownik jej nie wybrał —
/// oraz że konstruktor AddPhotoView poprawnie zasiewa selectedTags/didUserChoosePose z
/// initialTags/poseIsUserChosen.
/// Dlaczego to ważne: Użytkownik deklaruje pozę przed zdjęciem (steruje nią overlay); automat nie może
/// tej decyzji cofnąć w formularzu dodawania zdjęcia.
/// Kryteria zaliczenia: AddPhotoView.poseApplication zwraca nil, gdy didUserChoosePose == true (tagi się
/// nie zmieniają), a nowy zbiór tagów z zasugerowaną pozą, gdy użytkownik jej nie wybrał. Dodatkowo
/// konstruktor AddPhotoView poprawnie zasiewa selectedTags/didUserChoosePose z initialTags/poseIsUserChosen.
///
/// Uwaga: Te testy NIE wywołują `PhotoPoseClassifier` — makeSolidImage() istnieje wyłącznie po to, by
/// zasilić inicjalizator AddPhotoView obrazem podglądu; sama klasyfikacja obrazu nie jest tu weryfikowana.
/// Uwaga: @State w SwiftUI nie utrwala mutacji dokonanych poza zainstalowanym drzewem renderowania —
/// zweryfikowane empirycznie (nawet inkrementacja pojedynczego Int nie przetrwała odczytu na widoku
/// skonstruowanym wprost w teście). Dlatego logikę decyzyjną z `applySuggestedPose` wydzielono do czystej,
/// statycznej funkcji `poseApplication`, którą testujemy bezpośrednio, zamiast obserwować mutację @State.

@testable import MeasureMe

import XCTest
import SwiftUI

@MainActor
final class AddPhotoPoseHandoffTests: XCTestCase {

    private func makeSolidImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testUserChosenPoseSurvivesTheClassifier() {
        let view = AddPhotoView(
            previewImage: makeSolidImage(),
            initialTags: [.back],
            poseIsUserChosen: true
        )
        XCTAssertTrue(view.didUserChoosePose)
        XCTAssertEqual(view.selectedTags, [.back])

        let result = AddPhotoView.poseApplication(
            currentTags: view.selectedTags,
            suggestedPose: .side,
            didUserChoosePose: view.didUserChoosePose
        )

        XCTAssertNil(result)
    }

    func testSuggestedPoseReplacesTheTagWhenTheUserDidNotChoose() {
        let view = AddPhotoView(previewImage: makeSolidImage(), initialTags: [.back])
        XCTAssertFalse(view.didUserChoosePose)
        XCTAssertEqual(view.selectedTags, [.back])

        let result = AddPhotoView.poseApplication(
            currentTags: view.selectedTags,
            suggestedPose: .side,
            didUserChoosePose: view.didUserChoosePose
        )

        XCTAssertEqual(result, [.side])
    }
}
