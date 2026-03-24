// CustomMetricDefinition.swift
//
// **CustomMetricDefinition**
// Model SwiftData reprezentujący definicję metryki stworzonej przez użytkownika.
//
// **Struktura:**
// - Stabilny identyfikator "custom_<UUID>" używany w MetricSample.kindRaw / MetricGoal.kindRaw
// - Nazwa, jednostka, ikona SF Symbol, opcjonalny zakres wartości
// - Brak konwersji metric/imperial — wartości wyświetlane w unitLabel as-is
//

import SwiftData
import Foundation

@Model
final class CustomMetricDefinition {
    /// Stabilny identyfikator: "custom_<UUID>", przechowywany w MetricSample.kindRaw / MetricGoal.kindRaw
    @Attribute(.unique) var identifier: String

    /// Nazwa metryki widoczna dla użytkownika (np. "Wrist", "Steps")
    var name: String

    /// Symbol jednostki (np. "cm", "reps", "ml", "kcal")
    var unitLabel: String

    /// Nazwa ikony SF Symbol (np. "ruler", "figure.run", "drop.fill")
    var sfSymbolName: String

    /// Opcjonalny dolny zakres wartości
    var minValue: Double?

    /// Opcjonalny górny zakres wartości
    var maxValue: Double?

    /// Czy spadek wartości jest korzystny gdy brak ustawionego celu
    var favorsDecrease: Bool

    /// Data utworzenia
    var createdDate: Date

    /// Kolejność sortowania w sekcji custom metryk
    var sortOrder: Int

    init(
        name: String,
        unitLabel: String,
        sfSymbolName: String = "circle.dotted",
        minValue: Double? = nil,
        maxValue: Double? = nil,
        favorsDecrease: Bool = false,
        sortOrder: Int = 0
    ) {
        self.identifier = "custom_\(UUID().uuidString)"
        self.name = name
        self.unitLabel = unitLabel
        self.sfSymbolName = sfSymbolName
        self.minValue = minValue
        self.maxValue = maxValue
        self.favorsDecrease = favorsDecrease
        self.createdDate = Date()
        self.sortOrder = sortOrder
    }
}
