/// Cel testow: Sprawdza budowanie siatki 3D z parametrow przekrojow.
/// Dlaczego to wazne: Stala topologia jest warunkiem morfu bez artefaktow.
/// Kryteria zaliczenia: Liczba wierzcholkow i indeksow jest stala niezaleznie od wymiarow, a wierzchołki leza na zadanych wysokosciach.

import XCTest
import SceneKit
import simd
@testable import MeasureMe

final class BodyGeometryBuilderTests: XCTestCase {

    private static func parameters(circumference: Double) -> BodyMeshParameters {
        let snapshot = BodySnapshot(
            gender: .male, age: 30,
            heightCm: 180, weightKg: 80, bodyFatPercent: 18,
            neckCm: 38, shouldersCm: 118, chestCm: circumference, bustCm: nil,
            waistCm: 85, hipsCm: 98,
            bicepCm: 34, forearmCm: 28, thighCm: 58, calfCm: 38,
            anchorDate: Date(timeIntervalSince1970: 1_760_000_000),
            sourceDateRange: Date(timeIntervalSince1970: 1_760_000_000)...Date(timeIntervalSince1970: 1_760_000_000)
        )
        return BodyMeshSolver.solve(snapshot: snapshot, torsoShareScale: 1.0)
    }

    /// Co sprawdza: Topologia jest niezalezna od wymiarow ciala.
    /// Dlaczego: Morf podmienia tylko bufor pozycji; zmienna liczba wierzcholkow by to zlamala.
    /// Kryteria: Dwa rozne ciala daja te sama liczbe wierzcholkow i indeksow.
    func testTopologyIsIdenticalAcrossBodies() {
        let slim = Self.parameters(circumference: 90)
        let broad = Self.parameters(circumference: 115)

        XCTAssertEqual(
            BodyGeometryBuilder.positions(for: slim).count,
            BodyGeometryBuilder.positions(for: broad).count
        )
        XCTAssertEqual(
            BodyGeometryBuilder.indices(for: slim),
            BodyGeometryBuilder.indices(for: broad)
        )
    }

    /// Co sprawdza: Liczba wierzcholkow zgadza sie z liczba przekrojow razy segmenty.
    /// Dlaczego: Wylapuje zgubiony lub zdublowany pierscien.
    /// Kryteria: Liczba rowna sumie przekrojow (tors + 2 ramiona + 2 nogi) razy 32.
    func testVertexCountMatchesRingLayout() {
        let parameters = Self.parameters(circumference: 100)
        let rings = parameters.torso.count + 2 * parameters.arm.count + 2 * parameters.leg.count
        XCTAssertEqual(
            BodyGeometryBuilder.positions(for: parameters).count,
            rings * BodyGeometryBuilder.segmentsPerRing
        )
    }

    /// Co sprawdza: Wierzcholki torsu leza dokladnie na wysokosciach przekrojow.
    /// Dlaczego: Przesuniecie w pionie oznaczaloby, ze zmierzony obwod trafia na zla wysokosc.
    /// Kryteria: Kazda wysokosc przekroju wystepuje wsrod wspolrzednych y.
    func testTorsoVerticesSitAtSectionHeights() {
        let parameters = Self.parameters(circumference: 100)
        let ys = Set(BodyGeometryBuilder.positions(for: parameters).map { ($0.y * 1000).rounded() })
        for section in parameters.torso {
            // Positions are in metres; sections in centimetres.
            let expected = ((Float(section.y) / 100) * 1000).rounded()
            XCTAssertTrue(ys.contains(expected), "No ring at y=\(section.y) cm")
        }
    }

    /// Co sprawdza: Geometria powstaje i ma zrodlo pozycji oraz element indeksow.
    /// Dlaczego: To kontrakt wobec SceneKit.
    /// Kryteria: SCNGeometry ma niepuste sources i elements.
    func testGeometryHasSourcesAndElements() {
        let geometry = BodyGeometryBuilder.geometry(for: Self.parameters(circumference: 100))
        XCTAssertFalse(geometry.sources.isEmpty)
        XCTAssertFalse(geometry.elements.isEmpty)
    }

    /// Co sprawdza: Geometria niesie zrodlo normalnych, nie tylko pozycje.
    /// Dlaczego: Materialy .physicallyBased licza oswietlenie z normalnych — bez nich manekin
    ///           renderuje sie czarno, a zaden test jednostkowy tego nie widzi.
    /// Kryteria: SCNGeometry ma zrodlo o semantyce .normal.
    func testGeometryCarriesNormals() {
        let geometry = BodyGeometryBuilder.geometry(for: Self.parameters(circumference: 100))
        XCTAssertTrue(geometry.sources.contains { $0.semantic == .normal })
    }

    /// Co sprawdza: Kazda normalna jest wektorem jednostkowym.
    /// Dlaczego: Nieznormalizowane normalne daja bledna jasnosc; zerowe daja NaN i czarne piksele.
    /// Kryteria: Dlugosc kazdej normalnej rowna 1 z dokladnoscia 1e-4.
    func testNormalsAreUnitLength() {
        let normals = BodyGeometryBuilder.normals(for: Self.parameters(circumference: 100))
        XCTAssertFalse(normals.isEmpty)
        for normal in normals {
            XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-4)
        }
    }

    /// Co sprawdza: Liczba normalnych zgadza sie z liczba pozycji.
    /// Dlaczego: SceneKit paruje zrodla po indeksie; rozjazd dlugosci to ciche uszkodzenie siatki.
    /// Kryteria: normals(for:).count == positions(for:).count.
    func testNormalCountMatchesVertexCount() {
        let parameters = Self.parameters(circumference: 100)
        XCTAssertEqual(
            BodyGeometryBuilder.normals(for: parameters).count,
            BodyGeometryBuilder.positions(for: parameters).count
        )
    }
}
