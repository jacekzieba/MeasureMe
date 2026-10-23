import XCTest

/// Dostęp do paska zakładek dla testów UI.
///
/// Od iOS 26 pasek rysuje FabBar (`UISegmentedControl` + odczepiony przycisk „+” w jednym
/// `UIGlassContainerEffect`), a nie systemowy `UITabBar`. Skutki dla testów:
/// - `app.tabBars` jest puste — pasek zgłasza się jako `segmentedControl`,
/// - segmenty i „+” nie mają identyfikatorów, wystawiają tylko etykiety, więc dawne
///   identyfikatory `tab.*` mapujemy tutaj na etykiety zamiast rozsypywać je po testach.
///
/// Na iPhonie Duo (pionowe paski) i przy regular width FabBara nie ma, a pasek jest systemowy —
/// wtedy te same etykiety szukamy w `app.tabBars`.
extension XCUIApplication {
    /// Pasek zakładek jako element (dawniej `app.tabBars` + `firstMatch`).
    var appTabBar: XCUIElement {
        tabBarContainer.firstMatch
    }

    /// Przycisk zakładki po dawnym identyfikatorze, np. `tab.home` albo `tab.add`.
    func tabButton(_ identifier: String) -> XCUIElement {
        switch identifier {
        case "tab.home":
            return tabBarContainer.buttons["Home"].firstMatch
        case "tab.measurements":
            return tabBarContainer.buttons["Measurements"].firstMatch
        case "tab.photos":
            return tabBarContainer.buttons["Photos"].firstMatch
        case "tab.settings":
            return tabBarContainer.buttons["Settings"].firstMatch
        case "tab.add":
            // „+” jest rodzeństwem segmentów, poza kontrolką — stąd zapytanie po całej aplikacji.
            return buttons["Add"].firstMatch
        default:
            return buttons[identifier].firstMatch
        }
    }

    private var tabBarContainer: XCUIElementQuery {
        if !segmentedControls.firstMatch.exists && tabBars.firstMatch.exists {
            return tabBars
        }
        return segmentedControls
    }
}
