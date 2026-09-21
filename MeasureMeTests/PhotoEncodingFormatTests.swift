/// Cel testow: Pilnuje, ze na symulatorze zdjecia sa kodowane do JPEG, a nie HEIC.
/// Dlaczego to wazne: Maszyny wirtualne CI nie maja sprzetowego kodera HEIC i wywolanie zawisa na zawsze (spindump: watki stoja w encodeForStorage ~120 s), przez co padaly testy PendingPhotoSaveStore.
/// Kryteria zaliczenia: Na symulatorze encodeForStorage zwraca JPEG; na urzadzeniu test jest pomijany.

import XCTest
import UIKit
@testable import MeasureMe

final class PhotoEncodingFormatTests: XCTestCase {
    func testEncodeForStorageUsesJPEGOnTheSimulator() throws {
        #if targetEnvironment(simulator)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        let encoded = try XCTUnwrap(PhotoUtilities.encodeForStorage(image, maxSize: 2_000_000))

        XCTAssertEqual(encoded.format, "JPEG")
        #else
        throw XCTSkip("Only the simulator avoids HEIC; devices keep it.")
        #endif
    }
}
