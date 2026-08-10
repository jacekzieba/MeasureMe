/// Cel testow: Sprawdza geometrie przekroju superelipsy uzywana przez model 3D sylwetki.
/// Dlaczego to wazne: Pole przekroju wchodzi do objetosci, a dopasowanie obwodu do solvera.
/// Kryteria zaliczenia: Przypadki okregu i elipsy zgadzaja sie z wzorami analitycznymi.

import XCTest
import Foundation
@testable import MeasureMe

final class SuperellipseTests: XCTestCase {

    /// Co sprawdza: Dla n=2 i aspect=1 superelipsa jest okregiem.
    /// Dlaczego: To jedyna wyrocznia niezalezna od implementacji.
    /// Kryteria: Pole i obwod zgadzaja sie ze wzorami okregu.
    func testCircleCaseMatchesAnalyticFormulas() {
        let circle = Superellipse(semiAxisA: 5, semiAxisB: 5, exponent: 2)
        XCTAssertEqual(circle.area, Double.pi * 25, accuracy: 1e-6)
        XCTAssertEqual(circle.perimeter, 2 * Double.pi * 5, accuracy: 1e-4)
    }

    /// Co sprawdza: Dla n=2 pole elipsy to pi*a*b.
    /// Dlaczego: Weryfikuje czlon gamma we wzorze na pole.
    /// Kryteria: Pole zgadza sie ze wzorem elipsy.
    func testEllipseAreaMatchesAnalyticFormula() {
        let ellipse = Superellipse(semiAxisA: 8, semiAxisB: 4, exponent: 2)
        XCTAssertEqual(ellipse.area, Double.pi * 8 * 4, accuracy: 1e-6)
    }

    /// Co sprawdza: fitting() odtwarza zadany obwod.
    /// Dlaczego: To kontrakt uzywany przez solver dla kazdego pomiaru uzytkownika.
    /// Kryteria: Obwod dopasowanego ksztaltu rowna sie zadanemu ponizej 0.05 mm.
    func testFittingReproducesRequestedCircumference() {
        for aspect in [1.0, 0.72, 0.55] {
            for exponent in [2.0, 2.3, 2.6] {
                let shape = Superellipse.fitting(
                    circumference: 94.0,
                    aspectRatio: aspect,
                    exponent: exponent
                )
                XCTAssertEqual(shape.perimeter, 94.0, accuracy: 0.005)
                XCTAssertEqual(shape.semiAxisB / shape.semiAxisA, aspect, accuracy: 1e-9)
            }
        }
    }

    /// Co sprawdza: Przy stalych polosiach wyzszy wykladnik daje wieksze pole.
    /// Dlaczego: Weryfikuje kierunek czlonu gamma — ksztalt dazy do prostokata 4ab, a nie do elipsy pi*ab.
    /// Kryteria: Pole rosnie monotonicznie z wykladnikiem i zmierza do 4ab.
    func testAreaGrowsWithExponentAtFixedSemiAxes() {
        let areas = [2.0, 2.3, 2.6, 3.0, 8.0].map {
            Superellipse(semiAxisA: 8, semiAxisB: 6, exponent: $0).area
        }
        XCTAssertEqual(areas, areas.sorted())
        XCTAssertLessThan(areas.last!, 4 * 8 * 6)
    }

    /// Co sprawdza: Przy stalym obwodzie wyzszy wykladnik daje MNIEJSZE pole.
    /// Dlaczego: To nierownosc izoperymetryczna — okrag maksymalizuje pole dla danego obwodu,
    ///           wiec ksztalt bardziej pudelkowaty mniej go obejmuje. Solver trzyma staly obwod,
    ///           wiec to jest kierunek, ktory realnie widzi model objetosciowy.
    /// Kryteria: Pole maleje monotonicznie z wykladnikiem.
    func testAreaFallsWithExponentAtFixedCircumference() {
        let areas = [2.0, 2.3, 2.6, 3.0].map {
            Superellipse.fitting(circumference: 80, aspectRatio: 0.75, exponent: $0).area
        }
        XCTAssertEqual(areas, areas.sorted(by: >))
    }
}
