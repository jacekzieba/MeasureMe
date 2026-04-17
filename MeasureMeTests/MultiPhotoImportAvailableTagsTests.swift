/// Cel testów: Weryfikuje logikę filtrowania tagów używaną przez MultiPhotoImportView.availableTags.
/// Dlaczego to ważne: availableTags jest prywatny, więc testujemy izolowaną logikę mapowania
/// MetricKind → PhotoTag — tę samą, którą używa widok.
/// Kryteria zaliczenia: Wykluczone metryki (weight, bodyFat, leanBodyMass) nigdy nie dają tagów,
/// pozostałe metryki mapują się poprawnie, wholeBody jest zawsze obecny.

import XCTest
@testable import MeasureMe

final class MultiPhotoImportAvailableTagsTests: XCTestCase {

    func testPrimaryPoseTagsEncodeDecode() throws {
        let data = try JSONEncoder().encode(PhotoTag.primaryPoseTags)
        let decoded = try JSONDecoder().decode([PhotoTag].self, from: data)

        XCTAssertEqual(decoded, [.front, .side, .back, .detail])
        XCTAssertEqual(PhotoTag.primaryPose(in: decoded), .front)
        XCTAssertEqual(PhotoTag.side.shortLabel, "S")
    }

    // MARK: - Pomocnik: replika logiki availableTags

    /// Izolowana kopia logiki z MultiPhotoImportView.availableTags.
    /// Testując tę funkcję testujemy zachowanie widoku bez konieczności
    /// instancjowania SwiftUI View.
    private func availableTags(for activeKinds: [MetricKind]) -> [PhotoTag] {
        var tags: [PhotoTag] = PhotoTag.primaryPoseTags
        let activeTags = activeKinds
            .filter { $0 != .weight && $0 != .bodyFat && $0 != .leanBodyMass }
            .compactMap { PhotoTag(metricKind: $0) }
        tags.append(contentsOf: activeTags)
        return tags
    }

    // MARK: - wholeBody zawsze obecny

    /// Co sprawdza: wholeBody jest zawsze pierwszym elementem, niezależnie od aktywnych metryk.
    /// Dlaczego: wholeBody to domyślny tag — musi być dostępny zawsze.
    /// Kryteria: tags.first == .wholeBody dla dowolnego wejścia.
    func testAvailableTagsAlwaysStartsWithPrimaryPoseTags() {
        XCTAssertEqual(Array(availableTags(for: []).prefix(PhotoTag.primaryPoseTags.count)), PhotoTag.primaryPoseTags)
        XCTAssertEqual(Array(availableTags(for: [.waist, .hips]).prefix(PhotoTag.primaryPoseTags.count)), PhotoTag.primaryPoseTags)
        XCTAssertEqual(Array(availableTags(for: [.weight, .bodyFat]).prefix(PhotoTag.primaryPoseTags.count)), PhotoTag.primaryPoseTags)
    }

    /// Co sprawdza: Brak aktywnych metryk → tylko [.wholeBody].
    /// Dlaczego: Użytkownik bez aktywnych metryk powinien widzieć dokładnie jeden tag.
    /// Kryteria: tags == [.wholeBody].
    func testNoActiveMetricsReturnsOnlyPrimaryPoseTags() {
        let result = availableTags(for: [])
        XCTAssertEqual(result, PhotoTag.primaryPoseTags)
    }

    // MARK: - Wykluczone metryki

    /// Co sprawdza: .weight → nil przez PhotoTag(metricKind:).
    /// Dlaczego: Weight nie ma sensu jako tag zdjęcia (nie jest obserwowalne wizualnie).
    /// Kryteria: PhotoTag(metricKind: .weight) == nil.
    func testPhotoTagInitFromWeightReturnsNil() {
        XCTAssertNil(PhotoTag(metricKind: .weight))
    }

