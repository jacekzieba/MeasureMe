import XCTest
import simd
@testable import MeasureMe

/// Cel testow: sciezka morfa A->B, czyli to, co realnie robi suwak na ekranie.
/// Dlaczego to wazne: deformator byl testowany na pojedynczych stanach, ale
/// suwak karmi go wynikiem `BodyMeshParameters.interpolated`. To ostatnie
/// kryterium wyjscia etapu 2 — model ma zmieniac KSZTALT, nie tylko wzrost.
/// Kryteria zaliczenia: konce trafiaja w pomiar, srodek lezy miedzy nimi.
final class BodyMorphTests: XCTestCase {
    private func snapshot(waistCm: Double, heightCm: Double = 180) -> BodySnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BodySnapshot(
            gender: .male, age: 31, heightCm: heightCm, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: waistCm, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        )
    }

    private func waist(at t: Double, from: Double, to: Double) throws -> Double {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let rig = try BodyBaseMeshProvider.rig(for: .male)
        let parameters = BodyMeshParameters.interpolated(
            from: BodyMeshSolver.solve(snapshot: snapshot(waistCm: from)),
            to: BodyMeshSolver.solve(snapshot: snapshot(waistCm: to)),
            t: t
        )
        let positions = BodyMeshDeformer.deform(
            mesh: mesh, map: rig.map, profile: rig.profile, parameters: parameters
        )
        return Double(BodyMeshDeformer.circumference(
            of: positions, map: rig.map, region: .torso,
            atHeight: Float(BodyProportions.heightFraction(.waist, gender: .male) * 1.80)
        )) * 100
    }

    /// Dlaczego: to jest cala obietnica ekranu — przesuniecie suwaka ma pokazac
    /// zmiane sylwetki. Gdyby deformacja gubila sie w interpolacji, model
    /// wygladalby identycznie na obu koncach.
    func testTheMorphMovesTheWaistBetweenTheTwoMeasuredStates() throws {
        let start = try waist(at: 0, from: 78, to: 98)
        let middle = try waist(at: 0.5, from: 78, to: 98)
        let end = try waist(at: 1, from: 78, to: 98)

        XCTAssertEqual(start, 78, accuracy: 78 * 0.04)
        XCTAssertEqual(end, 98, accuracy: 98 * 0.04)
        XCTAssertGreaterThan(middle, start + 4, "srodek musi odjechac od poczatku")
        XCTAssertLessThan(middle, end - 4, "srodek musi nie dojechac do konca")
    }

    /// Dlaczego: niezmiennik z `BodyMeshParameters.interpolated` — konce morfa
    /// musza byc bit-identyczne z zmierzonymi cialami, nie ich przyblizeniem.
    func testTheEndpointsAreTheMeasuredBodiesExactly() throws {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let rig = try BodyBaseMeshProvider.rig(for: .male)
        func positions(_ parameters: BodyMeshParameters) -> [SIMD3<Float>] {
            BodyMeshDeformer.deform(
                mesh: mesh, map: rig.map, profile: rig.profile, parameters: parameters
            )
        }
        let a = BodyMeshSolver.solve(snapshot: snapshot(waistCm: 78))
        let b = BodyMeshSolver.solve(snapshot: snapshot(waistCm: 98))
        XCTAssertEqual(positions(BodyMeshParameters.interpolated(from: a, to: b, t: 0)), positions(a))
        XCTAssertEqual(positions(BodyMeshParameters.interpolated(from: a, to: b, t: 1)), positions(b))
    }

    /// Dlaczego: morf laczy tez dwa rozne wzrosty i nie wolno, zeby posrednia
    /// klatka byla wyzsza lub nizsza od obu koncow.
    func testStatureStaysBetweenTheEndpointsThroughTheMorph() throws {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let rig = try BodyBaseMeshProvider.rig(for: .male)
        let a = BodyMeshSolver.solve(snapshot: snapshot(waistCm: 86, heightCm: 170))
        let b = BodyMeshSolver.solve(snapshot: snapshot(waistCm: 86, heightCm: 190))
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            let top = BodyMeshDeformer.deform(
                mesh: mesh, map: rig.map, profile: rig.profile,
                parameters: BodyMeshParameters.interpolated(from: a, to: b, t: t)
            ).map(\.y).max() ?? 0
            XCTAssertGreaterThanOrEqual(Double(top), 1.70 - 0.01, "t=\(t)")
            XCTAssertLessThanOrEqual(Double(top), 1.90 + 0.01, "t=\(t)")
        }
    }
}
