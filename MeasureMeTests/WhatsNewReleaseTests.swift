/// Cel testow: Pilnuje, ze kazdy klucz z katalogu wydan ma tlumaczenie w kazdym jezyku.
/// Dlaczego to wazne: LocalizationConsistencyTests skanuje wylacznie literaly w wywolaniach
///   AppLocalization.string(...). Klucze highlightow siedza w strukturze i trafiaja do bundla
///   przez zmienna, wiec zaden istniejacy test ich nie widzi — literowka w katalogu wyswietlilaby
///   uzytkownikowi goly klucz.
/// Kryteria zaliczenia: Kazdy tytul i opis rozwiazuje sie na cos innego niz wlasny klucz,
///   we wszystkich szesciu jezykach.

import XCTest
@testable import MeasureMe

final class WhatsNewReleaseTests: XCTestCase {

    private let languages: [AppLanguage] = [.en, .pl, .es, .de, .fr, .ptBR]

    /// Co sprawdza: Wszystkie klucze katalogu maja wpis w kazdym Localizable.strings.
    /// Dlaczego: `localizedString(forKey:value:)` zwraca klucz, gdy go nie ma — awaria jest cicha.
    /// Kryteria: Zaden klucz nie rozwiazuje sie do samego siebie.
    func testEveryCatalogueKeyIsTranslatedInEveryLanguage() {
        var missing: [String] = []

        for release in WhatsNewRelease.catalogue {
            for highlight in release.highlights {
                for key in [highlight.titleKey, highlight.messageKey] {
                    for language in languages {
                        let resolved = language.bundle.localizedString(forKey: key, value: key, table: nil)
                        if resolved == key {
                            missing.append("\(language.rawValue): \(key)")
                        }
                    }
                }
            }
        }

        XCTAssertTrue(missing.isEmpty, "Brak tlumaczen: \(missing.joined(separator: " | "))")
    }

    /// Co sprawdza: Stale klucze arkusza tez sa przetlumaczone.
    /// Dlaczego: Tytul, podtytul i oba przyciski nie przechodza przez katalog, ale lapie je
    ///   ta sama luka — sa wolane przez AppLocalization.string z literalem, wiec teoretycznie
    ///   pilnuje ich inny test; ten trzyma je razem z reszta arkusza.
    /// Kryteria: Zaden z czterech kluczy nie rozwiazuje sie do samego siebie.
    func testSheetChromeKeysAreTranslatedInEveryLanguage() {
        let keys = ["whatsNew.title", "whatsNew.subtitle", "whatsNew.action.open", "whatsNew.action.dismiss"]
        var missing: [String] = []

        for key in keys {
            for language in languages {
                let resolved = language.bundle.localizedString(forKey: key, value: key, table: nil)
                if resolved == key {
                    missing.append("\(language.rawValue): \(key)")
                }
            }
        }

        XCTAssertTrue(missing.isEmpty, "Brak tlumaczen: \(missing.joined(separator: " | "))")
    }

    /// Co sprawdza: Numery wersji w katalogu sa unikalne.
    /// Dlaczego: `release(for:)` bierze pierwszy pasujacy wpis, wiec duplikat po cichu
    ///   przykrylby ten drugi przy nastepnym wydaniu.
    /// Kryteria: Liczba unikalnych wersji rowna liczbie wpisow.
    func testCatalogueVersionsAreUnique() {
        let versions = WhatsNewRelease.catalogue.map(\.version)

        XCTAssertEqual(Set(versions).count, versions.count)
    }

    /// Co sprawdza: Kazde wydanie ma przynajmniej jeden highlight.
    /// Dlaczego: Pusty wpis otworzylby arkusz bez tresci — gorzej niz nieotwarcie go wcale.
    /// Kryteria: Zadna lista highlightow nie jest pusta.
    func testEveryReleaseHasHighlights() {
        for release in WhatsNewRelease.catalogue {
            XCTAssertFalse(release.highlights.isEmpty, "Wydanie \(release.version) nie ma highlightow")
        }
    }
}
