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
    
    private let defaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Nasłuchuj zmian w UserDefaults (także z innych miejsc w aplikacji)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            // Odrocz publikację do następnego cyklu run loop
            // Unikamy "Publishing changes from within view updates" warning
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.debouncedPublish()
            }
        }
    }

    deinit {
        pendingPublish?.cancel()
        if let token = defaultsObserver {
            NotificationCenter.default.removeObserver(token)
        }
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
}
