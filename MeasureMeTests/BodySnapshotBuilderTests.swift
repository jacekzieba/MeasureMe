/// Cel testow: Sprawdza budowanie kompletnego snapshotu ciala z surowych probek.
/// Dlaczego to wazne: Snapshot jest jedynym wejsciem modelu 3D; blad tutaj psuje cala sylwetke.
/// Kryteria zaliczenia: Okno +/-14 dni, usrednianie lewa/prawa i wykrywanie brakow dzialaja zgodnie ze specyfikacja.

import XCTest
import Foundation
@testable import MeasureMe

final class BodySnapshotBuilderTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func day(_ offset: Int) -> Date {
        anchor.addingTimeInterval(Double(offset) * 86_400)
    }

    /// Buduje komplet probek dla mezczyzny, wszystkie w dniu kotwiczacym.
    private func completeMaleSamples(at date: Date) -> [MetricSample] {
        let values: [MetricKind: Double] = [
            .height: 180, .weight: 80, .bodyFat: 18,
            .neck: 38, .shoulders: 118, .chest: 100, .waist: 85, .hips: 98,
            .leftBicep: 34, .rightBicep: 34,
            .leftForearm: 28, .rightForearm: 28,
            .leftThigh: 58, .rightThigh: 58,
            .leftCalf: 38, .rightCalf: 38
        ]
        return values.map { MetricSample(kind: $0.key, value: $0.value, date: date) }
    }

    /// Co sprawdza: Komplet probek daje snapshot, a nie liste brakow.
    /// Dlaczego: To sciezka happy path calego feature'u.
    /// Kryteria: Wynik to .success z wartosciami przepisanymi 1:1.
    func testCompleteSampleSetBuildsSnapshot() {
        let result = BodySnapshotBuilder.build(
            samples: completeMaleSamples(at: anchor),
            anchorDate: anchor,
            gender: .male,
            age: 30,
            fallbackHeightCm: 0
        )
        guard case let .success(snapshot) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(snapshot.heightCm, 180, accuracy: 1e-9)
        XCTAssertEqual(snapshot.waistCm, 85, accuracy: 1e-9)
        XCTAssertNil(snapshot.bustCm)
    }

    /// Co sprawdza: Lewa i prawa strona sa usredniane.
    /// Dlaczego: Spec wymaga jednej, symetrycznej sylwetki.
    /// Kryteria: Bicep 34/36 daje 35.
    func testLeftAndRightAreAveraged() {
        var samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.rightBicep.rawValue }
        samples.append(MetricSample(kind: .rightBicep, value: 36, date: anchor))

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.bicepCm, 35, accuracy: 1e-9)
    }

    /// Co sprawdza: Jedna strona pary wystarcza.
    /// Dlaczego: Wymaganie obu stron podnosiloby prog wejscia bez zysku dla modelu.
    /// Kryteria: Snapshot powstaje, a wartosc to ta jedna zmierzona strona.
    func testSingleSideOfAPairIsSufficient() {
        let samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.rightCalf.rawValue }

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.calfCm, 38, accuracy: 1e-9)
    }

    /// Co sprawdza: Granice okna +/-14 dni.
    /// Dlaczego: To rdzen definicji snapshotu ze specyfikacji.
    /// Kryteria: 14 dni wchodzi, 15 dni nie.
    func testWindowBoundaryAtFourteenDays() {
        var inside = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.waist.rawValue }
        inside.append(MetricSample(kind: .waist, value: 85, date: day(-14)))
        guard case .success = BodySnapshotBuilder.build(
            samples: inside, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("14 days should be inside the window") }

        var outside = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.waist.rawValue }
        outside.append(MetricSample(kind: .waist, value: 85, date: day(-15)))
        guard case let .missing(kinds) = BodySnapshotBuilder.build(
            samples: outside, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("15 days should be outside the window") }
        XCTAssertEqual(kinds, [.waist])
    }

    /// Co sprawdza: Wybierana jest probka najblizsza dacie kotwiczacej.
    /// Dlaczego: Snapshot ma reprezentowac moment, nie sredni z okna.
    /// Kryteria: Przy dwoch probkach w oknie wygrywa blizsza.
    func testNearestSampleWithinWindowWins() {
        var samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.waist.rawValue }
        samples.append(MetricSample(kind: .waist, value: 90, date: day(-10)))
        samples.append(MetricSample(kind: .waist, value: 85, date: day(-2)))

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.waistCm, 85, accuracy: 1e-9)
    }

    /// Co sprawdza: Bust jest wymagany tylko u kobiet.
    /// Dlaczego: U mezczyzn obwod klatki niesie te sama informacje.
    /// Kryteria: Te same probki bez bustu przechodza dla mezczyzny i nie dla kobiety.
    func testBustRequiredOnlyForFemale() {
        let samples = completeMaleSamples(at: anchor)

        guard case .success = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Male should not need bust") }

        guard case let .missing(kinds) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .female, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Female should need bust") }
        XCTAssertEqual(kinds, [.bust])
    }

    /// Co sprawdza: Brak probki wzrostu jest uzupelniany wzrostem z profilu.
    /// Dlaczego: manualHeight w ustawieniach jest dla wielu userow jedynym zrodlem wzrostu.
    /// Kryteria: Snapshot powstaje i uzywa wartosci fallbackowej.
    func testFallbackHeightIsUsedWhenNoHeightSample() {
        let samples = completeMaleSamples(at: anchor)
            .filter { $0.kindRaw != MetricKind.height.rawValue }

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 178
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.heightCm, 178, accuracy: 1e-9)
    }

    /// Co sprawdza: Braki sa raportowane w calosci, nie po pierwszym napotkanym.
    /// Dlaczego: Stan pusty ma wymieniac userowi wszystko, czego brakuje.
    /// Kryteria: Lista brakow zawiera obie usuniete metryki, posortowana.
    func testAllMissingKindsAreReported() {
        let samples = completeMaleSamples(at: anchor).filter {
            $0.kindRaw != MetricKind.neck.rawValue && $0.kindRaw != MetricKind.bodyFat.rawValue
        }
        guard case let .missing(kinds) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected missing") }

        XCTAssertEqual(kinds, [.bodyFat, .neck])
    }

    /// Co sprawdza: sourceDateRange obejmuje wylacznie probki faktycznie uzyte.
    /// Dlaczego: Pole opisuje userowi, z jakiego okresu pochodzi sylwetka; nieuzyta metryka nie ma prawa go rozciagac.
    /// Kryteria: Probki .bust (nieuzywana u mezczyzn) i .leanBodyMass na krancach okna nie zmieniaja zakresu.
    func testSourceDateRangeCoversOnlyUsedSamples() {
        var samples = completeMaleSamples(at: anchor)
        samples.append(MetricSample(kind: .bust, value: 95, date: day(-14)))
        samples.append(MetricSample(kind: .leanBodyMass, value: 65, date: day(14)))

        guard case let .success(snapshot) = BodySnapshotBuilder.build(
            samples: samples, anchorDate: anchor, gender: .male, age: 30, fallbackHeightCm: 0
        ) else { return XCTFail("Expected success") }

        XCTAssertEqual(snapshot.sourceDateRange.lowerBound, anchor)
        XCTAssertEqual(snapshot.sourceDateRange.upperBound, anchor)
    }
}
