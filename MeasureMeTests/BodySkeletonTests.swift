import XCTest
import simd
@testable import MeasureMe

final class BodySkeletonTests: XCTestCase {
    func testEveryRegionHasAtLeastOneBone() throws {
        let bones = try BodySkeleton.bones(for: .male)
        for region in BodyRegion.allCases {
            XCTAssertTrue(bones.contains { $0.region == region }, "brak kosci dla \(region)")
        }
    }

    /// Dlaczego: siatka jest znormalizowana do 0...1, a szkielet byl w etapie 1
    /// wypiekany w decymetrach zrodla. Ten test lapie nawrot tamtego bledu.
    func testJointsLandInsideTheNormalisedMesh() throws {
        for gender in BodyGender.allCases {
            for bone in try BodySkeleton.bones(for: gender) {
                for point in [bone.start, bone.end] {
                    XCTAssertTrue((-0.1...1.1).contains(point.y), "\(gender) \(bone.region) y=\(point.y)")
                }
            }
        }
    }

    func testLeftAndRightBonesMirrorAcrossX() throws {
        let bones = try BodySkeleton.bones(for: .male)
        let left = try XCTUnwrap(bones.first { $0.region == .leftUpperArm })
        let right = try XCTUnwrap(bones.first { $0.region == .rightUpperArm })
        XCTAssertEqual(left.start.x, -right.start.x, accuracy: 1e-5)
        XCTAssertEqual(left.start.y, right.start.y, accuracy: 1e-5)
    }

    /// Dlaczego: to jest liczba, ktora wymusila lokalne uklady dla ramion —
    /// poziomy przekroj bicepsa zawyzalby obwod o 1/cos(39,6) czyli ~30%.
    func testTheUpperArmSitsAboutFortyDegreesOffVertical() throws {
        let bone = try XCTUnwrap(try BodySkeleton.bones(for: .male).first { $0.region == .leftUpperArm })
        let axis = bone.end - bone.start
        XCTAssertEqual(atan2(abs(axis.x), abs(axis.y)) * 180 / .pi, 39.6, accuracy: 5.0)
    }

    /// Dlaczego: nogi sa prawie pionowe i to jest powod, dla ktorego blad
    /// poziomego ciecia mozna tam zignorowac.
    func testTheShinIsNearlyVertical() throws {
        let bone = try XCTUnwrap(try BodySkeleton.bones(for: .male).first { $0.region == .leftShin })
        let axis = bone.end - bone.start
        XCTAssertLessThan(atan2(abs(axis.x), abs(axis.y)) * 180 / .pi, 15.0)
    }

    /// Dlaczego: stawy musza zgadzac sie z tablicami, ktorych uzywa solver —
    /// inaczej obwod talii trafi w siatke na innej wysokosci niz zaklada model.
    func testJointHeightsAgreeWithTheAnthropometricTables() throws {
        let bones = try BodySkeleton.bones(for: .male)
        func start(_ region: BodyRegion) throws -> SIMD3<Float> {
            try XCTUnwrap(bones.first { $0.region == region }).start
        }
        XCTAssertEqual(
            Double(try start(.leftShin).y),
            BodyProportions.heightFraction(.knee, gender: .male),
            accuracy: 0.03
        )
        XCTAssertEqual(
            Double(try start(.leftThigh).y),
            BodyProportions.heightFraction(.hip, gender: .male),
            accuracy: 0.03
        )
    }

    /// Dlaczego: lancuch tors -> szyja -> glowa nie moze miec dziury. Przy
    /// probie przeniesienia kosci szyi do torsu skasowalem ja przez pomylke i
    /// miedzy 0,8595 a 0,9146 zrobila sie luka bez kosci, przez co przypisania
    /// w tym pasie stawaly sie przypadkowe.
    ///
    /// Miedzy torsem a glowa stoi teraz `.neck` — wlasny, mierzony region, bez
    /// ktorego `neckCm` nie dotykal siatki. Test pyta wiec o oba styki, nie o
    /// jeden.
    func testTheTorsoNeckAndHeadMeetWithoutAGap() throws {
        for gender in BodyGender.allCases {
            let bones = try BodySkeleton.bones(for: gender)
            func top(_ region: BodyRegion) throws -> Float {
                try XCTUnwrap(bones.filter { $0.region == region }.map(\.end.y).max())
            }
            func bottom(_ region: BodyRegion) throws -> Float {
                try XCTUnwrap(bones.filter { $0.region == region }.map(\.start.y).min())
            }
            XCTAssertEqual(try top(.torso), try bottom(.neck), accuracy: 1e-5, "\(gender) tors/szyja")
            XCTAssertEqual(try top(.neck), try bottom(.head), accuracy: 1e-5, "\(gender) szyja/glowa")
        }
    }
}
