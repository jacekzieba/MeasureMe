import XCTest
import simd
@testable import MeasureMe

final class BodyBandProfileTests: XCTestCase {
    private func makeProfile(
        _ gender: BodyGender = .male, bands: Int = BodyBandProfile.defaultBandCount
    ) throws -> [BodyRegion: [BodyBand]] {
        let mesh = try BodyBaseMeshProvider.mesh(for: gender)
        let bones = try BodySkeleton.bones(for: gender)
        return BodyBandProfile.build(
            mesh: mesh,
            map: BodyRegionMap.build(mesh: mesh, bones: bones),
            bones: bones,
            bandsPerRegion: bands
        )
    }

    func testEveryRegionGetsBandsWithAPositiveCircumference() throws {
        for gender in BodyGender.allCases {
            let profile = try makeProfile(gender)
            for region in BodyRegion.allCases {
                let bands = try XCTUnwrap(profile[region], "\(gender) \(region)")
                XCTAssertFalse(bands.isEmpty, "\(gender) \(region)")
                XCTAssertNil(bands.first { $0.circumference <= 0 }, "\(gender) \(region)")
            }
        }
    }

    /// Dlaczego: tylko 7,6% wierzcholkow siedzi w torsie, wiec zbyt gesty
    /// podzial daje pasy z paroma punktami, ktorych otoczka nic nie znaczy —
    /// pas z jednym wierzcholkiem ma obwod zero. Zmierzone minimum zapelnienia
    /// (M / K): 24 pasy → 0, 12 → 2, 10 → 10 / 6, 8 → 16 / 20. Wiazacym
    /// ograniczeniem jest damskie przedramie, nie meskie.
    func testEveryMeasuredBandHasEnoughVerticesToHull() throws {
        for gender in BodyGender.allCases {
            let profile = try makeProfile(gender)
            for (region, bands) in profile where region.isMeasured {
                for band in bands {
                    XCTAssertGreaterThanOrEqual(
                        band.vertexCount, 8, "\(gender) \(region) ma pas z \(band.vertexCount)"
                    )
                }
            }
        }
    }

    /// Dlaczego: gdyby ktos podniosl liczbe pasow "dla gladkosci", ten test
    /// pokaze, ze siatka tego nie uniesie, zanim obwod zero trafi do renderu.
    func testRaisingTheBandCountStarvesTheSparsestRegion() throws {
        let dense = try makeProfile(.male, bands: 24)
        let starved = dense.filter { $0.key.isMeasured }
            .flatMap(\.value)
            .filter { $0.vertexCount < 8 }
        XCTAssertFalse(starved.isEmpty, "24 pasy powinny wyglodzic czesc regionow")
    }

    /// Dlaczego: liczby sanity-check na prawdziwym ciele. Siatka jest wysoka
    /// na 1,0, wiec obwod torsu ma wypasc rzedu 0,4-0,5 — czyli 72-90 cm przy
    /// wzroscie 180. Rzad wielkosci musi sie zgadzac, inaczej skala jest zla.
    func testTorsoCircumferencesAreInAPlausibleRange() throws {
        let bands = try XCTUnwrap(try makeProfile()[.torso])
        for band in bands {
            XCTAssertGreaterThan(band.circumference, 0.10)
            XCTAssertLessThan(band.circumference, 0.90)
        }
    }

    /// Dlaczego: os ramienia musi byc odchylona od pionu, inaczej przekroj idzie
    /// poziomo i obwod bicepsa jest zawyzony o ~30%.
    func testTheUpperArmBandsAreTiltedOffVertical() throws {
        let bands = try XCTUnwrap(try makeProfile()[.leftUpperArm])
        XCTAssertGreaterThan(abs(try XCTUnwrap(bands.first).axis.x), 0.4)
    }

    func testAnArmBandIsThinnerThanATorsoBand() throws {
        let profile = try makeProfile()
        let arm = try XCTUnwrap(profile[.leftUpperArm]?.map(\.circumference).max())
        let torso = try XCTUnwrap(profile[.torso]?.map(\.circumference).max())
        XCTAssertLessThan(arm, torso)
    }

    /// Dlaczego: lewa i prawa strona musza wyjsc identyczne, bo siatka jest
    /// symetryczna. Rozjazd znaczylby, ze przypisanie regionow jest niestabilne.
    func testLeftAndRightLimbsMeasureTheSame() throws {
        let profile = try makeProfile()
        for (left, right) in [(BodyRegion.leftUpperArm, BodyRegion.rightUpperArm),
                              (.leftThigh, .rightThigh), (.leftShin, .rightShin)] {
            let l = try XCTUnwrap(profile[left]).map(\.circumference)
            let r = try XCTUnwrap(profile[right]).map(\.circumference)
            XCTAssertEqual(l.count, r.count, "\(left) vs \(right)")
            for (a, b) in zip(l, r) {
                XCTAssertEqual(a, b, accuracy: 1e-4, "\(left) vs \(right)")
            }
        }
    }
}
