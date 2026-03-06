import Foundation

/// Abstrakcja zapisu aktywności streakowej, ułatwiająca tworzenie atrap testowych.
protocol StreakTracking {
    func recordMetricSaved(date: Date)
}

extension StreakManager: StreakTracking {}
