/// Cel testow: Sprawdza walidacje objetosciowa modelu 3D i korekte podzialu tors/nogi.
/// Dlaczego to wazne: Walidacja jest jedynym niezaleznym sprawdzianem, czy sylwetka spina sie z waga.
/// Kryteria zaliczenia: Okraglosc masy, poprawne progi i korekta w dozwolonym zakresie.

import XCTest
import Foundation
@testable import MeasureMe

final class BodyVolumeValidatorTests: XCTestCase {

    private static func snapshot(weightKg: Double, bodyFat: Double = 18) -> BodySnapshot {
        BodySnapshot(
            gender: .male, age: 30,
            heightCm: 180, weightKg: weightKg, bodyFatPercent: bodyFat,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: 85, hipsCm: 98,
            bicepCm: 34, forearmCm: 28, thighCm: 58, calfCm: 38,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    /// Co sprawdza: OKRAGLOSC. Masa policzona z modelu, podana z powrotem jako waga, daje zerowa odchylke.
    /// Dlaczego: Wylapuje kazdy blad w lancuchu pole -> objetosc -> gestosc, bez zewnetrznych danych.
    /// Kryteria: Odchylka ponizej 0.5% i pasmo .good.
    func testRoundTripMassGivesZeroDeviation() {
        let probe = Self.snapshot(weightKg: 80)
        let parameters = BodyMeshSolver.solve(snapshot: probe, torsoShareScale: 1.0)
        let impliedMass = BodyVolumeValidator.volumeLitres(parameters)
            * BodyVolumeValidator.bodyDensity(bodyFatPercent: probe.bodyFatPercent)

        let consistent = Self.snapshot(weightKg: impliedMass)
        let (_, validation) = BodyVolumeValidator.reconcile(snapshot: consistent)

        XCTAssertEqual(validation.deviationFraction, 0, accuracy: 0.005)
        XCTAssertEqual(validation.band, .good)
    }

    /// Co sprawdza: Objetosc walca o znanych wymiarach zgadza sie z wartoscia analityczna.
    /// Dlaczego: Test okraglosci nie przypina wspolczynnikow — ta sama zla formula generuje
    ///           obie strony porownania. To jest bezwzgledna wyrocznia dla lancucha pole -> objetosc.
    /// Kryteria: Walec o promieniu 10 cm i wysokosci 100 cm ma objetosc pi*r^2*h / 1000 litra.
    func testVolumeOfAKnownCylinderMatchesTheAnalyticValue() {
        let radius = 10.0
        let circumference = 2 * Double.pi * radius
        let cylinder = [
            BodyCrossSection(y: 0, circumferenceCm: circumference, aspectRatio: 1, exponent: 2),
            BodyCrossSection(y: 100, circumferenceCm: circumference, aspectRatio: 1, exponent: 2)
        ]
        let parameters = BodyMeshParameters(torso: cylinder, arm: [], leg: [], heightCm: 100)

        let expectedLitres = Double.pi * radius * radius * 100 / 1000
        XCTAssertEqual(BodyVolumeValidator.volumeLitres(parameters), expectedLitres, accuracy: expectedLitres * 0.001)
    }

    /// Co sprawdza: Kazda konczyna liczy sie dwukrotnie, a zaden stos nie wypada z sumy.
    /// Dlaczego: Solver buduje jedno ramie i jedna noge, renderer je odbija. Zly mnoznik
    ///           albo pominiety stos przechodza przez test okraglosci niezauwazone.
    /// Kryteria: Ten sam walec jako ramie daje dwukrotnosc objetosci walca jako tors,
    ///           i tak samo jako noga.
    func testLimbStacksAreCountedTwice() {
        let circumference = 2 * Double.pi * 10.0
        let cylinder = [
            BodyCrossSection(y: 0, circumferenceCm: circumference, aspectRatio: 1, exponent: 2),
            BodyCrossSection(y: 100, circumferenceCm: circumference, aspectRatio: 1, exponent: 2)
        ]
        let single = BodyVolumeValidator.volumeLitres(
            BodyMeshParameters(torso: cylinder, arm: [], leg: [], heightCm: 100)
        )

        let asArm = BodyVolumeValidator.volumeLitres(
            BodyMeshParameters(torso: [], arm: cylinder, leg: [], heightCm: 100)
        )
        let asLeg = BodyVolumeValidator.volumeLitres(
            BodyMeshParameters(torso: [], arm: [], leg: cylinder, heightCm: 100)
        )

        XCTAssertEqual(asArm, single * 2, accuracy: single * 0.001)
        XCTAssertEqual(asLeg, single * 2, accuracy: single * 0.001)
    }

    /// Co sprawdza: Masa wynikajaca z realnych wymiarow miesci sie w prawdopodobnym pasmie.
    /// Dlaczego: Lapie pominiety stos albo zly mnoznik na realnym ciele, a nie na walcu.
    /// Kryteria: Dla mezczyzny 180 cm o typowych obwodach implikowana masa lezy w 55-105 kg.
    func testImpliedMassOfARealisticBodyIsPlausible() {
        let snapshot = Self.snapshot(weightKg: 80)
        let parameters = BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)
        let impliedMass = BodyVolumeValidator.volumeLitres(parameters)
            * BodyVolumeValidator.bodyDensity(bodyFatPercent: snapshot.bodyFatPercent)

        XCTAssertGreaterThan(impliedMass, 55)
        XCTAssertLessThan(impliedMass, 105)
    }

    /// Co sprawdza: Objetosc skaluje sie z szescianem skali liniowej.
    /// Dlaczego: To wymiarowy niezmiennik geometrii; lamie sie przy pomyleniu jednostek.
    /// Kryteria: Podwojenie wszystkich dlugosci daje osmiokrotna objetosc.
    func testVolumeScalesWithCubeOfLinearScale() {
        let base = BodyMeshSolver.solve(snapshot: Self.snapshot(weightKg: 80), torsoShareScale: 1.0)
        let doubled = BodyMeshParameters(
            torso: base.torso.map { BodyCrossSection(y: $0.y * 2, circumferenceCm: $0.circumferenceCm * 2, aspectRatio: $0.aspectRatio, exponent: $0.exponent) },
            arm: base.arm.map { BodyCrossSection(y: $0.y * 2, circumferenceCm: $0.circumferenceCm * 2, aspectRatio: $0.aspectRatio, exponent: $0.exponent) },
            leg: base.leg.map { BodyCrossSection(y: $0.y * 2, circumferenceCm: $0.circumferenceCm * 2, aspectRatio: $0.aspectRatio, exponent: $0.exponent) },
            heightCm: base.heightCm * 2
        )
        XCTAssertEqual(
            BodyVolumeValidator.volumeLitres(doubled),
            BodyVolumeValidator.volumeLitres(base) * 8,
            accuracy: BodyVolumeValidator.volumeLitres(base) * 0.01
        )
    }

    /// Co sprawdza: Wiekszy procent tkanki tluszczowej obniza gestosc ciala.
    /// Dlaczego: Model dwuskladnikowy Siriego jest podstawa przeliczenia objetosci na mase.
    /// Kryteria: Gestosc maleje monotonicznie i miesci sie miedzy gestoscia tluszczu a beztluszczowej.
    func testDensityFallsAsBodyFatRises() {
        let densities = [5.0, 15.0, 25.0, 40.0].map(BodyVolumeValidator.bodyDensity(bodyFatPercent:))
        XCTAssertEqual(densities, densities.sorted(by: >))
        XCTAssertLessThan(densities.last!, 1.1)
        XCTAssertGreaterThan(densities.first!, 0.9)
    }

    /// Co sprawdza: Wieksza waga przy tych samych obwodach jest kompensowana dluzszym torsem.
    /// Dlaczego: To zadeklarowany mechanizm korekty; obwody musza zostac nietkniete.
    /// Kryteria: Skala torsu rosnie, a zmierzone obwody nadal sie zgadzaja.
    func testHeavierWeightPushesTorsoShareUpWithoutTouchingCircumferences() {
        let light = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: 72))
        let heavy = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: 88))

        XCTAssertGreaterThan(heavy.validation.torsoShareScale, light.validation.torsoShareScale)

        let waistY = 180 * BodyProportions.heightFraction(.waist, gender: .male)
        for result in [light, heavy] {
            let waistSection = result.parameters.torso.min { abs($0.y - waistY) < abs($1.y - waistY) }
            XCTAssertNotNil(waistSection)
        }
        // Circumferences survive the correction regardless of how far it moved.
        for result in [light, heavy] {
            XCTAssertTrue(result.parameters.torso.contains { abs($0.circumferenceCm - 85) < 0.05 })
            XCTAssertTrue(result.parameters.torso.contains { abs($0.circumferenceCm - 98) < 0.05 })
        }
    }

    /// Co sprawdza: Korekta nigdy nie wychodzi poza dozwolone +/-6%.
    /// Dlaczego: Poza tym zakresem model ma raportowac rozjazd, a nie dopasowywac na sile.
    /// Kryteria: Skala miesci sie w torsoShareRange nawet dla absurdalnej wagi.
    func testCorrectionStaysWithinAllowedRange() {
        for weight in [40.0, 60.0, 80.0, 120.0, 200.0] {
            let (_, validation) = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: weight))
            XCTAssertTrue(
                BodyProportions.torsoShareRange.contains(validation.torsoShareScale),
                "Scale escaped the allowed range at \(weight) kg"
            )
        }
    }

    /// Co sprawdza: Absurdalna waga trafia do pasma .suspect, ale przy podrecznikowych
    ///           obwodach zaden pojedynczy pomiar nie tlumaczy rozjazdu.
    /// Dlaczego: Wskazanie konkretnej strony bez przekroczonego progu kierowaloby
    ///           uzytkownika do przemierzenia dobrej taśmy zamiast poprawienia wagi.
    /// Kryteria: Pasmo to .suspect, a suspectSite jest nil, bo zaden obwod nie
    ///           przekracza progu 0.15.
    func testWildlyInconsistentWeightWithTextbookMeasurementsHasNoSuspectSite() {
        let (_, validation) = BodyVolumeValidator.reconcile(snapshot: Self.snapshot(weightKg: 200))
        XCTAssertEqual(validation.band, .suspect)
        XCTAssertNil(validation.suspectSite)
    }

    /// Co sprawdza: Progi pasm odpowiadaja specyfikacji.
    /// Dlaczego: Progi steruja tym, co widzi uzytkownik.
    /// Kryteria: 5% to .good, 12% to .approximate, powyzej to .suspect.
    func testBandThresholdsMatchSpec() {
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.049), .good)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.05), .good)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.08), .approximate)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.12), .approximate)
        XCTAssertEqual(BodyValidationBand(deviationFraction: 0.13), .suspect)
    }
}
