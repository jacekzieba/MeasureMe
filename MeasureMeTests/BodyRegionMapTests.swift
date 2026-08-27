import XCTest
import simd
@testable import MeasureMe

final class BodyRegionMapTests: XCTestCase {
    private func makeMap(_ gender: BodyGender = .male) throws -> (BodyBaseMesh, BodyRegionMap) {
        let mesh = try BodyBaseMeshProvider.mesh(for: gender)
        return (mesh, BodyRegionMap.build(mesh: mesh, bones: try BodySkeleton.bones(for: gender)))
    }

    func testEveryVertexGetsARegionAndAPosition() throws {
        let (mesh, map) = try makeMap()
        XCTAssertEqual(map.region.count, mesh.positions.count)
        XCTAssertEqual(map.along.count, mesh.positions.count)
        XCTAssertNil(map.along.first { $0 < 0 || $0 > 1 })
    }

    /// Dlaczego: pusty region to cicha awaria — jego obwod nigdy by nie
    /// zadzialal, a model po prostu ignorowalby jeden z pomiarow.
    func testNoRegionIsEmpty() throws {
        for gender in BodyGender.allCases {
            let (_, map) = try makeMap(gender)
            for region in BodyRegion.allCases {
                XCTAssertTrue(map.region.contains(region), "\(gender): pusty region \(region)")
            }
        }
    }

    func testTheHighestVerticesBelongToTheHead() throws {
        let (mesh, map) = try makeMap()
        let top = try XCTUnwrap(mesh.positions.indices.max { mesh.positions[$0].y < mesh.positions[$1].y })
        XCTAssertEqual(map.region[top], .head)
    }

    func testTheLowestVerticesBelongToAFoot() throws {
        let (mesh, map) = try makeMap()
        let bottom = try XCTUnwrap(mesh.positions.indices.min { mesh.positions[$0].y < mesh.positions[$1].y })
        XCTAssertTrue([.leftFoot, .rightFoot].contains(map.region[bottom]), "\(map.region[bottom])")
    }

    /// Dlaczego: strony nie moga sie mieszac — lewa reka po prawej stronie
    /// oznaczalaby, ze pomiar bicepsa trafia w niewlasciwe ramie.
    func testArmAndLegRegionsStayOnTheirOwnSideOfTheBody() throws {
        let (mesh, map) = try makeMap()
        for index in mesh.positions.indices {
            switch map.region[index] {
            case .leftUpperArm, .leftForearm, .leftHand, .leftThigh, .leftShin, .leftFoot:
                XCTAssertGreaterThan(mesh.positions[index].x, -0.02, "wierzcholek \(index)")
            case .rightUpperArm, .rightForearm, .rightHand, .rightThigh, .rightShin, .rightFoot:
                XCTAssertLessThan(mesh.positions[index].x, 0.02, "wierzcholek \(index)")
            default: break
            }
        }
    }

    /// Dlaczego: zaden CZLONEK nie moze przejac torsu. Gdyby ramiona przejely
    /// klatke piersiowa, obwod klatki skalowalby reke.
    ///
    /// Nie pyta juz o najliczniejszy region w ogole, bo `.neck` bije tors —
    /// 1547 wierzcholkow wobec 1015 — i nie jest to bledem: szyja graniczy z
    /// gesto modelowana zuchwa i zabiera jej dolna czesc. Liczba wierzcholkow
    /// mierzy gestosc modelowania, nie powierzchnie ciala; sama glowa ma ich
    /// ponad cztery tysiace. Skalowanie zuchwy blokuje wygaszanie w
    /// `neckFactors`, nie podzial regionow.
    func testNoLimbTakesMoreOfTheMeshThanTheTorso() throws {
        let (_, map) = try makeMap()
        var counts: [BodyRegion: Int] = [:]
        for region in map.region { counts[region, default: 0] += 1 }
        let torso = counts[.torso] ?? 0
        XCTAssertGreaterThan(torso, 0)
        // Tylko MIERZONE segmenty konczyn. Dlonie i stopy sa niemierzone i
        // modelowane bardzo gesto — sama dlon ma 1599 wierzcholkow — wiec
        // porownywanie ich z torsem nie mowi nic o przypisaniu.
        for (region, count) in counts
        where region.isMeasured && (region.isArmChain || region == .leftThigh
            || region == .rightThigh || region == .leftShin || region == .rightShin) {
            XCTAssertLessThan(count, torso, "\(region) przejal wiecej siatki niz tors")
        }
    }

    /// Dlaczego: `along` musi biec wzdluz CALEGO lancucha regionu, nie jednej
    /// kosci. Tors ma piec kosci; przy parametrze liczonym per-kosc wierzcholek
    /// w polowie miednicy i wierzcholek w polowie klatki dostaja oba 0,5 i
    /// wpadaja do tego samego pasa, mieszajac talie z biodrami. Jesli parametr
    /// jest poprawny, rosnie monotonicznie z wysokoscia.
    func testTorsoPositionTracksHeight() throws {
        let (mesh, map) = try makeMap()
        let torso = mesh.positions.indices.filter { map.region[$0] == .torso }
        let byHeight = torso.sorted { mesh.positions[$0].y < mesh.positions[$1].y }

        let lowest = byHeight.prefix(80).map { map.along[$0] }
        let highest = byHeight.suffix(80).map { map.along[$0] }
        let lowMean = lowest.reduce(0, +) / Float(lowest.count)
        let highMean = highest.reduce(0, +) / Float(highest.count)

        XCTAssertLessThan(lowMean, 0.25, "dolne wierzcholki torsu powinny miec male `along`")
        XCTAssertGreaterThan(highMean, 0.75, "gorne wierzcholki torsu powinny miec duze `along`")
    }
}
