/// Cel testow: Sprawdza mapowanie brakujacych metryk na wiersze listy i na metryki arkusza QuickAdd.
/// Dlaczego to wazne: Builder zglasza tylko lewa strone pary; ekran musi pokazac neutralna nazwe,
///   a arkusz zaoferowac obie strony.
/// Kryteria zaliczenia: Pary zwijaja sie w liscie i rozwijaja w arkuszu, metryki pojedyncze przechodza 1:1.

import XCTest
@testable import MeasureMe

@MainActor
final class BodyModelMissingMetricsTests: XCTestCase {

    /// Co sprawdza: Lewa strona pary daje jeden wiersz z neutralnym identyfikatorem czesci ciala.
    /// Dlaczego: Model usrednia lewa i prawa, wiec nazwanie strony twierdziloby cos, czego model nie widzial.
    /// Kryteria: Dla .leftBicep powstaje dokladnie jeden wiersz o id "bodyModel.site.bicep".
    func testPairCollapsesToNeutralRow() {
        let rows = BodyModelMissingMetrics.rows(for: [.leftBicep])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "bodyModel.site.bicep")
        XCTAssertEqual(rows.first?.systemImage, MetricKind.leftBicep.systemImage)
    }

    /// Co sprawdza: Wszystkie cztery pary zwijaja sie do neutralnych nazw.
    /// Dlaczego: Regresja na jednej parze byla latwa do przeoczenia przy tescie tylko bicepsa.
    /// Kryteria: Cztery lewe strony daja cztery wiersze o kluczach BodyMeasurementSite.
    func testEveryPairCollapses() {
        let rows = BodyModelMissingMetrics.rows(for: [.leftBicep, .leftForearm, .leftThigh, .leftCalf])

        XCTAssertEqual(rows.map(\.id), [
            "bodyModel.site.bicep",
            "bodyModel.site.forearm",
            "bodyModel.site.thigh",
            "bodyModel.site.calf"
        ])
    }

    /// Co sprawdza: Metryki pojedyncze przechodza bez zmian i zachowuja kolejnosc wejscia.
    /// Dlaczego: Builder sortuje braki wg MetricKind.allCases i ta kolejnosc ma dotrzec do UI.
    /// Kryteria: id to rawValue metryki, kolejnosc zgodna z wejsciem.
    func testSingleKindsPassThroughInOrder() {
        let rows = BodyModelMissingMetrics.rows(for: [.height, .weight, .neck])

        XCTAssertEqual(rows.map(\.id), [
            MetricKind.height.rawValue,
            MetricKind.weight.rawValue,
            MetricKind.neck.rawValue
        ])
    }

    /// Co sprawdza: Wiersz ma niepusty tytul rozny od wlasnego id.
    /// Dlaczego: AppLocalization.string zwraca klucz, gdy tlumaczenia brakuje — to by przeciekło do UI.
    /// Kryteria: Tytul jest niepusty i nie jest surowym kluczem.
    func testRowTitleIsLocalizedNotARawKey() {
        let rows = BodyModelMissingMetrics.rows(for: [.leftBicep, .neck])

        for row in rows {
            XCTAssertFalse(row.title.isEmpty, "Row \(row.id) has an empty title")
            XCTAssertNotEqual(row.title, row.id, "Row \(row.id) leaked its key as the title")
        }
    }

    /// Co sprawdza: Arkusz QuickAdd dostaje obie strony kazdej pary.
    /// Dlaczego: Builder zglasza lewa strone tylko wtedy, gdy obie sa puste, wiec obie mozna zaoferowac.
    /// Kryteria: .leftThigh rozwija sie do [.leftThigh, .rightThigh].
    func testQuickAddKindsExpandPairs() {
        let kinds = BodyModelMissingMetrics.quickAddKinds(for: [.leftThigh])

        XCTAssertEqual(kinds, [.leftThigh, .rightThigh])
    }

    /// Co sprawdza: Metryki pojedyncze nie sa duplikowane przy rozwijaniu.
    /// Dlaczego: Blad w flatMap latwo podwaja wszystko, nie tylko pary.
    /// Kryteria: Mieszane wejscie daje dokladnie oczekiwana liste.
    func testQuickAddKindsLeaveSingleKindsAlone() {
        let kinds = BodyModelMissingMetrics.quickAddKinds(for: [.waist, .leftCalf, .hips])

        XCTAssertEqual(kinds, [.waist, .leftCalf, .rightCalf, .hips])
    }

    /// Co sprawdza: Zaden wiersz nie zdradza strony ciala dla zadnej z plci.
    /// Dlaczego: BodySnapshotBuilder ma wlasna, prywatna tabele par. Gdyby doszla piata para,
    ///   karta pokazalaby "Lewy X", a arkusz zaoferowalby tylko lewa strone — i zaden test by nie padl.
    ///   `requiredKinds(for:)` zwraca obie strony kazdej pary naraz, co `build()` nigdy nie zglasza
    ///   jako "missing" (raportuje tylko lewa strone) — wiec test odtwarza prawdziwa sciezke przez
    ///   `build()` z pustymi probkami zamiast karmic `rows(for:)` ksztaltem, jakiego produkcja nie da.
    /// Kryteria: Dla listy brakujacych metryk obu plci zaden Row.id nie jest rawValue metryki
    ///   z lewa/prawa strona.
    func testNoRowExposesASideForEitherGender() {
        let sidedIds = Set(
            MetricKind.allCases
                .filter { $0.rawValue.hasPrefix("left") || $0.rawValue.hasPrefix("right") }
                .map(\.rawValue)
        )

        for gender in [BodyGender.male, .female] {
            guard case let .missing(missingKinds) = BodySnapshotBuilder.build(
                samples: [],
                anchorDate: Date(),
                gender: gender,
                age: 30,
                fallbackHeightCm: 0
            ) else {
                XCTFail("Expected .missing with no samples for \(gender)")
                continue
            }

            let rows = BodyModelMissingMetrics.rows(for: missingKinds)
            let leaked = rows.map(\.id).filter { sidedIds.contains($0) }
            XCTAssertTrue(leaked.isEmpty, "\(gender) leaked sided rows: \(leaked)")
        }
    }
}
