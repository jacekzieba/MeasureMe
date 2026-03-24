// ActiveMetricsStore.swift
//
// **ActiveMetricsStore**
// ObservableObject zarządzający aktywowanymi metrykami użytkownika.
//
// **Odpowiedzialności:**
// - Przechowywanie stanu włączenia/wyłączenia metryk w UserDefaults
// - Zarządzanie kolejnością aktywnych metryk (drag & drop)
// - Publikowanie zmian do widoków SwiftUI
// - Nasłuchiwanie zmian w UserDefaults z innych źródeł
//
// **Optymalizacje:**
// - Debouncing publikacji zmian (unikanie nadmiarowych re-renderów)
// - Efektywne zarządzanie obserwatorem UserDefaults
// - Odroczone publikowanie zmian do następnego cyklu run loop
//
import Foundation
import SwiftUI
import Combine

@MainActor
final class ActiveMetricsStore: ObservableObject {
    // MARK: - Properties
    
    private let defaults: AppSettingsStore
    private var defaultsObserver: AnyCancellable?
    private let activeOrderKey = "metrics_active_order"
    private let keyMetricsKey = "home_key_metrics"
    private let maxKeyMetrics = 3
    
    /// Debouncing - zapobiega nadmiarowym publikacjom zmian.
    /// `nonisolated(unsafe)` allows safe access from `deinit` which is not
    /// izolowany do MainActor. `Task.cancel()` jest bezpieczne watkowo (atomowe),
    /// and all *writes* to this property happen exclusively on @MainActor,
    /// wiec jedynym dostepem miedzy izolacjami jest koncowe `.cancel()` w deinit.
    nonisolated(unsafe) private var pendingPublish: Task<Void, Never>?

    // MARK: - Initialization

    convenience init() {
        self.init(settings: .shared)
    }

