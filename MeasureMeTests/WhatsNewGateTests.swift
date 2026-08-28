/// Cel testow: Sprawdza, kiedy arkusz „Co nowego” ma sie otworzyc po aktualizacji.
/// Dlaczego to wazne: Decyzja siedzi w czystej funkcji wlasnie dlatego, ze zapis do @State
///   na niezainstalowanym widoku znika — test na RootView przechodzilby pusto.
/// Kryteria zaliczenia: Swiezy start tylko stempluje, aktualizacja pokazuje notatki,
///   ta sama wersja nie pokazuje nic, a wersja bez wpisu w katalogu tylko stempluje.

import XCTest
@testable import MeasureMe

final class WhatsNewGateTests: XCTestCase {

    /// Wersja, ktora na pewno jest w katalogu — test nie ma sie sypac przy podbiciu numeru appki.
    private var catalogueVersion: String {
        WhatsNewRelease.catalogue.first?.version ?? ""
    }

    /// Co sprawdza: Swieza instalacja nie dostaje notatek o wydaniu.
    /// Dlaczego: Uzytkownik wlasnie przeszedl onboarding; „co dodalismy” nie znaczy dla niego nic.
    /// Kryteria: Decyzja to .stampOnly z biezaca wersja.
    func testFreshInstallOnlyStamps() {
        let decision = WhatsNewGate.decide(
            currentVersion: catalogueVersion,
            lastSeenVersion: "",
            hasCompletedOnboarding: false
        )

        XCTAssertEqual(decision, .stampOnly(version: catalogueVersion))
    }

    /// Co sprawdza: Uzytkownik z poprzedniej wersji dostaje arkusz.
    /// Dlaczego: To jedyny przypadek, dla ktorego ta funkcja istnieje.
    /// Kryteria: Decyzja to .present z wpisem katalogu dla biezacej wersji.
    func testUpgradePresentsRelease() throws {
        let expected = try XCTUnwrap(WhatsNewRelease.release(for: catalogueVersion))

        let decision = WhatsNewGate.decide(
            currentVersion: catalogueVersion,
            lastSeenVersion: "1.5.3",
            hasCompletedOnboarding: true
        )

        XCTAssertEqual(decision, .present(expected))
    }

    /// Co sprawdza: Istniejacy uzytkownik bez zapisanego klucza tez dostaje arkusz.
    /// Dlaczego: Klucz nie istnial przed tym wydaniem, wiec pusty ciag to nie to samo co swieza instalacja —
    ///   rozroznia je dopiero ukonczony onboarding.
    /// Kryteria: Decyzja to .present mimo pustego lastSeenVersion.
    func testExistingUserWithNoStoredVersionPresents() throws {
        let expected = try XCTUnwrap(WhatsNewRelease.release(for: catalogueVersion))

        let decision = WhatsNewGate.decide(
            currentVersion: catalogueVersion,
            lastSeenVersion: "",
            hasCompletedOnboarding: true
        )

        XCTAssertEqual(decision, .present(expected))
    }

    /// Co sprawdza: Drugie uruchomienie tej samej wersji nie pokazuje nic i nie rusza zapisu.
    /// Dlaczego: Arkusz raz na wydanie; powtorka jest gorsza niz jego brak.
    /// Kryteria: Decyzja to .none.
    func testSameVersionShowsNothing() {
        let decision = WhatsNewGate.decide(
            currentVersion: catalogueVersion,
            lastSeenVersion: catalogueVersion,
            hasCompletedOnboarding: true
        )

        XCTAssertEqual(decision, .none)
    }

    /// Co sprawdza: Wydanie bez wpisu w katalogu tylko stempluje wersje.
    /// Dlaczego: Wydanie z samymi poprawkami nie ma o czym opowiadac, ale nie moze tez zostawic
    ///   starej wersji w zapisie — inaczej nastepne wydanie porownaloby sie z nia zamiast z ta.
    /// Kryteria: Decyzja to .stampOnly z ta wersja.
    func testVersionWithoutCatalogueEntryOnlyStamps() {
        let decision = WhatsNewGate.decide(
            currentVersion: "9.9.9",
            lastSeenVersion: "1.5.3",
            hasCompletedOnboarding: true
        )

        XCTAssertEqual(decision, .stampOnly(version: "9.9.9"))
    }

    /// Co sprawdza: Pusta wersja bundle'a nie wywoluje niczego.
    /// Dlaczego: Host testow jednostkowych nie ma CFBundleShortVersionString; zapisanie "" jako
    ///   „widzianej wersji” zamaskowaloby prawdziwa aktualizacje.
    /// Kryteria: Decyzja to .none.
    func testEmptyCurrentVersionDoesNothing() {
        let decision = WhatsNewGate.decide(
            currentVersion: "",
            lastSeenVersion: "",
            hasCompletedOnboarding: true
        )

        XCTAssertEqual(decision, .none)
    }
}
