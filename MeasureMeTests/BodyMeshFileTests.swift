import XCTest
import simd
@testable import MeasureMe

final class BodyMeshFileTests: XCTestCase {
    /// Jeden wierzcholek i jeden trojkat — minimalny poprawny plik.
    private func makeData(
        magic: String = "BMSH",
        version: UInt32 = 1,
        positions: [SIMD3<Float>] = [SIMD3(1, 2, 3)],
        normals: [SIMD3<Float>] = [SIMD3(0, 1, 0)],
        indices: [UInt32] = [0, 0, 0]
    ) -> Data {
        var data = Data(magic.utf8)
        for value in [version, UInt32(positions.count), UInt32(indices.count)] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        for vector in positions + normals {
            for scalar in [vector.x, vector.y, vector.z] {
                withUnsafeBytes(of: scalar) { data.append(contentsOf: $0) }
            }
        }
        for index in indices {
            withUnsafeBytes(of: index.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    func testDecodeReadsPositionsNormalsAndIndices() throws {
        let mesh = try BodyMeshFile.decode(makeData())
        XCTAssertEqual(mesh.positions, [SIMD3<Float>(1, 2, 3)])
        XCTAssertEqual(mesh.normals, [SIMD3<Float>(0, 1, 0)])
        XCTAssertEqual(mesh.indices, [0, 0, 0])
    }

    func testDecodeRejectsForeignMagic() {
        XCTAssertThrowsError(try BodyMeshFile.decode(makeData(magic: "NOPE"))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .badMagic)
        }
    }

    /// Dlaczego: format ma sie psuc glosno przy zmianie wersji, a nie czytac
    /// starym parserem nowy uklad bajtow i renderowac smieci.
    func testDecodeRejectsFutureVersion() {
        XCTAssertThrowsError(try BodyMeshFile.decode(makeData(version: 2))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .unsupportedVersion(2))
        }
    }

    func testDecodeRejectsTruncatedPayload() {
        XCTAssertThrowsError(try BodyMeshFile.decode(makeData().dropLast(4))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .truncated)
        }
    }

    func testDecodeRejectsDataShorterThanTheHeader() {
        XCTAssertThrowsError(try BodyMeshFile.decode(Data("BMSH".utf8))) { error in
            XCTAssertEqual(error as? BodyMeshFile.DecodeError, .truncated)
        }
    }
}
