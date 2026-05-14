/// Cel testów: Weryfikuje zarządzanie aktywnymi i kluczowymi metrykami w UserDefaults.
/// Dlaczego to ważne: ActiveMetricsStore steruje widoczną zawartością Home i Settings;
/// błędy mogą skutkować znikaniem lub duplikacją metryk.
/// Kryteria zaliczenia: Każdy stan UserDefaults daje przewidywalny wynik bez efektów ubocznych.

import XCTest
@testable import MeasureMe

@MainActor
final class ActiveMetricsStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Tworzy izolowaną parę (store, settings) z czystymi UserDefaults.
    private func makeStore(
        suffix: String = UUID().uuidString
    ) -> (store: ActiveMetricsStore, settings: AppSettingsStore) {
        let suiteName = "ActiveMetricsStoreTests.\(suffix)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let settings = AppSettingsStore(defaults: ud)
        let store = ActiveMetricsStore(settings: settings)
        return (store, settings)
    }

    /// Metryki włączone domyślnie przez AppSettingsSnapshot.registeredDefaults.
    private let registeredEnabledByDefault: Set<MetricKind> = [.weight, .bodyFat, .leanBodyMass, .waist]

    /// Jawnie wyłącza wszystkie metryki — przydatne w testach potrzebujących czystego stanu.
    private func disableAll(store: ActiveMetricsStore) {
        MetricKind.allCases.forEach { store.setEnabled(false, for: $0) }
    }

    // MARK: - Enable / Disable

    /// Co sprawdza: Cztery metryki są domyślnie włączone przez registeredDefaults (weight, bodyFat, leanBodyMass, waist).
    /// Dlaczego: Dobry UX pierwszego użycia — użytkownik widzi sensowne metryki od razu po instalacji.
    /// Kryteria: Dokładnie te 4 są enabled; pozostałe 14 — disabled.
    func testRegisteredDefaultsEnableFourMetrics() {
        let (store, _) = makeStore()
        for kind in MetricKind.allCases {
            if registeredEnabledByDefault.contains(kind) {
                XCTAssertTrue(store.isEnabled(kind), "\(kind.rawValue) powinno być domyślnie włączone")
            } else {
                XCTAssertFalse(store.isEnabled(kind), "\(kind.rawValue) powinno być domyślnie wyłączone")
            }
        }
        XCTAssertEqual(store.activeKinds.count, 4)
    }

    /// Co sprawdza: setEnabled(true) powoduje pojawienie się metryki w activeKinds.
    /// Dlaczego: Podstawowy kontrakt store; włączenie = widoczność w UI.
    /// Kryteria: isEnabled(weight) == true i activeKinds zawiera .weight.
    func testSetEnabledTrueAddsToActiveKinds() {
        let (store, _) = makeStore()
        store.setEnabled(true, for: .weight)
        XCTAssertTrue(store.isEnabled(.weight))
        XCTAssertTrue(store.activeKinds.contains(.weight))
    }

    /// Co sprawdza: setEnabled(false) usuwa metrykę z activeKinds.
    /// Dlaczego: Wyłączenie musi być natychmiast odzwierciedlone.
    /// Kryteria: activeKinds nie zawiera .weight po wyłączeniu.
    func testSetEnabledFalseRemovesFromActiveKinds() {
        let (store, _) = makeStore()
        store.setEnabled(true, for: .weight)
        store.setEnabled(false, for: .weight)
        XCTAssertFalse(store.isEnabled(.weight))
        XCTAssertFalse(store.activeKinds.contains(.weight))
    }

    /// Co sprawdza: Wielokrotne wywołanie setEnabled(true) nie duplikuje metryki.
    /// Dlaczego: Guard w setEnabled sprawdza aktualny stan; idempotentność jest wymagana.
    /// Kryteria: .waist pojawia się w activeKinds dokładnie raz.
    func testSetEnabledIsIdempotent() {
        let (store, _) = makeStore()
        store.setEnabled(true, for: .waist)
        store.setEnabled(true, for: .waist)
        XCTAssertEqual(store.activeKinds.filter { $0 == .waist }.count, 1)
    }

    // MARK: - activeKinds

    /// Co sprawdza: Po jawnym wyłączeniu wszystkich metryk activeKinds jest puste.
    /// Dlaczego: setEnabled(false) musi nadpisać registered defaults i dać czysty stan.
    /// Kryteria: activeKinds.isEmpty == true po disableAll.
    func testActiveKindsEmptyAfterDisablingAll() {
        let (store, _) = makeStore()
        disableAll(store: store)
        XCTAssertTrue(store.activeKinds.isEmpty)
    }

    /// Co sprawdza: activeKinds zawiera wszystkie i tylko włączone metryki.
    /// Dlaczego: Filtrowanie musi być precyzyjne — brak fałszywych pozytywów/negatywów.
    /// Kryteria: Po disableAll + włączeniu 3, count == 3, wszystkie obecne.
    func testActiveKindsContainsExactlyEnabledMetrics() {
        let (store, _) = makeStore()
        disableAll(store: store)
        store.setEnabled(true, for: .neck)
        store.setEnabled(true, for: .hips)
        store.setEnabled(true, for: .leftCalf)
        let active = store.activeKinds
        XCTAssertEqual(active.count, 3)
        XCTAssertTrue(active.contains(.neck))
        XCTAssertTrue(active.contains(.hips))
        XCTAssertTrue(active.contains(.leftCalf))
    }

    /// Co sprawdza: moveActiveKinds zmienia kolejność i jest trwałe.
    /// Dlaczego: Drag & drop w Settings musi być persist-owany.
    /// Kryteria: Po disableAll + włączeniu 3 + przesunięciu indeksu 0 na koniec, kolejność się zmienia.
    func testMoveActiveKindsChangesOrder() {
        let (store, _) = makeStore()
        disableAll(store: store)
        // Użyj metryk spoza registered defaults żeby mieć kontrolę nad stanem
        store.setEnabled(true, for: .neck)
        store.setEnabled(true, for: .hips)
        store.setEnabled(true, for: .leftCalf)
        // Kolejność po włączeniu (insertion order): [neck, hips, leftCalf]
        // Przesuń neck (index 0) na koniec (toOffset: 3)
        store.moveActiveKinds(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        let active = store.activeKinds
        XCTAssertEqual(active.first, .hips)
        XCTAssertEqual(active.last, .neck)
    }

    /// Co sprawdza: Zduplikowane wpisy w metrics_active_order są deduplikowane.
    /// Dlaczego: Uszkodzone UserDefaults nie mogą powodować duplikatów w UI.
    /// Kryteria: .weight pojawia się w activeKinds dokładnie raz, mimo 3 wpisów w kluczu.
    func testActiveKindsDeduplicatesCorruptedOrder() {
        let (store, settings) = makeStore()
        store.setEnabled(true, for: .weight)
        // Symuluj uszkodzone dane w UserDefaults
        settings.set(["weight", "weight", "weight"], forKey: "metrics_active_order")
        XCTAssertEqual(store.activeKinds.filter { $0 == .weight }.count, 1)
    }

    /// Co sprawdza: Nieznane raw value w metrics_active_order jest cicho ignorowane.
    /// Dlaczego: compactMap filtruje nieznane case'y; migracje enum nie crashują.
    /// Kryteria: activeKinds zawiera .weight, ale nie zawiera "nonExistentMetric".
    func testUnknownRawValueInOrderIsSilentlyDropped() {
        let (store, settings) = makeStore()
        store.setEnabled(true, for: .weight)
        settings.set(["weight", "nonExistentMetric"], forKey: "metrics_active_order")
        let active = store.activeKinds
        XCTAssertTrue(active.contains(.weight))
        XCTAssertFalse(active.map { $0.rawValue }.contains("nonExistentMetric"))
    }

    // MARK: - keyMetrics

    /// Co sprawdza: Pierwsze odczytanie keyMetrics auto-przypisuje pierwsze 5 aktywnych metryk.
    /// Dlaczego: UX wymaga, żeby Home miał metryki od razu po pierwszym włączeniu.
    /// Kryteria: keyMetrics.count == 5, zawiera weight i bodyFat.
    func testKeyMetricsAutoAssignsFirstFiveOnFirstSession() {
        let (store, _) = makeStore()
        store.setEnabled(true, for: .weight)
        store.setEnabled(true, for: .bodyFat)
        store.setEnabled(true, for: .waist)
        store.setEnabled(true, for: .hips)
        store.setEnabled(true, for: .neck)
        store.setEnabled(true, for: .shoulders)
        // home_key_metrics nie istnieje -> auto-przypisz pierwsze 5
        let keys = store.keyMetrics
        XCTAssertEqual(keys.count, 5)
        XCTAssertTrue(keys.contains(.weight))
        XCTAssertTrue(keys.contains(.bodyFat))
    }

    /// Co sprawdza: Pusty klucz home_key_metrics (świadomy wybór użytkownika) zwraca [].
    /// Dlaczego: Jeśli użytkownik odznaczył wszystkie gwiazdki, Home nie pokazuje key metrics.
    /// Kryteria: keyMetrics.isEmpty == true.
    func testKeyMetricsReturnsEmptyWhenUserClearedAll() {
        let (store, settings) = makeStore()
        store.setEnabled(true, for: .weight)
        // Klucz istnieje, ale pusty — świadomy wybór użytkownika
        settings.set([String](), forKey: "home_key_metrics")
        XCTAssertTrue(store.keyMetrics.isEmpty)
    }

    /// Co sprawdza: Wyłączenie metryki usuwa ją z keyMetrics mimo że jest zapisana.
    /// Dlaczego: keyMetrics musi być zawsze podzbiorem activeKinds.
    /// Kryteria: Po wyłączeniu .weight, keyMetrics nie zawiera .weight.
    func testKeyMetricsFiltersDisabledMetric() {
        let (store, _) = makeStore()
        store.setEnabled(true, for: .weight)
        store.setEnabled(true, for: .bodyFat)
        // Wywołaj keyMetrics żeby wyzwolić auto-assign i ustawić klucz
        _ = store.keyMetrics
        // Wyłącz weight
        store.setEnabled(false, for: .weight)
        XCTAssertFalse(store.keyMetrics.contains(.weight))
        XCTAssertTrue(store.keyMetrics.contains(.bodyFat))
    }

    // MARK: - setKeyMetric / isKeyMetric

    /// Co sprawdza: setKeyMetric(true) dodaje aktywną metrykę do key metrics.
    /// Dlaczego: Użytkownik oznacza metrykę gwiazdką → powinna pojawić się na Home.
    /// Kryteria: isKeyMetric(.weight) == true po wywołaniu.
    func testSetKeyMetricTrueAddsToKeyMetrics() {
        let (store, settings) = makeStore()
        store.setEnabled(true, for: .weight)
        // Ustaw pusty klucz żeby zapobiec auto-assignowi
        settings.set([String](), forKey: "home_key_metrics")
        let result = store.setKeyMetric(true, for: .weight)
        XCTAssertTrue(result)
        XCTAssertTrue(store.isKeyMetric(.weight))
    }

    /// Co sprawdza: setKeyMetric(false) usuwa metrykę z key metrics.
    /// Dlaczego: Odznaczenie gwiazdki musi być persist-owane.
    /// Kryteria: isKeyMetric(.weight) == false po odznaczeniu.
    func testSetKeyMetricFalseRemovesFromKeyMetrics() {
        let (store, settings) = makeStore()
        store.setEnabled(true, for: .weight)
        settings.set([String](), forKey: "home_key_metrics")
        store.setKeyMetric(true, for: .weight)
        store.setKeyMetric(false, for: .weight)
        XCTAssertFalse(store.isKeyMetric(.weight))
    }

    /// Co sprawdza: setKeyMetric zwraca false przy próbie dodania 6. metryki (limit = 5).
    /// Dlaczego: Home wyświetla maks 5 key metrics; limit musi być egzekwowany.
    /// Kryteria: Szóste wywołanie zwraca false, isKeyMetric(.shoulders) == false, count == 5.
    func testSetKeyMetricReturnsFalseWhenLimitReached() {
        let (store, settings) = makeStore()
        [MetricKind.weight, .bodyFat, .waist, .hips, .neck, .shoulders].forEach { store.setEnabled(true, for: $0) }
        settings.set([String](), forKey: "home_key_metrics")
        store.setKeyMetric(true, for: .weight)
        store.setKeyMetric(true, for: .bodyFat)
        store.setKeyMetric(true, for: .waist)
        store.setKeyMetric(true, for: .hips)
        store.setKeyMetric(true, for: .neck)
        let result = store.setKeyMetric(true, for: .shoulders)   // 6. -> powinno zwrocic false
        XCTAssertFalse(result)
        XCTAssertFalse(store.isKeyMetric(.shoulders))
        XCTAssertEqual(store.keyMetrics.count, 5)
    }
}
