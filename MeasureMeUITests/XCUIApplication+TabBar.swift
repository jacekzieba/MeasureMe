import XCTest

/// Dostęp do paska zakładek dla testów UI.
///
/// Od iOS 26 pasek rysuje FabBar (`UISegmentedControl` + odczepiony przycisk „+” w jednym
/// `UIGlassContainerEffect`), a nie systemowy `UITabBar`. Skutki dla testów:
/// - `app.tabBars` jest puste — pasek zgłasza się jako `segmentedControl`,
/// - segmenty i „+” nie mają identyfikatorów, wystawiają tylko etykiety, więc dawne
///   identyfikatory `tab.*` mapujemy tutaj na etykiety zamiast rozsypywać je po testach.
///
/// Przy regular width FabBara nie ma, a pasek jest systemowy — wtedy te same etykiety szukamy
/// w `app.tabBars`. Na iPhonie Duo systemowy pasek stoi pionowo i zgłasza się jako część
/// `toolbar`, nie `tabBar`. Który z tych przypadków zachodzi, mówi marker układu aplikacji.
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
        // From iOS 26 the app reports its layout (`uitest.layout.<regular|compact>.<verticalBars|bottomBar>`).
        // Trusting it avoids picking a segmented control from the screen's content (e.g. a chart range
        // picker) as the FabBar, and does not depend on the app language.
        let marker = descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'uitest.layout.'"))
            .firstMatch
        if marker.exists {
            let layout = marker.identifier
            if layout.hasSuffix(".verticalBars") {
                return toolbars
            }
            return layout.contains(".regular.") ? tabBars : segmentedControls
        }
        if !segmentedControls.firstMatch.exists {
            if tabBars.firstMatch.exists {
                return tabBars
            }
            if toolbars.buttons["Home"].exists {
                return toolbars
            }
        }
        return segmentedControls
    }
}
