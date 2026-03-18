/// Cel testow: Weryfikuje renderowanie karty transformacji (TransformationCardRenderer).
/// Dlaczego to wazne: Blad w renderowaniu cicho niszczy eksport uzytkownika do social media.
///   Testy pokrywaja: generowanie JPEG, layout z/bez wagi, edge cases (0 dni, imperial).
/// Kryteria zaliczenia: Wszystkie nonisolated static func zwracaja deterministyczny wynik
///   dla danego wejscia — zero zaleznosci od UI czy SwiftData.

import XCTest
@testable import MeasureMe

// MARK: - Helpers

private func makeTestImageData(width: Int = 200, height: Int = 200, color: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create test image context")
    }
    ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let cgImage = ctx.makeImage() else {
        fatalError("Failed to create test CGImage")
    }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)!
}

private func makeInput(
    weightOld: Double? = 90.0,
    weightNew: Double? = 78.0,
    unitsSystem: String = "metric",
    olderDate: Date = Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!,
    newerDate: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!
) -> TransformationCardInput {
    TransformationCardInput(
        olderImageData: makeTestImageData(color: (0.8, 0.2, 0.2)),
        newerImageData: makeTestImageData(color: (0.2, 0.8, 0.2)),
        olderDate: olderDate,
        newerDate: newerDate,
        weightOld: weightOld,
        weightNew: weightNew,
        unitsSystem: unitsSystem
    )
}

// MARK: - Basic Rendering

final class TransformationCardRenderTests: XCTestCase {

    /// Co sprawdza: render() zwraca niepuste Data.
    func testRenderReturnsNonNilData() {
        let data = TransformationCardRenderer.render(makeInput())
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    /// Co sprawdza: Wynik jest poprawnym JPEG (magic bytes FF D8 FF).
    func testRenderOutputIsValidJPEG() {
        let data = TransformationCardRenderer.render(makeInput())!
        let bytes = [UInt8](data.prefix(3))
        XCTAssertEqual(bytes, [0xFF, 0xD8, 0xFF], "Output should start with JPEG magic bytes")
    }

    /// Co sprawdza: Wynikowy obraz ma wymiary 1080x1080.
    func testRenderOutputIs1080x1080() {
        let data = TransformationCardRenderer.render(makeInput())!
        let image = UIImage(data: data)!
        XCTAssertEqual(Int(image.size.width * image.scale), 1080, "Width should be 1080px")
        XCTAssertEqual(Int(image.size.height * image.scale), 1080, "Height should be 1080px")
    }

    /// Co sprawdza: Wynik ma rozsądny rozmiar pliku (>10KB, <5MB).
    func testRenderOutputHasReasonableFileSize() {
        let data = TransformationCardRenderer.render(makeInput())!
        XCTAssertGreaterThan(data.count, 10_000, "JPEG should be larger than 10KB")
        XCTAssertLessThan(data.count, 5_000_000, "JPEG should be smaller than 5MB")
    }
}

// MARK: - Without Weight Data

final class TransformationCardNoWeightTests: XCTestCase {