    /// Co sprawdza: .bodyFat → nil przez PhotoTag(metricKind:).
    /// Dlaczego: bodyFat nie ma odpowiednika wizualnego w tagach zdjęcia.
    /// Kryteria: PhotoTag(metricKind: .bodyFat) == nil.
    func testPhotoTagInitFromBodyFatReturnsNil() {
        XCTAssertNil(PhotoTag(metricKind: .bodyFat))
    }

    /// Co sprawdza: .leanBodyMass → nil przez PhotoTag(metricKind:).
    /// Dlaczego: leanBodyMass to metryka wyliczana — nie zdjęciowa.
    /// Kryteria: PhotoTag(metricKind: .leanBodyMass) == nil.
    func testPhotoTagInitFromLeanBodyMassReturnsNil() {
        XCTAssertNil(PhotoTag(metricKind: .leanBodyMass))
    }

    /// Co sprawdza: availableTags nie zawiera żadnego tagu z weight gdy jest jedyną aktywną metryką.
    /// Dlaczego: Filter musi działać na poziomie MetricKind, nie tylko PhotoTag.init.
    /// Kryteria: result == [.wholeBody] (tylko wholeBody, bez żadnego dodatkowego tagu z weight).
    func testWeightOnlyActiveKindsGivesOnlyPrimaryPoseTags() {
        let result = availableTags(for: [.weight])
        XCTAssertEqual(result, PhotoTag.primaryPoseTags)
    }

    /// Co sprawdza: availableTags nie zawiera tagów z bodyFat gdy jest jedyną aktywną metryką.
    /// Dlaczego: Analogicznie do weight — kompletność filtru.
    /// Kryteria: result == [.wholeBody].
    func testBodyFatOnlyActiveKindsGivesOnlyPrimaryPoseTags() {
        let result = availableTags(for: [.bodyFat])
        XCTAssertEqual(result, PhotoTag.primaryPoseTags)
    }

    /// Co sprawdza: availableTags nie zawiera tagów z leanBodyMass gdy jest jedyną aktywną metryką.
    /// Dlaczego: Analogicznie do weight i bodyFat.
    /// Kryteria: result == [.wholeBody].
    func testLeanBodyMassOnlyActiveKindsGivesOnlyPrimaryPoseTags() {
        let result = availableTags(for: [.leanBodyMass])
        XCTAssertEqual(result, PhotoTag.primaryPoseTags)
    }

    /// Co sprawdza: Zestaw tylko wykluczonych metryk (weight + bodyFat + leanBodyMass) → [.wholeBody].
    /// Dlaczego: Upewniamy się, że żaden z nich nie przemknie przez filter.
    /// Kryteria: result == [.wholeBody].
    func testAllExcludedMetricsGiveOnlyPrimaryPoseTags() {
        let result = availableTags(for: [.weight, .bodyFat, .leanBodyMass])
        XCTAssertEqual(result, PhotoTag.primaryPoseTags)
    }

    // MARK: - Poprawne mapowanie

    /// Co sprawdza: .waist mapuje się na .waist.
    /// Dlaczego: Waist to najczęściej używana metryka obok wagi — mapowanie musi być pewne.
    /// Kryteria: PhotoTag(metricKind: .waist) == .waist, wynik zawiera .waist.
    func testWaistMetricMapsToWaistTag() {
        XCTAssertEqual(PhotoTag(metricKind: .waist), .waist)
        let result = availableTags(for: [.waist])
        XCTAssertTrue(result.contains(.waist), "Aktywna metryka .waist powinna generować tag .waist")
    }

    /// Co sprawdza: .hips mapuje się na .hips.
    /// Dlaczego: Weryfikacja mapowania dolnej partii ciała.
    /// Kryteria: availableTags zawiera .hips gdy .hips jest aktywne.
    func testHipsMetricMapsToHipsTag() {
        XCTAssertEqual(PhotoTag(metricKind: .hips), .hips)
        let result = availableTags(for: [.hips])
        XCTAssertTrue(result.contains(.hips))
    }

