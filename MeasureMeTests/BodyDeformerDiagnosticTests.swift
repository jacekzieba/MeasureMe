import XCTest
import simd
@testable import MeasureMe

/// Cel testow: diagnostyka deformatora — drukuje liczby, nie asertuje.
/// Dlaczego to wazne: round-trip zanizal obwod i zgadywanie przyczyny kosztowalo
/// juz jedna runde. Ten plik pokazuje, gdzie dokladnie rozjezdza sie baza.
final class BodyDeformerDiagnosticTests: XCTestCase {
    func testReportWorstEdges() throws {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let bones = try BodySkeleton.bones(for: .male)
        let map = BodyRegionMap.build(mesh: mesh, bones: bones)
        let profile = BodyBandProfile.build(
            mesh: mesh, map: map, bones: bones,
            bandsPerRegion: BodyBandProfile.defaultBandCount
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let parameters = BodyMeshSolver.solve(snapshot: BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: 104, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        ))
        let deformed = BodyMeshDeformer.deform(
            mesh: mesh, map: map, profile: profile, parameters: parameters
        )
        let stature = Float(1.80)

        var worst: [(ratio: Float, i: Int, j: Int)] = []
        var triangle = 0
        while triangle + 2 < mesh.indices.count {
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let i = Int(mesh.indices[triangle + a]), j = Int(mesh.indices[triangle + b])
                let before = simd_distance(mesh.positions[i], mesh.positions[j]) * stature
                guard before > 1e-6 else { continue }
                worst.append((simd_distance(deformed[i], deformed[j]) / before, i, j))
            }
            triangle += 3
        }
        worst.sort { $0.ratio > $1.ratio }

        print("=== NAJGORSZE KRAWEDZIE ===")
        for entry in worst.prefix(12) {
            print(String(
                format: "  x%.2f  %@(blend %.3f, 2nd %@)  <->  %@(blend %.3f, 2nd %@)  y=%.3f/%.3f",
                entry.ratio,
                "\(map.region[entry.i])", map.blend[entry.i], "\(map.secondary[entry.i])",
                "\(map.region[entry.j])", map.blend[entry.j], "\(map.secondary[entry.j])",
                mesh.positions[entry.i].y, mesh.positions[entry.j].y
            ))
        }
        let counts = Dictionary(grouping: worst.prefix(400)) {
            "\($0.i == $0.i ? map.region[$0.i] : map.region[$0.i])-\(map.region[$0.j])"
        }.mapValues(\.count).sorted { $0.value > $1.value }
        print("=== PARY REGIONOW W 400 NAJGORSZYCH ===")
        for (pair, count) in counts.prefix(8) { print("  \(pair): \(count)") }
    }

    func testReportWaistPipeline() throws {
        let mesh = try BodyBaseMeshProvider.mesh(for: .male)
        let bones = try BodySkeleton.bones(for: .male)
        let map = BodyRegionMap.build(mesh: mesh, bones: bones)
        let profile = BodyBandProfile.build(
            mesh: mesh, map: map, bones: bones,
            bandsPerRegion: BodyBandProfile.defaultBandCount
        )

        let waistFraction = Float(BodyProportions.heightFraction(.waist, gender: .male))
        let bands = try XCTUnwrap(profile[.torso])

        print("=== PASY TORSU (baza, jednostki siatki) ===")
        for (index, band) in bands.enumerated() {
            let horizontal = BodyMeshDeformer.circumference(
                of: mesh.positions, map: map, region: .torso, atHeight: band.centroid.y
            )
            print(String(
                format: "  pas %d  y=%.4f  pas-obwod=%.4f  poziomy=%.4f  iloraz=%.3f  n=%d",
                index, band.centroid.y, band.circumference, horizontal,
                horizontal > 0 ? band.circumference / horizontal : 0, band.vertexCount
            ))
        }

        print("=== TALIA ===")
        print(String(format: "  wysokosc talii (frakcja) = %.4f", waistFraction))
        let baseHorizontal = BodyMeshDeformer.circumference(
            of: mesh.positions, map: map, region: .torso, atHeight: waistFraction
        )
        print(String(format: "  poziomy obwod bazy w talii = %.4f  (%.1f cm przy 180)",
                     baseHorizontal, baseHorizontal * 180))

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = BodySnapshot(
            gender: .male, age: 31, heightCm: 180, weightKg: 80, bodyFatPercent: 20,
            neckCm: 38, shouldersCm: 118, chestCm: 100, bustCm: nil,
            waistCm: 86, hipsCm: 98, bicepCm: 33, forearmCm: 28,
            thighCm: 58, calfCm: 38, anchorDate: date, sourceDateRange: date...date
        )
        let parameters = BodyMeshSolver.solve(snapshot: snapshot)
        let factors = try XCTUnwrap(
            BodyMeshDeformer.scaleFactors(parameters: parameters, profile: profile)[.torso]
        )
        print("=== WSPOLCZYNNIKI ===")
        for (index, factor) in factors.enumerated() {
            let target = BodyMeshDeformer.sample(
                parameters.torso, atHeightCm: Double(bands[index].centroid.y) * 180
            )
            print(String(format: "  pas %d  cel=%.1f cm  wspolczynnik=%.4f", index, target, factor))
        }

        let deformed = BodyMeshDeformer.deform(
            mesh: mesh, map: map, profile: profile, parameters: parameters
        )
        let measured = BodyMeshDeformer.circumference(
            of: deformed, map: map, region: .torso, atHeight: waistFraction * 1.80
        )
        print(String(format: "=== WYNIK ===\n  zmierzona talia = %.2f cm (cel 86)", measured * 100))
        print(String(format: "  solver w talii  = %.2f cm",
                     BodyMeshDeformer.sample(parameters.torso, atHeightCm: Double(waistFraction) * 180)))
    }
}
