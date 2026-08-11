/// Cel testow: Sprawdza solver zamieniajacy pomiary na przekroje sylwetki.
/// Dlaczego to wazne: Jesli solver nie odtwarza zmierzonych obwodow, model klamie o danych uzytkownika.
/// Kryteria zaliczenia: Obwody na poziomach kotwiczacych zgadzaja sie ponizej 0.5 mm, a sylwetka nie faluje.

import XCTest
import Foundation
@testable import MeasureMe

final class BodyMeshSolverTests: XCTestCase {

    private static func maleSnapshot(waist: Double = 85, hips: Double = 98) -> BodySnapshot {
        BodySnapshot(
            gender: .male, age: 30,
            heightCm: 180, weightKg: 80, bodyFatPercent: 18,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: waist, hipsCm: hips,
            bicepCm: 34, forearmCm: 28, thighCm: 58, calfCm: 38,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    /// Znajduje przekroj najblizszy zadanej wysokosci.
    private func section(
        of sections: [BodyCrossSection],
        nearestTo y: Double
    ) -> BodyCrossSection {
        sections.min { abs($0.y - y) < abs($1.y - y) }!
    }

    /// Co sprawdza: NIEZMIENNIK. Obwod na kazdym poziomie kotwiczacym rowna sie zmierzonemu.
    /// Dlaczego: To jedyna gwarancja, ze sylwetka reprezentuje dane uzytkownika, a nie srednia populacji.
    /// Kryteria: Roznica ponizej 0.05 cm dla kazdej kotwicy.
    func testSolverReproducesMeasuredCircumferencesAtAnchors() {
        let snapshot = Self.maleSnapshot()
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let expected: [(BodyLandmark, Double)] = [
            (.neck, snapshot.neckCm),
            (.shoulder, snapshot.shouldersCm),
            (.chest, snapshot.chestCm),
            (.waist, snapshot.waistCm),
            (.hip, snapshot.hipsCm)
        ]

        for (landmark, measured) in expected {
            let y = snapshot.heightCm * BodyProportions.heightFraction(landmark, gender: .male)
            let found = section(of: solved.torso, nearestTo: y)
            XCTAssertEqual(found.y, y, accuracy: 1e-6, "\(landmark) level misplaced")
            XCTAssertEqual(
                found.circumferenceCm, measured, accuracy: 0.05,
                "\(landmark) circumference drifted from the measurement"
            )
        }
    }

    /// Co sprawdza: Obwod odtwarza sie takze po przejsciu przez geometrie superelipsy.
    /// Dlaczego: Solver zapisuje obwod, ale renderowany jest ksztalt; oba musza sie zgadzac.
    /// Kryteria: Obwod dopasowanego ksztaltu rowna sie zapisanemu ponizej 0.05 cm.
    func testFittedShapePerimeterMatchesStoredCircumference() {
        let solved = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: 1.0)
        for section in solved.torso {
            XCTAssertEqual(section.shape.perimeter, section.circumferenceCm, accuracy: 0.05)
        }
    }

    /// Co sprawdza: Miedzy talia a biodrami obwod zmienia sie monotonicznie.
    /// Dlaczego: Splajn kubiczny zrobilby tam fale; spec wymaga interpolacji monotonicznej.
    /// Kryteria: Przy talii wezszej od bioder obwod maleje monotonicznie od bioder w gore do talii.
    func testTorsoDoesNotOscillateBetweenWaistAndHips() {
        let snapshot = Self.maleSnapshot(waist: 80, hips: 100)
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let hipY = snapshot.heightCm * BodyProportions.heightFraction(.hip, gender: .male)
        let waistY = snapshot.heightCm * BodyProportions.heightFraction(.waist, gender: .male)

        let between = solved.torso
            .filter { $0.y >= hipY - 1e-9 && $0.y <= waistY + 1e-9 }
            .sorted { $0.y < $1.y }
            .map(\.circumferenceCm)

        XCTAssertEqual(between, between.sorted(by: >), "Circumference should fall monotonically from hips to waist")
    }

    /// Co sprawdza: Skalowanie podzialu tors/nogi przesuwa landmarki, ale nie zmienia wzrostu.
    /// Dlaczego: Wzrost jest zmierzony; korekta objetosci nie ma prawa go ruszyc.
    /// Kryteria: Najwyzszy przekroj lezy na wysokosci uzytkownika dla obu skal.
    func testTorsoShareScaleKeepsTotalHeight() {
        for scale in [0.94, 1.0, 1.06] {
            let solved = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: scale)
            XCTAssertEqual(solved.torso.map(\.y).max() ?? 0, 180, accuracy: 1e-6)
            XCTAssertEqual(solved.heightCm, 180, accuracy: 1e-9)
        }
    }

