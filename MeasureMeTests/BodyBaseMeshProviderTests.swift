import XCTest
import simd
@testable import MeasureMe

final class BodyBaseMeshProviderTests: XCTestCase {
    /// Dlaczego: liczba zmierzona na base.obj — grupa `body` ma dokladnie tyle
    /// wierzcholkow. Rozjazd znaczy, ze wypiek zlapal helpery albo jointy.
    func testBakedMeshesCarryTheBodyGroupOnly() throws {
        for gender in BodyGender.allCases {
            let mesh = try BodyBaseMeshProvider.mesh(for: gender)
            XCTAssertEqual(mesh.positions.count, 13_380, "\(gender)")
            XCTAssertEqual(mesh.normals.count, mesh.positions.count, "\(gender)")
            XCTAssertEqual(mesh.indices.count % 3, 0, "\(gender)")
        }
    }

    func testBakedMeshesStandOnTheFloorAtUnitHeight() throws {
        for gender in BodyGender.allCases {
            let ys = try BodyBaseMeshProvider.mesh(for: gender).positions.map(\.y)
            XCTAssertEqual(try XCTUnwrap(ys.min()), 0, accuracy: 1e-5, "\(gender)")
            XCTAssertEqual(try XCTUnwrap(ys.max()), 1, accuracy: 1e-5, "\(gender)")
        }
    }

    func testBakedMeshesContainNoNaN() throws {
        for gender in BodyGender.allCases {
            let mesh = try BodyBaseMeshProvider.mesh(for: gender)
            XCTAssertFalse(mesh.positions.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }, "\(gender)")
            XCTAssertFalse(mesh.normals.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN }, "\(gender)")
        }
    }

    /// Dlaczego: indeks poza tablica to crash w SceneKit, nie wyjatek.
    func testIndicesStayInsideTheVertexArray() throws {
        for gender in BodyGender.allCases {
            let mesh = try BodyBaseMeshProvider.mesh(for: gender)
            let limit = Int32(mesh.positions.count)
            XCTAssertNil(mesh.indices.first { $0 < 0 || $0 >= limit }, "\(gender)")
        }
    }

    func testScalingToStatureMakesTheMeshThatManyMetresTall() throws {
        let scaled = try BodyBaseMeshProvider.mesh(for: .male).positions(forHeightCm: 182)
        XCTAssertEqual(scaled.map(\.y).max() ?? 0, 1.82, accuracy: 1e-4)
    }

    func testMaleAndFemaleBasesAreDifferentMeshes() throws {
        let male = try BodyBaseMeshProvider.mesh(for: .male)
        let female = try BodyBaseMeshProvider.mesh(for: .female)
        XCTAssertNotEqual(male.positions, female.positions)
    }
}