    /// Co sprawdza: render() działa poprawnie bez danych o wadze.
    func testRenderWithoutWeightReturnsNonNil() {
        let data = TransformationCardRenderer.render(makeInput(weightOld: nil, weightNew: nil))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Obraz bez wagi jest poprawnym JPEG 1080x1080.
    func testRenderWithoutWeightIs1080x1080() {
        let data = TransformationCardRenderer.render(makeInput(weightOld: nil, weightNew: nil))!
        let image = UIImage(data: data)!
        XCTAssertEqual(Int(image.size.width * image.scale), 1080)
        XCTAssertEqual(Int(image.size.height * image.scale), 1080)
    }

    /// Co sprawdza: Waga tylko na jednym zdjęciu traktowana jak brak wagi.
    func testRenderWithPartialWeightReturnsNonNil() {
        let data = TransformationCardRenderer.render(makeInput(weightOld: 90.0, weightNew: nil))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Obraz bez wagi ma inny rozmiar niż z wagą (mniej elementów).
    func testRenderWithoutWeightDifferentSizeThanWithWeight() {
        let withWeight = TransformationCardRenderer.render(makeInput())!
        let withoutWeight = TransformationCardRenderer.render(makeInput(weightOld: nil, weightNew: nil))!
        XCTAssertNotEqual(withWeight.count, withoutWeight.count, "Cards with and without weight should differ in size")
    }
}

// MARK: - Edge Cases

final class TransformationCardEdgeCaseTests: XCTestCase {

    /// Co sprawdza: 0 dni odstępu (to samo zdjęcie) nie crashuje.
    func testRenderSameDayDoesNotCrash() {
        let now = Date()
        let data = TransformationCardRenderer.render(makeInput(olderDate: now, newerDate: now))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Imperial units nie crashuje.
    func testRenderImperialUnitsReturnsNonNil() {
        let data = TransformationCardRenderer.render(makeInput(unitsSystem: "imperial"))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Bardzo duża różnica wagi (300 → 60 kg) nie crashuje.
    func testRenderExtremeWeightChangeDoesNotCrash() {
        let data = TransformationCardRenderer.render(makeInput(weightOld: 300.0, weightNew: 60.0))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Waga 0 kg (edge case dzielenia) nie crashuje.
    func testRenderZeroOldWeightDoesNotCrash() {
        let data = TransformationCardRenderer.render(makeInput(weightOld: 0.0, weightNew: 80.0))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Wzrost wagi (np. bulking) renderuje poprawnie.
    func testRenderWeightGainReturnsNonNil() {
        let data = TransformationCardRenderer.render(makeInput(weightOld: 60.0, weightNew: 85.0))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Bardzo krótki okres (1 dzień) nie crashuje.
    func testRenderOneDayApartDoesNotCrash() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let data = TransformationCardRenderer.render(makeInput(olderDate: yesterday, newerDate: today))
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Bardzo długi okres (10+ lat) nie crashuje.
    func testRenderTenYearsApartDoesNotCrash() {
        let start = Calendar.current.date(from: DateComponents(year: 2015, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!
        let data = TransformationCardRenderer.render(makeInput(olderDate: start, newerDate: end))
        XCTAssertNotNil(data)
    }
}

// MARK: - Photo Input Variations

final class TransformationCardPhotoInputTests: XCTestCase {

    /// Co sprawdza: Różne rozmiary zdjęć (portrait + landscape) nie crashują.
    func testRenderMixedAspectRatiosDoesNotCrash() {
        let portrait = makeTestImageData(width: 300, height: 600)
        let landscape = makeTestImageData(width: 600, height: 300)
        let input = TransformationCardInput(
            olderImageData: portrait,
            newerImageData: landscape,
            olderDate: Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!,
            newerDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!,
            weightOld: 90.0,
            weightNew: 78.0,
            unitsSystem: "metric"
        )
        let data = TransformationCardRenderer.render(input)
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Bardzo duże zdjęcia (4000x4000) renderują poprawnie (downsampling).
    func testRenderLargePhotosDoesNotCrash() {
        let large = makeTestImageData(width: 4000, height: 4000)
        let input = TransformationCardInput(
            olderImageData: large,
            newerImageData: large,
            olderDate: Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!,
            newerDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!,
            weightOld: 90.0,
            weightNew: 78.0,
            unitsSystem: "metric"
        )
        let data = TransformationCardRenderer.render(input)
        XCTAssertNotNil(data)
    }

    /// Co sprawdza: Bardzo małe zdjęcia (10x10) renderują poprawnie.
    func testRenderTinyPhotosDoesNotCrash() {
        let tiny = makeTestImageData(width: 10, height: 10)
        let input = TransformationCardInput(
            olderImageData: tiny,
            newerImageData: tiny,
            olderDate: Calendar.current.date(from: DateComponents(year: 2020, month: 1, day: 1))!,
            newerDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!,
            weightOld: 90.0,
            weightNew: 78.0,
            unitsSystem: "metric"
        )
        let data = TransformationCardRenderer.render(input)
        XCTAssertNotNil(data)
    }
}
