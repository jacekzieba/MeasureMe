import XCTest
import simd
@testable import MeasureMe

/// Cel testow: diagnostyka konczyn — drukuje obwody, nie asertuje.
final class BodyLimbDiagnosticTests: XCTestCase {
    func testReportRenderedLimbGirths() throws {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let rig = try BodyBaseMeshProvider.rig(for: .male)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: 86, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        )
        let parameters = BodyMeshSolver.solve(snapshot: snapshot)
        let deformed = BodyMeshDeformer.deform(
            mesh: mesh, map: rig.map, profile: rig.profile, parameters: parameters
        )

        print("=== POMIARY WEJSCIOWE ===")
        print("  bicep 33  przedramie 28  udo 58  lydka 38  talia 86  biodra 98")

        // Obwod prostopadly do osi regionu, na kazdym pasie, po deformacji.
        for region: BodyRegion in [.leftUpperArm, .leftForearm, .leftThigh, .leftShin, .torso] {
            guard let bands = rig.profile[region] else { continue }
            let axis = bands[0].axis
            let (right, up) = BodyBandProfile.frame(for: axis)
            print("=== \(region) ===")
            for (index, band) in bands.enumerated() {
                let members = deformed.indices.filter {
                    rig.map.region[$0] == region
                        && abs(simd_dot(deformed[$0] / 1.80, axis) - band.position) < 0.012
                }
                guard members.count > 2 else { continue }
                let centre = members.reduce(SIMD3<Float>.zero) { $0 + deformed[$1] } / Float(members.count)
                let flat = members.map { index -> SIMD2<Float> in
                    let off = deformed[index] - centre
                    return SIMD2(simd_dot(off, right), simd_dot(off, up))
                }
                let target = BodyMeshDeformer.sample(
                    region == .leftUpperArm || region == .leftForearm ? parameters.arm
                        : (region == .leftThigh || region == .leftShin ? parameters.leg : parameters.torso),
                    atHeightCm: Double(band.centroid.y) * 180
                )
                print(String(format: "  pas %d  y=%.3f  baza=%5.1f  cel=%5.1f  PO=%5.1f cm  (n=%d)",
                             index, band.centroid.y, band.circumference * 180,
                             target, ConvexHull.perimeter(of: flat) * 100, members.count))
            }
        }
    }
}
