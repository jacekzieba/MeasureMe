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

    /// Opcjonalna wartość startowa celu podana przez użytkownika (jednostki bazowe: kg, cm, %).
    /// Gdy nil, baseline jest wyliczany dynamicznie z próbek (stare zachowanie).
    var startValue: Double?

    /// Opcjonalna data startowa celu podana przez użytkownika.
    /// Gdy nil, baseline pochodzi z próbek ≤ createdDate (stare zachowanie).
    var startDate: Date?

    /// Zamierzone tygodniowe tempo zmiany w jednostkach bazowych (kg/tydzień dla wagi).
    /// Wartość dodatnia — np. 0.5 oznacza 0.5 kg/tydzień (niezależnie od kierunku).
    var commitmentWeeklyRate: Double?

    init(kind: MetricKind, targetValue: Double, direction: Direction = .decrease,
         createdDate: Date = .now, startValue: Double? = nil, startDate: Date? = nil,
         commitmentWeeklyRate: Double? = nil) {
        self.kindRaw = kind.rawValue
        self.targetValue = targetValue
        self.directionRaw = direction.rawValue
        self.createdDate = createdDate
        self.startValue = startValue
        self.startDate = startDate
        self.commitmentWeeklyRate = commitmentWeeklyRate
    }

    /// Inicjalizator dla custom metryk — przyjmuje surowy identyfikator (np. "custom_<UUID>")
    init(kindRaw: String, targetValue: Double, direction: Direction = .decrease,
         createdDate: Date = .now, startValue: Double? = nil, startDate: Date? = nil,
         commitmentWeeklyRate: Double? = nil) {
        self.kindRaw = kindRaw
        self.targetValue = targetValue
        self.directionRaw = direction.rawValue
        self.createdDate = createdDate
        self.startValue = startValue
        self.startDate = startDate
        self.commitmentWeeklyRate = commitmentWeeklyRate
    }

    /// Czy cel dotyczy custom metryki użytkownika
    var isCustomMetric: Bool {
        kindRaw.hasPrefix("custom_")
    }

    /// Wygodny accessor do konwersji String -> MetricKind.
    /// Zwraca nil dla uszkodzonych rekordów i custom metryk.
    var kind: MetricKind? {
        get { MetricKind(rawValue: kindRaw) }
        set {
            guard let newValue else { return }
            kindRaw = newValue.rawValue
        }
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

enum MetricGoalStore {
    /// Upserts a goal and optionally persists a matching start sample for the same metric.
    @discardableResult
    static func upsertGoal(
        kind: MetricKind,
        targetValue: Double,
        direction: MetricGoal.Direction,
        startValue: Double? = nil,
        startDate: Date? = nil,
        commitmentWeeklyRate: Double? = nil,
        in context: ModelContext,
        existingGoal: MetricGoal?,
        existingSamples: [MetricSample],
        now: Date = .now
    ) -> MetricGoal {
        let goal: MetricGoal
        if let existingGoal {
            existingGoal.targetValue = targetValue
            existingGoal.direction = direction
            existingGoal.startValue = startValue
            existingGoal.startDate = startDate
            existingGoal.commitmentWeeklyRate = commitmentWeeklyRate
            existingGoal.createdDate = now
            goal = existingGoal
        } else {
            let newGoal = MetricGoal(
                kind: kind,
                targetValue: targetValue,
                direction: direction,
                createdDate: now,
                startValue: startValue,
                startDate: startDate,
                commitmentWeeklyRate: commitmentWeeklyRate
            )
            context.insert(newGoal)
            goal = newGoal
        }

        if let startValue, let startDate {
            let matchingStartSampleExists = existingSamples.contains {
                abs($0.date.timeIntervalSince(startDate)) < 60 && abs($0.value - startValue) < 0.001
            }
            if !matchingStartSampleExists {
                context.insert(MetricSample(kind: kind, value: startValue, date: startDate))
            }
        }

        return goal
    }

    /// Upsert celu dla custom metryki (identyfikator jako surowy String).
    @discardableResult
    static func upsertCustomGoal(
        kindRaw: String,
        targetValue: Double,
        direction: MetricGoal.Direction,
        startValue: Double? = nil,
        startDate: Date? = nil,
        commitmentWeeklyRate: Double? = nil,
        in context: ModelContext,
        existingGoal: MetricGoal?,
        existingSamples: [MetricSample],
        now: Date = .now
    ) -> MetricGoal {
        let goal: MetricGoal
        if let existingGoal {
            existingGoal.targetValue = targetValue
            existingGoal.direction = direction
            existingGoal.startValue = startValue
            existingGoal.startDate = startDate
            existingGoal.commitmentWeeklyRate = commitmentWeeklyRate
            existingGoal.createdDate = now
            goal = existingGoal
        } else {
            let newGoal = MetricGoal(
                kindRaw: kindRaw,
                targetValue: targetValue,
                direction: direction,
                createdDate: now,
                startValue: startValue,
                startDate: startDate,
                commitmentWeeklyRate: commitmentWeeklyRate
            )
            context.insert(newGoal)
            goal = newGoal
        }

        if let startValue, let startDate {
            let matchingStartSampleExists = existingSamples.contains {
                abs($0.date.timeIntervalSince(startDate)) < 60 && abs($0.value - startValue) < 0.001
            }
            if !matchingStartSampleExists {
                context.insert(MetricSample(kindRaw: kindRaw, value: startValue, date: startDate))
            }
        }

        return goal
    }
}
