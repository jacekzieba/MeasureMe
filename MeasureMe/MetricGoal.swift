// MetricGoal.swift
//
// **MetricGoal**
// Model SwiftData reprezentujący cel użytkownika dla konkretnej metryki.
//
// **Struktura:**
// - Każda metryka może mieć maksymalnie jeden cel
// - Wartość celu przechowywana w jednostkach bazowych (metric: kg, cm, %)
// - Data utworzenia celu dla celów historycznych
// - Kierunek celu (increase/decrease) określa czy chcemy zwiększyć czy zmniejszyć wartość
//
// **Użycie:**
// - Wyświetlanie poziomej przerywanej linii na wykresach
// - Tracking postępów użytkownika w osiąganiu celów
// - Edycja i usuwanie celów przez użytkownika
//
import SwiftData
import Foundation

@Model
final class MetricGoal {
    /// Kierunek celu - czy chcemy zwiększyć czy zmniejszyć wartość
    enum Direction: String, Codable {
        case increase  // Zwiększ (np. masa mięśniowa, wzrost)
        case decrease  // Zmniejsz (np. waga, tłuszcz, obwody)
    }
    
    /// Rodzaj metryki jako String (rawValue z MetricKind enum)
    var kindRaw: String
    
    /// Wartość docelowa w jednostkach bazowych:
    /// - Waga/Lean Body Mass: kilogramy
    /// - Wymiary: centymetry
    /// - Body Fat: procent (0.0-100.0)
    var targetValue: Double
    
    /// Data utworzenia/ostatniej modyfikacji celu
    var createdDate: Date
    
    /// Kierunek celu jako String (rawValue z Direction enum)
    var directionRaw: String
    
    init(kind: MetricKind, targetValue: Double, direction: Direction = .decrease, createdDate: Date = .now) {
        self.kindRaw = kind.rawValue
        self.targetValue = targetValue
        self.directionRaw = direction.rawValue
        self.createdDate = createdDate
    }
    
    /// Wygodny accessor do konwersji String -> MetricKind
    var kind: MetricKind {
        get { MetricKind(rawValue: kindRaw) ?? .weight }
        set { kindRaw = newValue.rawValue }
    }
    
    /// Wygodny accessor do konwersji String -> Direction
    var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .decrease }
        set { directionRaw = newValue.rawValue }
    }
    
    /// Sprawdza czy cel został osiągnięty na podstawie aktualnej wartości
    func isAchieved(currentValue: Double) -> Bool {
        switch direction {
        case .increase:
            return currentValue >= targetValue
        case .decrease:
            return currentValue <= targetValue
        }
    }
    
    /// Oblicza ile zostało do celu (może być ujemne jeśli przekroczono)
    func remainingToGoal(currentValue: Double) -> Double {
        switch direction {
        case .increase:
            return targetValue - currentValue  // Dodatnie = jeszcze trzeba wzrosnąć
        case .decrease:
            return currentValue - targetValue  // Dodatnie = jeszcze trzeba spaść
        }
    }
}
