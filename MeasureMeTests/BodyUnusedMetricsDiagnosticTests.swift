import XCTest
import simd
@testable import MeasureMe

/// Cel testow: czy pomiary barkow i szyi realnie zmieniaja renderowana siatke.
/// Drukuje, nie asertuje.
@MainActor
final class BodyUnusedMetricsDiagnosticTests: XCTestCase {
    private func snapshot(shoulders: Double = 118, neck: Double = 38) -> BodySnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: neck, shouldersCm: shoulders, chestCm: 100, bustCm: nil,
            waistCm: 86, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        )
    }

    private func positions(_ snapshot: BodySnapshot) throws -> [SIMD3<Float>] {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let rig = try BodyBaseMeshProvider.rig(for: .male)
        return BodyMeshDeformer.deform(
            mesh: mesh, map: rig.map, profile: rig.profile,
            parameters: BodyVolumeValidator.reconcile(snapshot: snapshot).parameters
        )
    }

    func testReportWhetherShouldersAndNeckMoveAnything() throws {
        let base = try positions(snapshot())
        for (label, other) in [
            ("barki 118 -> 100", snapshot(shoulders: 100)),
            ("barki 118 -> 140", snapshot(shoulders: 140)),
            ("szyja  38 -> 32",  snapshot(neck: 32)),
            ("szyja  38 -> 46",  snapshot(neck: 46)),
        ] {
            let moved = try positions(other)
            let deltas = zip(base, moved).map { simd_distance($0, $1) }
            let maxMm = (deltas.max() ?? 0) * 1000
            let moving = deltas.filter { $0 > 0.0005 }.count
            print(String(format: "  WPLYW %@ : max %.2f mm, ruszonych wierzcholkow %d",
                         label, maxMm, moving))
        }
    }
}
