/// Cel testow: Pilnuje, zeby testy zawsze dzialaly w tym samym jezyku i regionie (en_US), tak jak na CI.
/// Dlaczego to wazne: Daty i liczby w snapshotach zaleza od regionu; na polskim Macu wychodzilo "lis" zamiast "Nov", a baza nagrana na CI (en_US) nie pasowala lokalnie.
/// Kryteria zaliczenia: Locale.current to en_US niezaleznie od ustawien komputera.

import XCTest

final class TestEnvironmentTests: XCTestCase {
    func testTestsRunInTheEnglishUSLocale() {
        XCTAssertEqual(Locale.current.language.languageCode?.identifier, "en")
        XCTAssertEqual(Locale.current.region?.identifier, "US")
    }
}
