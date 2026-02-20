/// Cel testow: Sprawdza logike pierwszego uruchomienia Quick Add (np. widocznosc miarki/rulera).
/// Dlaczego to wazne: Pierwszy zapis jest krytyczny dla retencji i poprawnosci danych.
/// Kryteria zaliczenia: UI/logika reaguje poprawnie na brak lub obecne dane historyczne.

import XCTest
@testable import MeasureMe

final class QuickAddFirstTimeFlowTests: XCTestCase {

    // MARK: - shouldShowRuler

    /// Co sprawdza: Sprawdza scenariusz: ShouldShowRulerFalseWhenNoLatestAndNoInput.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testShouldShowRulerFalseWhenNoLatestAndNoInput() {
        // Pierwszy uzytkownik bez wpisanej wartosci -> miarka ukryta
        XCTAssertFalse(
            QuickAddMath.shouldShowRuler(hasLatest: false, currentInput: nil),
            "Miarka powinna byc ukryta, gdy nie ma historii i brak wpisu uzytkownika"
        )
    }

    /// Co sprawdza: Sprawdza scenariusz: ShouldShowRulerTrueWhenHasLatest.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testShouldShowRulerTrueWhenHasLatest() {
        // Powracajacy uzytkownik z poprzednim pomiarem -> miarka widoczna
        XCTAssertTrue(
            QuickAddMath.shouldShowRuler(hasLatest: true, currentInput: nil),
            "Miarka powinna byc widoczna, gdy istnieje poprzedni pomiar"
        )
    }

    /// Co sprawdza: Sprawdza scenariusz: ShouldShowRulerTrueWhenUserTypedValue.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testShouldShowRulerTrueWhenUserTypedValue() {
        // Pierwszy uzytkownik po wpisaniu wartosci -> miarka sie pojawia
        XCTAssertTrue(
            QuickAddMath.shouldShowRuler(hasLatest: false, currentInput: 80.0),
            "Miarka powinna sie pojawic po wpisaniu pierwszej wartosci"
        )
    }

    /// Co sprawdza: Sprawdza scenariusz: ShouldShowRulerTrueWhenBothExist.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testShouldShowRulerTrueWhenBothExist() {
        // Powracajacy uzytkownik po wpisaniu nowej wartosci -> miarka pozostaje widoczna
        XCTAssertTrue(
            QuickAddMath.shouldShowRuler(hasLatest: true, currentInput: 85.0),
            "Miarka powinna pozostac widoczna, gdy istnieje historia i wpis uzytkownika"
        )
    }
}