    /// Co sprawdza: Wieksza skala torsu daje dluzszy tors i krotsze nogi.
    /// Dlaczego: To mechanizm, ktorym walidator dopina objetosc do wagi.
    /// Kryteria: Krocze schodzi nizej przy wiekszej skali.
    func testLargerTorsoShareLowersTheCrotch() {
        let small = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: 0.94)
        let large = BodyMeshSolver.solve(snapshot: Self.maleSnapshot(), torsoShareScale: 1.06)
        XCTAssertLessThan(large.torso.map(\.y).min() ?? 0, small.torso.map(\.y).min() ?? 0)
    }

    /// Co sprawdza: NIEZMIENNIK NOGI. Zmierzony obwod lydki trafia do siatki dokladnie.
    /// Dlaczego: Lydka jest metryka wymagana od uzytkownika; gdyby sluzyla tylko jako mnoznik,
    ///           kazalibysmy mierzyc cos, czego nie pokazujemy.
    /// Kryteria: Przekroj na wysokosci lydki ma obwod rowny zmierzonemu ponizej 0.05 cm.
    func testSolverReproducesMeasuredCalfCircumference() {
        let snapshot = Self.maleSnapshot()
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let y = snapshot.heightCm * BodyProportions.heightFraction(.calf, gender: .male)
        let found = section(of: solved.leg, nearestTo: y)
        XCTAssertEqual(found.y, y, accuracy: 1e-6)
        XCTAssertEqual(found.circumferenceCm, snapshot.calfCm, accuracy: 0.05)
    }

    /// Co sprawdza: Noga ma realne wybrzuszenie lydki, a nie monotoniczny stozek.
    /// Dlaczego: To wizualny sens dodania landmarku .calf; bez tego lydka nadal by nie istniala.
    /// Kryteria: Obwod na wysokosci lydki jest wiekszy niz na wysokosci kolana.
    func testLegHasACalfBulgeRatherThanATaper() {
        let snapshot = Self.maleSnapshot()
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)

        let calfY = snapshot.heightCm * BodyProportions.heightFraction(.calf, gender: .male)
        let kneeY = snapshot.heightCm * BodyProportions.heightFraction(.knee, gender: .male)

        XCTAssertGreaterThan(
            section(of: solved.leg, nearestTo: calfY).circumferenceCm,
            section(of: solved.leg, nearestTo: kneeY).circumferenceCm
        )
    }

    /// Co sprawdza: Niezmiennik obwodow trzyma sie takze przy skorygowanym podziale tors/nogi.
    /// Dlaczego: Walidacja objetosciowa bedzie ta skale zmieniac; pomiar nie moze od niej zalezec.
    /// Kryteria: Talia i biodra odtwarzaja sie dla obu krancow torsoShareRange.
    func testAnchorCircumferencesSurviveTorsoShareCorrection() {
        let snapshot = Self.maleSnapshot()
        for scale in [BodyProportions.torsoShareRange.lowerBound,
                      BodyProportions.torsoShareRange.upperBound] {
            let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: scale)
            XCTAssertTrue(
                solved.torso.contains { abs($0.circumferenceCm - snapshot.waistCm) < 0.05 },
                "Waist lost at scale \(scale)"
            )
            XCTAssertTrue(
                solved.torso.contains { abs($0.circumferenceCm - snapshot.hipsCm) < 0.05 },
                "Hips lost at scale \(scale)"
            )
        }
    }

    /// Co sprawdza: Stos ramienia zaczyna sie ponizej plyty barkow.
    /// Dlaczego: Obwod barkow z definicji obejmuje juz ramiona, wiec doliczanie ich drugi raz
    ///           w tej samej plycie liczy te sama tkanke dwukrotnie i zawyza objetosc.
    /// Kryteria: Najwyzszy przekroj ramienia lezy nie wyzej niz poziom klatki.
    func testArmStackStartsBelowTheShoulderSlab() {
        let snapshot = Self.maleSnapshot()
        for scale in [BodyProportions.torsoShareRange.lowerBound, 1.0,
                      BodyProportions.torsoShareRange.upperBound] {
            let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: scale)
            let armTop = solved.arm.map(\.y).max() ?? 0
            // torsoShareScale remaps every above-crotch height, the chest anchor
            // included, so the comparison must use the solved chest level, not
            // the unscaled height fraction, or it drifts at the range extremes.
            let chestSection = solved.torso.first { abs($0.circumferenceCm - snapshot.chestCm) < 0.05 }
            XCTAssertNotNil(chestSection, "Chest anchor missing at scale \(scale)")
            XCTAssertLessThanOrEqual(
                armTop, (chestSection?.y ?? .infinity) + 1e-6,
                "Arm reaches into the shoulder slab at scale \(scale)"
            )
        }
    }

    /// Co sprawdza: Dla kobiet obwod biustu trafia na poziom klatki.
    /// Dlaczego: U kobiet bust zastepuje chest jako obwod definiujacy gorna partie.
    /// Kryteria: Przekroj na wysokosci klatki ma obwod rowny bustowi.
    func testFemaleUsesBustAtChestLevel() {
        let snapshot = BodySnapshot(
            gender: .female, age: 30,
            heightCm: 168, weightKg: 62, bodyFatPercent: 26,
            neckCm: 32, shouldersCm: 104, chestCm: 84, bustCm: 92,
            waistCm: 70, hipsCm: 96,
            bicepCm: 27, forearmCm: 23, thighCm: 54, calfCm: 35,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
        let solved = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)
        let y = 168 * BodyProportions.heightFraction(.chest, gender: .female)
        XCTAssertEqual(section(of: solved.torso, nearestTo: y).circumferenceCm, 92, accuracy: 0.05)
    }
}
