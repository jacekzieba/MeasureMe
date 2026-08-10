/// Cel testu: Weryfikuje, że poza wybrana ręcznie w aparacie nie jest nadpisywana przez klasyfikator pozy.
/// Dlaczego to ważne: Użytkownik deklaruje pozę przed zdjęciem (steruje nią overlay); automat nie może
/// tej decyzji cofnąć w formularzu dodawania zdjęcia.
/// Kryteria zaliczenia: Z poseIsUserChosen == true tagi po applySuggestedPoseIfNeeded się nie zmieniają,
/// a bez tej flagi klasyfikator może je podmienić.

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

    func testUserChosenPoseSurvivesTheClassifier() async {
        let view = AddPhotoView(
            previewImage: makeSolidImage(),
            initialTags: [.back],
            poseIsUserChosen: true
        )

        await view.applySuggestedPoseIfNeeded(from: makeSolidImage())

        XCTAssertEqual(view.selectedTags, [.back])
    }

    func testDefaultConstructionLeavesTheClassifierEnabled() {
        let view = AddPhotoView(previewImage: makeSolidImage(), initialTags: [.back])

        XCTAssertFalse(view.didUserChoosePose)
        XCTAssertEqual(view.selectedTags, [.back])
    }
}
