// ActiveMetricsStore.swift
//
// **ActiveMetricsStore**
// ObservableObject managing user-activated metrics.
//
// **Responsibilities:**
// - Storing metric enabled/disabled state in UserDefaults
// - Managing the order of active metrics (drag & drop)
// - Publishing changes to SwiftUI views
// - Observing UserDefaults changes from other sources
//
// **Optimizations:**
// - Debouncing change publications (avoiding excessive re-renders)
// - Efficient UserDefaults observer management
// - Deferred change publishing to the next run loop cycle
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
    
    /// Debouncing - prevents excessive change publications.
    /// `nonisolated(unsafe)` allows safe access from `deinit` which is not
    /// isolated to MainActor. `Task.cancel()` is thread-safe (atomic),
    /// and all *writes* to this property happen exclusively on @MainActor,
    /// so the only cross-isolation access is the final `.cancel()` in deinit.
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
    
    /// Publishes changes with a small delay, cancelling previous pending publications
    private func debouncedPublish() {
        // Cancel previous pending task
        pendingPublish?.cancel()

        // Create a new task with a small delay
        pendingPublish = Task { @MainActor in
            // Minimal delay for batch updates
            try? await Task.sleep(for: .milliseconds(50))

            // Check if cancelled
            guard !Task.isCancelled else { return }

            // Publish change
            self.objectWillChange.send()
        }
    }

    // MARK: - Metric Groups (Stable order)

    /// Body composition metrics (synced with HealthKit)
    let bodyComposition: [MetricKind] = [.weight, .bodyFat, .leanBodyMass]

    /// Body size metrics (synced with HealthKit)
    /// Height is managed only in Settings for health calculations, not as a tracked metric.
    let bodySize: [MetricKind] = [.waist]

    /// Upper body metrics
    let upperBody: [MetricKind] = [.neck, .shoulders, .bust, .chest]

    /// Arm metrics
    let arms: [MetricKind] = [.leftBicep, .rightBicep, .leftForearm, .rightForearm]

    /// Lower body metrics
    let lowerBody: [MetricKind] = [.hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf]

    /// All metrics in default order
    var allKindsInOrder: [MetricKind] {
        bodyComposition + bodySize + upperBody + arms + lowerBody
    }

    // MARK: - Active Metrics
    
    /// Returns active metrics in the order set by the user
    var activeKinds: [MetricKind] {
        // Which metrics are enabled
        let enabledSet = Set(allKindsInOrder.filter { isEnabled($0) })

        // Load saved order (may contain inactive ones - filter them out)
        // Deduplication: protection against corrupted metrics_active_order in UserDefaults
        var seen = Set<MetricKind>()
        let saved = loadActiveOrderKinds().filter { enabledSet.contains($0) && seen.insert($0).inserted }

        // Add missing active metrics at the end
        let missing = allKindsInOrder.filter { enabledSet.contains($0) && !seen.contains($0) }

        return saved + missing
    }

    // MARK: - Key Metrics (Home)

    /// Returns key metrics for Home (max 3), always a subset of active metrics.
    /// If the user has never set key metrics (no key in UserDefaults),
    /// we automatically assign the first active metrics. If the user deliberately
    /// unchecked all stars (key exists but array is empty), we return [].
    var keyMetrics: [MetricKind] {
        let active = activeKinds
        let stored = loadKeyMetricsKinds().filter { active.contains($0) }

        // First session: key doesn't exist -> auto-assign defaults
        if defaults.object(forKey: keyMetricsKey) == nil {
            let initial = Array(active.prefix(maxKeyMetrics))
            saveKeyMetricsKinds(initial)
            return initial
        }

        // Key exists (even if empty) -> respect user's choice
        let orderedByActive = active.filter { stored.contains($0) }
        return Array(orderedByActive.prefix(maxKeyMetrics))
    }

    /// Checks whether a metric is marked as key (Home)
    func isKeyMetric(_ kind: MetricKind) -> Bool {
        keyMetrics.contains(kind)
    }

    /// Enables/disables a metric as key. Returns false if the limit is exceeded.
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

    /// Creates a Binding for Toggle in UI
    func binding(for kind: MetricKind) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(kind) },
            set: { self.setEnabled($0, for: kind) }
        )
    }

    // MARK: - Order Management (Persisted order)

    /// Loads raw order as a string array
    private func loadActiveOrderRaw() -> [String] {
        defaults.stringArray(forKey: activeOrderKey) ?? []
    }

    /// Converts raw order to a MetricKind array
    private func loadActiveOrderKinds() -> [MetricKind] {
        loadActiveOrderRaw().compactMap { MetricKind(rawValue: $0) }
    }

    /// Saves order to UserDefaults
    private func saveActiveOrderKinds(_ kinds: [MetricKind]) {
        let raw = kinds.map { $0.rawValue }
        defaults.set(raw, forKey: activeOrderKey)
    }

    /// Loads saved key metrics as a string array
    private func loadKeyMetricsRaw() -> [String] {
        defaults.stringArray(forKey: keyMetricsKey) ?? []
    }

    /// Converts saved key metrics to a MetricKind array
    private func loadKeyMetricsKinds() -> [MetricKind] {
        loadKeyMetricsRaw().compactMap { MetricKind(rawValue: $0) }
    }

    /// Saves key metrics to UserDefaults
    private func saveKeyMetricsKinds(_ kinds: [MetricKind]) {
        let raw = kinds.map { $0.rawValue }
        defaults.set(raw, forKey: keyMetricsKey)
    }

    /// Reorders active metrics (drag & drop in UI)
    func moveActiveKinds(fromOffsets: IndexSet, toOffset: Int) {
        // Reorder based on currently visible activeKinds
        var current = activeKinds
        current.move(fromOffsets: fromOffsets, toOffset: toOffset)

        // Merge reordered list with saved order
        var saved = loadActiveOrderKinds()
        let activeSet = Set(current)

        // Remove active metrics from saved list
        saved.removeAll { activeSet.contains($0) }

        // Insert reordered active metrics at the beginning
        saved.insert(contentsOf: current, at: 0)

        saveActiveOrderKinds(saved)
        debouncedPublish()
    }

    // MARK: - Enable/Disable Management
    
    /// Checks whether a metric is enabled
    func isEnabled(_ kind: MetricKind) -> Bool {
        defaults.bool(forKey: key(for: kind))
    }

    /// Enables or disables a metric
    func setEnabled(_ enabled: Bool, for kind: MetricKind) {
        let k = key(for: kind)
        let current = defaults.bool(forKey: k)

        // Do nothing if state hasn't changed
        guard current != enabled else { return }

        defaults.set(enabled, forKey: k)

        // Mark that the user has customized metric configuration
        if !defaults.bool(forKey: AppSettingsKeys.Experience.hasCustomizedMetrics) {
            defaults.set(true, forKey: AppSettingsKeys.Experience.hasCustomizedMetrics)
        }

        // Update order
        var order = loadActiveOrderKinds()
        if enabled {
            // Add at the end if not present
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
