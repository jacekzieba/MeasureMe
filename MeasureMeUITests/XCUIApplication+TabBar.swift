import XCTest

/// Dostęp do paska zakładek dla testów UI.
///
/// Od iOS 26 pasek rysuje FabBar (`UISegmentedControl` + odczepiony przycisk „+” w jednym
/// `UIGlassContainerEffect`), a nie systemowy `UITabBar`. Skutki dla testów:
/// - `app.tabBars` jest puste — pasek zgłasza się jako `segmentedControl`,
/// - segmenty i „+” nie mają identyfikatorów, wystawiają tylko etykiety, więc dawne
///   identyfikatory `tab.*` mapujemy tutaj na etykiety zamiast rozsypywać je po testach.
extension XCUIApplication {
    /// Pasek zakładek jako element (dawniej `app.tabBars` + `firstMatch`).
    var appTabBar: XCUIElement {
        segmentedControls.firstMatch
    }

    /// Przycisk zakładki po dawnym identyfikatorze, np. `tab.home` albo `tab.add`.
    func tabButton(_ identifier: String) -> XCUIElement {
        switch identifier {
        case "tab.home":
            return segmentedControls.buttons["Home"].firstMatch
        case "tab.measurements":
            return segmentedControls.buttons["Measurements"].firstMatch
        case "tab.photos":
            return segmentedControls.buttons["Photos"].firstMatch
        case "tab.settings":
            return segmentedControls.buttons["Settings"].firstMatch
        case "tab.add":
            // „+” jest rodzeństwem segmentów, poza kontrolką — stąd zapytanie po całej aplikacji.
            return buttons["Add"].firstMatch
        default:
            return buttons[identifier].firstMatch
        }
    }
}
