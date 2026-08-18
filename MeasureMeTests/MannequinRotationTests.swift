import XCTest
@testable import MeasureMe

/// Cel testow: matematyka obrotu manekina.
/// Dlaczego to wazne: zapis do @State w niezainstalowanym widoku przepada, wiec
/// test sterujacy gestem przechodzilby na pusto. Decyzja siedzi w czystej funkcji.
final class MannequinRotationTests: XCTestCase {
    /// Dlaczego: to jest ten blad. Kat liczony wprost z translacji wracal do zera
    /// przy kazdym nowym dotknieciu, co czyta sie jako "nie da sie obracac".
    func testASecondDragContinuesFromWhereTheFirstStopped() {
        let first = MannequinRotation.angle(committed: 0, dragWidth: 90)
        XCTAssertEqual(first, 1, accuracy: 1e-9)

        let second = MannequinRotation.angle(committed: first, dragWidth: 90)
        XCTAssertEqual(second, 2, accuracy: 1e-9)
    }

    func testDraggingBackUndoesTheTurn() {
        XCTAssertEqual(MannequinRotation.angle(committed: 1, dragWidth: -90), 0, accuracy: 1e-9)
    }

    func testNormalisingKeepsTheAngleInOneTurn() {
        for angle in [0.0, 1.0, 7.0, -1.0, -100.0, 1000.0] {
            let wrapped = MannequinRotation.normalised(angle)
            XCTAssertGreaterThanOrEqual(wrapped, 0, "\(angle)")
            XCTAssertLessThan(wrapped, 2 * Double.pi, "\(angle)")
            let turns = (angle - wrapped) / (2 * Double.pi)
            XCTAssertEqual(turns, turns.rounded(), accuracy: 1e-9, "\(angle) musi rozniс sie o pelne obroty")
        }
    }
}
