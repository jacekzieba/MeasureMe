import XCTest
import simd
@testable import MeasureMe

final class ConvexHullTests: XCTestCase {
    private let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]

    func testPerimeterOfAUnitSquareIsFour() {
        XCTAssertEqual(ConvexHull.perimeter(of: square), 4, accuracy: 1e-5)
    }

    /// Dlaczego: tasma krawiecka nie wchodzi do srodka — punkt wewnetrzny nie
    /// moze zmienic odczytu.
    func testInteriorPointsDoNotChangeThePerimeter() {
        XCTAssertEqual(ConvexHull.perimeter(of: square + [SIMD2(0.5, 0.5)]), 4, accuracy: 1e-5)
    }

    /// Dlaczego: to jest cala roznica miedzy obwodem otoczki a obwodem
    /// powierzchni — wciecie w plecach nie zwieksza obwodu talii.
    func testAConcaveOutlineMeasuresAsItsHull() {
        let concave: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0.5, 0.4), SIMD2(0, 1)
        ]
        XCTAssertEqual(ConvexHull.perimeter(of: concave), 4, accuracy: 1e-5)
    }

    /// Dlaczego: na tej wlasnosci stoi kryterium round-tripu. Skalowanie
    /// promieniowe wokol centroidu mnozy obwod otoczki DOKLADNIE przez ten sam
    /// wspolczynnik, wiec deformator trafia w cel bez iterowania.
    func testScalingAboutTheCentroidScalesThePerimeterExactly() {
        let points: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(3, 0), SIMD2(3, 2), SIMD2(0, 2)]
        let centre = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let scaled = points.map { centre + ($0 - centre) * 1.37 }
        XCTAssertEqual(
            ConvexHull.perimeter(of: scaled),
            ConvexHull.perimeter(of: points) * 1.37,
            accuracy: 1e-4
        )
    }

    func testDegenerateInputsDoNotCrash() {
        XCTAssertEqual(ConvexHull.perimeter(of: []), 0)
        XCTAssertEqual(ConvexHull.perimeter(of: [SIMD2(1, 1)]), 0)
        XCTAssertEqual(ConvexHull.perimeter(of: [SIMD2(0, 0), SIMD2(1, 0)]), 2, accuracy: 1e-5)
    }

    func testCollinearPointsCollapseToTheSpanThereAndBack() {
        let line: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(2, 0), SIMD2(3, 0)]
        XCTAssertEqual(ConvexHull.perimeter(of: line), 6, accuracy: 1e-5)
    }

    /// Dlaczego: przekroje ciala sa mniej wiecej okragle, wiec wielokat wpisany
    /// zaniza obwod. Ten test pilnuje, ze przy realnej liczbie wierzcholkow na
    /// pas blad jest pomijalny — wzor to okolo pi^2/(6n^2).
    func testAnInscribedPolygonUnderreadsACircleOnlySlightly() {
        for count in [9, 42] {
            let circle = (0..<count).map { index -> SIMD2<Float> in
                let angle = 2 * Float.pi * Float(index) / Float(count)
                return SIMD2(cos(angle), sin(angle))
            }
            let error = (2 * Float.pi - ConvexHull.perimeter(of: circle)) / (2 * Float.pi)
            XCTAssertLessThan(error, count == 9 ? 0.03 : 0.002, "n=\(count)")
        }
    }
}
