// MetricGoal.swift
//
// **MetricGoal**
// SwiftData model representing a user's goal for a specific metric.
//
// **Structure:**
// - Each metric can have at most one goal
// - Goal value stored in base (metric) units (kg, cm, %)
// - Goal creation date for historical purposes
// - Goal direction (increase/decrease) determines whether we want to increase or decrease the value
//
// **Usage:**
// - Displaying a horizontal dashed line on charts
// - Tracking user progress toward goals
// - Editing and deleting goals by the user
//
import SwiftData
import Foundation

@Model
final class MetricGoal {
    /// Goal direction - whether we want to increase or decrease the value
    enum Direction: String, Codable {
        case increase  // Increase (e.g. muscle mass, height)
        case decrease  // Decrease (e.g. weight, fat, circumferences)
    }
    
    /// Metric kind as String (rawValue from MetricKind enum)
    var kindRaw: String
    
    /// Target value in base units:
    /// - Weight/Lean Body Mass: kilograms
    /// - Dimensions: centimeters
    /// - Body Fat: percentage (0.0-100.0)
    var targetValue: Double
    
    /// Date of creation/last modification of the goal
    var createdDate: Date
    
    /// Goal direction as String (rawValue from Direction enum)
    var directionRaw: String

    /// Optional goal start value provided by the user (base units: kg, cm, %).
    /// When nil, baseline is calculated dynamically from samples (legacy behavior).
    var startValue: Double?

    /// Optional goal start date provided by the user.
    /// When nil, baseline comes from samples ≤ createdDate (legacy behavior).
    var startDate: Date?

    /// Intended weekly rate of change in base units (kg/week for weight).
    /// Positive value — e.g. 0.5 means 0.5 kg/week (regardless of direction).
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
