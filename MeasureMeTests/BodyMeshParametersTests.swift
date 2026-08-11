/// Cel testow: Sprawdza tablice proporcji i interpolacje parametrow siatki.
/// Dlaczego to wazne: Proporcje ustalaja pozycje pionowe, ktorych nie ma w pomiarach; interpolacja napedza morf.
/// Kryteria zaliczenia: Landmarki sa monotoniczne, a interpolacja jest liniowa i zachowuje krance.

import XCTest
import Foundation
@testable import MeasureMe

final class BodyMeshParametersTests: XCTestCase {

    /// Co sprawdza: Konwersja Gender -> BodyGender odrzuca .notSpecified.
    /// Dlaczego: To jest bramka "plec wymagana" ze specyfikacji, wyrazona typem zamiast sprawdzeniem w runtime.
    /// Kryteria: male i female mapuja sie, notSpecified daje nil.
    func testBodyGenderRejectsUnspecified() {
        XCTAssertEqual(BodyGender(.male), .male)
        XCTAssertEqual(BodyGender(.female), .female)
        XCTAssertNil(BodyGender(.notSpecified))
    }

    /// Co sprawdza: Landmarki rosna od kostki do czubka glowy dla obu plci.
    /// Dlaczego: Odwrocona kolejnosc dalaby siatke ze skrzyzowanymi przekrojami.
    /// Kryteria: Ulamki wzrostu sa scisle rosnace.
    func testLandmarkFractionsAreStrictlyIncreasing() {
        let order: [BodyLandmark] = [.ankle, .calf, .knee, .crotch, .hip, .waist, .chest, .shoulder, .neck, .crown]
        for gender in [BodyGender.male, .female] {
            let fractions = order.map { BodyProportions.heightFraction($0, gender: gender) }
            // sorted() would accept adjacent duplicates; landmarks must be
            // strictly apart or two cross-sections collapse onto one height.
            XCTAssertTrue(
                zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 },
                "Not strictly increasing for \(gender): \(fractions)"
            )
            XCTAssertEqual(fractions.last!, 1.0, accuracy: 1e-9)
        }
    }

    /// Co sprawdza: Interpolacja przy t=0 i t=1 zwraca dokladnie krance.
    /// Dlaczego: Morf musi trafiac w zmierzone stany, nie w ich przyblizenia.
    /// Kryteria: Wynik jest rowny wejsciu A dla t=0 i B dla t=1.
    func testInterpolationPreservesEndpoints() {
        let a = Self.parameters(circumference: 80, height: 175)
        let b = Self.parameters(circumference: 90, height: 175)

        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 0), a)
        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 1), b)
    }

    /// Co sprawdza: Obwod dla t w (0,1) lezy miedzy A i B.
    /// Dlaczego: To niezmiennik morfu ze specyfikacji.
    /// Kryteria: Kazdy poziom i kazde t spelniaja warunek zawierania.
    func testInterpolatedCircumferencesStayBetweenEndpoints() {
        let a = Self.parameters(circumference: 80, height: 175)
        let b = Self.parameters(circumference: 90, height: 175)

        for step in 0...10 {
            let t = Double(step) / 10
            let mid = BodyMeshParameters.interpolated(from: a, to: b, t: t)
            for (index, section) in mid.torso.enumerated() {
                let low = min(a.torso[index].circumferenceCm, b.torso[index].circumferenceCm)
                let high = max(a.torso[index].circumferenceCm, b.torso[index].circumferenceCm)
                XCTAssertGreaterThanOrEqual(section.circumferenceCm, low - 1e-9)
                XCTAssertLessThanOrEqual(section.circumferenceCm, high + 1e-9)
            }
        }
    }

    /// Co sprawdza: Krance sa dokladne takze dla wartosci, ktore nie sa okragle.
    /// Dlaczego: first + (second - first) * 1 nie jest bitowo rowne second w IEEE 754.
    ///           Fixture z okraglymi liczbami (80 -> 90) maskowal te zaleznosc, a realne
    ///           pomiary okragle nie sa. Test pilnuje kontraktu, nie reprodukuje konkretnego bledu.
    /// Kryteria: Dla obwodow 82.3 i 91.7 oraz wzrostu 174.7 oba krance sa identyczne z wejsciem.
    func testInterpolationEndpointsAreExactForAwkwardValues() {
        let a = Self.parameters(circumference: 82.3, height: 174.7)
        let b = Self.parameters(circumference: 91.7, height: 174.7)

        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 0), a)
        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 1), b)
    }

    /// Co sprawdza: t poza [0,1] jest przycinane.
    /// Dlaczego: Suwak i animacja moga chwilowo wyjsc poza zakres.
    /// Kryteria: t=-0.5 zachowuje sie jak 0, a t=1.5 jak 1.
    func testInterpolationClampsOutOfRangeT() {
        let a = Self.parameters(circumference: 80, height: 175)
        let b = Self.parameters(circumference: 90, height: 175)

        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: -0.5), a)
        XCTAssertEqual(BodyMeshParameters.interpolated(from: a, to: b, t: 1.5), b)
    }

    private static func parameters(circumference: Double, height: Double) -> BodyMeshParameters {
        let sections = (0..<20).map { index in
            BodyCrossSection(
                y: height * Double(index) / 19,
                circumferenceCm: circumference,
                aspectRatio: 0.75,
                exponent: 2.3
            )
        }
        return BodyMeshParameters(torso: sections, arm: sections, leg: sections, heightCm: height)
    }
}
