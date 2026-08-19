import XCTest
import simd
import SceneKit
@testable import MeasureMe

/// Cel testow: gdzie idzie czas przy wejsciu na ekran modelu 3D.
/// Drukuje pomiary, nie asertuje.
final class BodyModelStartupBenchmarkTests: XCTestCase {
    private func time(_ label: String, _ work: () -> Void) {
        let start = Date()
        work()
        let ms = (Date().timeIntervalSince(start) * 1000).rounded()
        print("  BENCH \(label) = \(Int(ms)) ms")
    }

    func testReportStartupCost() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MaleBase", withExtension: "bodymesh"))
        let data = try Data(contentsOf: url)

        print("=== KOSZT WEJSCIA NA EKRAN ===")
        var mesh: BodyBaseMesh!
        time("dekod .bodymesh") { mesh = try? BodyMeshFile.decode(data) }

        var bones: [BodyBone]!
        time("szkielet z JSON") { bones = try? BodySkeleton.bones(for: .male) }

        var map: BodyRegionMap!
        time("mapa regionow") { map = BodyRegionMap.build(mesh: mesh, bones: bones) }

        var profile: [BodyRegion: [BodyBand]]!
        time("profil pasow") {
            profile = BodyBandProfile.build(
                mesh: mesh, map: map, bones: bones,
                bandsPerRegion: BodyBandProfile.defaultBandCount
            )
        }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: 86, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        )
        var parameters: BodyMeshParameters!
        time("solver + walidator objetosci") {
            parameters = BodyVolumeValidator.reconcile(snapshot: snapshot).parameters
        }

        var positions: [SIMD3<Float>]!
        time("deformacja") {
            positions = BodyMeshDeformer.deform(
                mesh: mesh, map: map, profile: profile, parameters: parameters
            )
        }
        time("normalne") { _ = BodyMeshDeformer.normals(for: positions, indices: mesh.indices) }
        time("zrodla SCNGeometry") {
            _ = positions.map { SCNVector3($0.x, $0.y, $0.z) }
        }
    }
}