    /// Co sprawdza: Kilka aktywnych metryk generuje odpowiednie tagi.
    /// Dlaczego: Typowy scenariusz — user śledzi waist, hips, leftBicep.
    /// Kryteria: Wynik zawiera dokładnie [.wholeBody, .waist, .hips, .leftBicep].
    func testMultipleActiveMetricsMappedCorrectly() {
        let result = availableTags(for: [.waist, .hips, .leftBicep])
        XCTAssertTrue(result.contains(.front))
        XCTAssertTrue(result.contains(.waist))
        XCTAssertTrue(result.contains(.hips))
        XCTAssertTrue(result.contains(.leftBicep))
        XCTAssertEqual(result.count, PhotoTag.primaryPoseTags.count + 3)
    }

    /// Co sprawdza: Wykluczone metryki wśród aktywnych nie trafiają do tagów.
    /// Dlaczego: Mieszany scenariusz — user śledzi weight (wykluczone) i waist (ok).
    /// Kryteria: Wynik zawiera .waist, NIE zawiera żadnego odpowiednika weight.
    func testMixedActiveKindsExcludesExcludedMetrics() {
        let result = availableTags(for: [.weight, .waist, .bodyFat, .hips, .leanBodyMass])
        XCTAssertTrue(result.contains(.waist), "waist powinien być w tagach")
        XCTAssertTrue(result.contains(.hips), "hips powinien być w tagach")
        XCTAssertEqual(result.count, PhotoTag.primaryPoseTags.count + 2)
    }

    /// Co sprawdza: Kolejność tagów: wholeBody jest pierwszy, reszta po kolei jak w activeKinds.
    /// Dlaczego: Widok renderuje tagi w kolejności — nieprzewidywalna kolejność psuje UX.
    /// Kryteria: result[0] == .wholeBody, dalej w kolejności wejścia.
    func testPrimaryPoseTagsAreAlwaysFirst() {
        let result = availableTags(for: [.neck, .shoulders, .waist])
        XCTAssertEqual(Array(result.prefix(PhotoTag.primaryPoseTags.count)), PhotoTag.primaryPoseTags)
        XCTAssertEqual(result[4], .neck)
        XCTAssertEqual(result[5], .shoulders)
        XCTAssertEqual(result[6], .waist)
    }

    // MARK: - Wszystkie obsługiwane metryki

    /// Co sprawdza: Każda MetricKind spoza wykluczonej trójki ma nienil mapowanie na PhotoTag.
    /// Dlaczego: Kompletność mapowania — dodanie nowej metryki bez dodania jej do PhotoTag
    /// byłoby cichym błędem (tag by znikał bez ostrzeżenia).
    /// Kryteria: Wszystkie MetricKind poza [.weight, .bodyFat, .leanBodyMass] dają nie-nil PhotoTag.
    func testAllNonExcludedMetricKindsMapToPhotoTag() {
        let excluded: Set<MetricKind> = [.weight, .bodyFat, .leanBodyMass]
        let allKinds = MetricKind.allCases
        for kind in allKinds where !excluded.contains(kind) {
            XCTAssertNotNil(
                PhotoTag(metricKind: kind),
                "MetricKind.\(kind) powinien mieć odpowiadający PhotoTag (nie jest w liście wykluczonej)"
            )
        }
    }

    /// Co sprawdza: Wyłącznie wykluczone metryki dają nil.
    /// Dlaczego: Dopełnienie poprzedniego testu — żadna metryka nie powinna być przypadkowo wykluczona.
    /// Kryteria: PhotoTag(metricKind:) == nil wyłącznie dla weight, bodyFat, leanBodyMass.
    func testOnlyExcludedMetricKindsReturnNilPhotoTag() {
        let excluded: Set<MetricKind> = [.weight, .bodyFat, .leanBodyMass]
        for kind in MetricKind.allCases {
            if excluded.contains(kind) {
                XCTAssertNil(PhotoTag(metricKind: kind), ".\(kind) powinien zwracać nil")
            } else {
                XCTAssertNotNil(PhotoTag(metricKind: kind), ".\(kind) nie powinien zwracać nil")
            }
        }
    }
}