    init(settings: AppSettingsStore) {
        self.defaults = settings

        defaultsObserver = settings.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.debouncedPublish()
            }
        }
    }

    deinit {
        pendingPublish?.cancel()
        defaultsObserver?.cancel()
    }
    
    // MARK: - Debounced Publishing
    
    /// Publikuje zmiany z małym opóźnieniem, anulując poprzednie oczekujące publikacje
    private func debouncedPublish() {
        // Anuluj poprzedni oczekujący task
        pendingPublish?.cancel()
        
        // Utwórz nowy task z małym opóźnieniem
        pendingPublish = Task { @MainActor in
            // Minimalne opóźnienie dla batch updates
            try? await Task.sleep(for: .milliseconds(50))
            
            // Sprawdź czy nie został anulowany
            guard !Task.isCancelled else { return }
            
            // Publikuj zmianę
            self.objectWillChange.send()
        }
    }

    // MARK: - Metric Groups (Stabilna kolejność)
    
    /// Metryki składu ciała (sync z HealthKit)
    let bodyComposition: [MetricKind] = [.weight, .bodyFat, .leanBodyMass]
    
    /// Metryki rozmiaru ciała (sync z HealthKit)
    /// Wzrost jest zarzadzany tylko w Ustawieniach do obliczen zdrowotnych, nie jako sledzona metryka.
    let bodySize: [MetricKind] = [.waist]
    
    /// Metryki górnej części ciała
    let upperBody: [MetricKind] = [.neck, .shoulders, .bust, .chest]
    
    /// Metryki ramion
    let arms: [MetricKind] = [.leftBicep, .rightBicep, .leftForearm, .rightForearm]
    
    /// Metryki dolnej części ciała
    let lowerBody: [MetricKind] = [.hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf]

    /// Wszystkie metryki w domyślnej kolejności
    var allKindsInOrder: [MetricKind] {
        bodyComposition + bodySize + upperBody + arms + lowerBody
    }

    // MARK: - Active Metrics
    
    /// Zwraca aktywne metryki w kolejności ustawionej przez użytkownika
    var activeKinds: [MetricKind] {
        // Które metryki są włączone
        let enabledSet = Set(allKindsInOrder.filter { isEnabled($0) })

        // Załaduj zapisaną kolejność (może zawierać nieaktywne - przefiltruj)
        // Deduplikacja: zabezpieczenie przed uszkodzonym metrics_active_order w UserDefaults
        var seen = Set<MetricKind>()
        let saved = loadActiveOrderKinds().filter { enabledSet.contains($0) && seen.insert($0).inserted }

        // Dodaj brakujące aktywne metryki na końcu
        let missing = allKindsInOrder.filter { enabledSet.contains($0) && !seen.contains($0) }

        return saved + missing
    }

    // MARK: - Key Metrics (Home)

    /// Zwraca kluczowe metryki na Home (maks 3), zawsze będące podzbiorem aktywnych.
    /// Jeśli użytkownik nigdy nie ustawiał key metrics (brak klucza w UserDefaults),
    /// automatycznie przypisujemy pierwsze aktywne metryki. Jeśli użytkownik świadomie
    /// odznaczył wszystkie gwiazdki (klucz istnieje, ale tablica jest pusta), zwracamy [].
    var keyMetrics: [MetricKind] {
        let active = activeKinds
        let stored = loadKeyMetricsKinds().filter { active.contains($0) }

        // Pierwsza sesja: klucz nie istnieje → auto-przypisz domyślne
        if defaults.object(forKey: keyMetricsKey) == nil {
            let initial = Array(active.prefix(maxKeyMetrics))
            saveKeyMetricsKinds(initial)
            return initial
        }

        // Klucz istnieje (nawet jeśli pusty) → uszanuj wybór użytkownika
        let orderedByActive = active.filter { stored.contains($0) }
        return Array(orderedByActive.prefix(maxKeyMetrics))
    }

    /// Sprawdza czy metryka jest oznaczona jako kluczowa (Home)
    func isKeyMetric(_ kind: MetricKind) -> Bool {
        keyMetrics.contains(kind)
    }

    /// Włącza/wyłącza metrykę jako kluczową. Zwraca false jeśli przekroczono limit.
    @discardableResult
    func setKeyMetric(_ enabled: Bool, for kind: MetricKind) -> Bool {
        var current = loadKeyMetricsKinds().filter { activeKinds.contains($0) }
        if enabled {
            guard !current.contains(kind) else { return true }
            guard current.count < maxKeyMetrics else { return false }
            current.append(kind)
        } else {
            current.removeAll { $0 == kind }
        }
        saveKeyMetricsKinds(current)
        debouncedPublish()
        return true
    }

    /// Tworzy Binding dla Toggle w UI
    func binding(for kind: MetricKind) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(kind) },
            set: { self.setEnabled($0, for: kind) }
        )
    }

    // MARK: - Order Management (Persistowana kolejność)
    
    /// Ładuje surową kolejność jako array stringów
    private func loadActiveOrderRaw() -> [String] {
        defaults.stringArray(forKey: activeOrderKey) ?? []
    }

    /// Konwertuje surową kolejność na array MetricKind
    private func loadActiveOrderKinds() -> [MetricKind] {
        loadActiveOrderRaw().compactMap { MetricKind(rawValue: $0) }
    }

    /// Zapisuje kolejność do UserDefaults
    private func saveActiveOrderKinds(_ kinds: [MetricKind]) {
        let raw = kinds.map { $0.rawValue }
        defaults.set(raw, forKey: activeOrderKey)
    }

    /// Ładuje zapisane kluczowe metryki jako array stringów
    private func loadKeyMetricsRaw() -> [String] {
        defaults.stringArray(forKey: keyMetricsKey) ?? []
    }

    /// Konwertuje zapisane kluczowe metryki na array MetricKind
    private func loadKeyMetricsKinds() -> [MetricKind] {
        loadKeyMetricsRaw().compactMap { MetricKind(rawValue: $0) }
    }

    /// Zapisuje kluczowe metryki do UserDefaults
    private func saveKeyMetricsKinds(_ kinds: [MetricKind]) {
        let raw = kinds.map { $0.rawValue }
        defaults.set(raw, forKey: keyMetricsKey)
    }

    /// Przestawia kolejność aktywnych metryk (drag & drop w UI)
    func moveActiveKinds(fromOffsets: IndexSet, toOffset: Int) {
        // Reorder na podstawie aktualnie widocznych activeKinds
        var current = activeKinds
        current.move(fromOffsets: fromOffsets, toOffset: toOffset)

        // Scal przestawioną listę z zapisaną kolejnością
        var saved = loadActiveOrderKinds()
        let activeSet = Set(current)
        
        // Usuń aktywne metryki z zapisanej listy
        saved.removeAll { activeSet.contains($0) }
        
        // Wstaw przestawione aktywne metryki na początek
        saved.insert(contentsOf: current, at: 0)

        saveActiveOrderKinds(saved)
        debouncedPublish()
    }

    // MARK: - Enable/Disable Management
    
    /// Sprawdza czy metryka jest włączona
    func isEnabled(_ kind: MetricKind) -> Bool {
        defaults.bool(forKey: key(for: kind))
    }

    /// Włącza lub wyłącza metrykę
    func setEnabled(_ enabled: Bool, for kind: MetricKind) {
        let k = key(for: kind)
        let current = defaults.bool(forKey: k)

        // Nic nie rób jeśli stan się nie zmienił
        guard current != enabled else { return }

        defaults.set(enabled, forKey: k)

        // Oznacz, że użytkownik zmienił konfigurację metryk
        if !defaults.bool(forKey: AppSettingsKeys.Experience.hasCustomizedMetrics) {
            defaults.set(true, forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)
        }

        // Aktualizuj kolejność
        var order = loadActiveOrderKinds()
        if enabled {
            // Dodaj na końcu jeśli nie ma
            if !order.contains(kind) { 
                order.append(kind) 
            }
        }
        // else: gdy disabled - pozostaw w order, ale nie będzie w activeKinds
        
        saveActiveOrderKinds(order)
        
        // Natychmiastowa publikacja zmian dla Toggle
        objectWillChange.send()
    }

    // MARK: - UserDefaults Keys

    /// Zwraca klucz UserDefaults dla danej metryki
    private func key(for kind: MetricKind) -> String {
        switch kind {
        case .weight: return "metric_weight_enabled"
        case .bodyFat: return "metric_bodyFat_enabled"
        case .height: return "metric_height_enabled"
        case .leanBodyMass: return "metric_nonFatMass_enabled"
        case .waist: return "metric_waist_enabled"
        case .neck: return "metric_neck_enabled"
        case .shoulders: return "metric_shoulders_enabled"
        case .bust: return "metric_bust_enabled"
        case .chest: return "metric_chest_enabled"
        case .leftBicep: return "metric_leftBicep_enabled"
        case .rightBicep: return "metric_rightBicep_enabled"
        case .leftForearm: return "metric_leftForearm_enabled"
        case .rightForearm: return "metric_rightForearm_enabled"
        case .hips: return "metric_hips_enabled"
        case .leftThigh: return "metric_leftThigh_enabled"
        case .rightThigh: return "metric_rightThigh_enabled"
        case .leftCalf: return "metric_leftCalf_enabled"
        case .rightCalf: return "metric_rightCalf_enabled"
        }
    }

    // MARK: - Custom Metrics

    private let customOrderKey = "custom_metrics_order"

    /// Zwraca klucz UserDefaults dla custom metryki
    private func customKey(for identifier: String) -> String {
        "custom_metric_\(identifier)_enabled"
    }

    /// Sprawdza czy custom metryka jest włączona
    func isCustomEnabled(_ identifier: String) -> Bool {
        defaults.bool(forKey: customKey(for: identifier))
    }

    /// Włącza lub wyłącza custom metrykę
    func setCustomEnabled(_ enabled: Bool, for identifier: String) {
        let k = customKey(for: identifier)
        let current = defaults.bool(forKey: k)
        guard current != enabled else { return }

        defaults.set(enabled, forKey: k)

        if !defaults.bool(forKey: AppSettingsKeys.Experience.hasCustomizedMetrics) {
            defaults.set(true, forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)
        }

        var order = loadCustomOrderRaw()
        if enabled {
            if !order.contains(identifier) {
                order.append(identifier)
            }
        }
        saveCustomOrderRaw(order)
        objectWillChange.send()
    }

    /// Tworzy Binding dla Toggle custom metryki w UI
    func customBinding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { self.isCustomEnabled(identifier) },
            set: { self.setCustomEnabled($0, for: identifier) }
        )
    }

    /// Zwraca aktywne (włączone) custom metryki identifiers w kolejności usera
    func activeCustomIdentifiers(from definitions: [CustomMetricDefinition]) -> [String] {
        let enabledSet = Set(definitions.map(\.identifier).filter { isCustomEnabled($0) })

        var seen = Set<String>()
        let saved = loadCustomOrderRaw().filter { enabledSet.contains($0) && seen.insert($0).inserted }
        let missing = definitions.map(\.identifier).filter { enabledSet.contains($0) && !seen.contains($0) }

        return saved + missing
    }

    /// Sprawdza czy custom metryka jest kluczowa (Home) — dzieli limit z built-in key metrics
    func isCustomKeyMetric(_ identifier: String) -> Bool {
        loadKeyMetricsRaw().contains(identifier)
    }

    /// Włącza/wyłącza custom metrykę jako kluczową. Dzieli limit maxKeyMetrics z built-in.
    @discardableResult
    func setCustomKeyMetric(_ enabled: Bool, for identifier: String) -> Bool {
        var current = loadKeyMetricsRaw()
        // Filtruj do aktywnych built-in + aktywnych custom
        let activeBuiltIn = Set(activeKinds.map(\.rawValue))
        current = current.filter { activeBuiltIn.contains($0) || (isCustomEnabled($0) && $0.hasPrefix("custom_")) }

        if enabled {
            guard !current.contains(identifier) else { return true }
            guard current.count < maxKeyMetrics else { return false }
            current.append(identifier)
        } else {
            current.removeAll { $0 == identifier }
        }
        defaults.set(current, forKey: keyMetricsKey)
        debouncedPublish()
        return true
    }

    /// Łączna liczba key metrics (built-in + custom)
    var totalKeyMetricsCount: Int {
        let raw = loadKeyMetricsRaw()
        let activeBuiltIn = Set(activeKinds.map(\.rawValue))
        return raw.filter { activeBuiltIn.contains($0) || (isCustomEnabled($0) && $0.hasPrefix("custom_")) }.count
    }

    /// Ordered key metric identifiers (both built-in rawValues and custom_ identifiers),
    /// filtered to active metrics only, limited to maxKeyMetrics.
    /// Returns the same order as stored in UserDefaults.
    var keyMetricIdentifiers: [String] {
        let raw = loadKeyMetricsRaw()
        let activeBuiltIn = Set(activeKinds.map(\.rawValue))

        // First session: key not set → auto-assign defaults (built-in only, same as keyMetrics)
        if defaults.object(forKey: keyMetricsKey) == nil {
            return Array(activeKinds.prefix(maxKeyMetrics)).map(\.rawValue)
        }

        let filtered = raw.filter { id in
            if id.hasPrefix("custom_") {
                return isCustomEnabled(id)
            }
            return activeBuiltIn.contains(id)
        }
        return Array(filtered.prefix(maxKeyMetrics))
    }

    // MARK: - Custom Order Persistence

    private func loadCustomOrderRaw() -> [String] {
        defaults.stringArray(forKey: customOrderKey) ?? []
    }

    private func saveCustomOrderRaw(_ identifiers: [String]) {
        defaults.set(identifiers, forKey: customOrderKey)
    }

    /// Przestawia kolejność custom metryk (drag & drop)
    func moveCustomIdentifiers(fromOffsets: IndexSet, toOffset: Int, definitions: [CustomMetricDefinition]) {
        var current = activeCustomIdentifiers(from: definitions)
        current.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveCustomOrderRaw(current)
        debouncedPublish()
    }

    /// Usuwa custom metrykę — czyści klucze enabled i order
    func removeCustomMetric(_ identifier: String) {
        defaults.removeObject(forKey: customKey(for: identifier))
        var order = loadCustomOrderRaw()
        order.removeAll { $0 == identifier }
        saveCustomOrderRaw(order)

        // Usuń z key metrics jeśli była
        var keyRaw = loadKeyMetricsRaw()
        if keyRaw.contains(identifier) {
            keyRaw.removeAll { $0 == identifier }
            defaults.set(keyRaw, forKey: keyMetricsKey)
        }

        objectWillChange.send()
    }
}
