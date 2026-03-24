// GoalPredictionEngine.swift
//
// **GoalPredictionEngine**
// Prognoza daty osiągnięcia celu za pomocą Double Exponential Smoothing (metoda Holta).
//
// **Algorytm:**
// Holt's Linear Trend Method modeluje dwa komponenty:
//   - Poziom (s_t): wygładzony bieżący poziom danych
//   - Trend (b_t): wygładzona zmiana na dzień
//
// Formuły aktualizacji (dla nieregularnych interwałów):
//   s_i = α * y_i + (1 - α) * (s_{i-1} + b_{i-1} * Δt)
//   b_i = β * ((s_i - s_{i-1}) / Δt) + (1 - β) * b_{i-1}
//
// Prognoza: ŷ(t + h) = s_n + b_n * h
// Data celu: h = (targetValue - s_n) / b_n
//
// **Parametry:**
// - α = 0.15 (wygładzanie danych) — tłumi dzienne wahania ±1 kg
// - β = 0.05 (wygładzanie trendu) — stabilny trend, wolno się zmienia
//
// **Wymagania minimalne:** 7 punktów danych rozłożonych na ≥ 7 dni
//
import Foundation

/// Wynik predykcji osiągnięcia celu.
enum GoalPredictionResult: Equatable {
    /// Cel już osiągnięty.
    case achieved
    /// Prognozowana data osiągnięcia celu.
    case onTrack(date: Date)
    /// Trend idzie w przeciwną stronę niż cel.
    case trendOpposite
    /// Trend jest płaski — brak wyraźnej zmiany.
    case flatTrend
    /// Prognoza wykracza poza 5 lat.
    case tooFarOut
    /// Za mało danych (< 7 pomiarów lub < 7 dni rozpiętości).
    case insufficientData
}

/// Silnik predykcji celu oparty na Double Exponential Smoothing (Holt's Linear Trend).
enum GoalPredictionEngine {

    // MARK: - Public API

    /// Oblicza prognozę osiągnięcia celu na podstawie historycznych pomiarów.
    ///
    /// - Parameters:
    ///   - samples: Wszystkie próbki dla danej metryki (dowolna kolejność).
    ///   - goal: Cel użytkownika z kierunkiem i wartością docelową.
    ///   - alpha: Współczynnik wygładzania danych (domyślnie 0.15).
    ///   - beta: Współczynnik wygładzania trendu (domyślnie 0.05).
    /// - Returns: Wynik predykcji.
    static func predict(
        samples: [MetricSample],
        goal: MetricGoal,
        alpha: Double = 0.15,
        beta: Double = 0.05
    ) -> GoalPredictionResult {

        // 1. Sprawdź czy cel jest już osiągnięty (na surowej ostatniej wartości)
        let sortedAll = samples.sorted { $0.date < $1.date }
        if let latest = sortedAll.last, goal.isAchieved(currentValue: latest.value) {
            return .achieved
        }

        // 2. Agreguj próbki do jednej na dzień (średnia) i posortuj
        let daily = aggregateDaily(sortedAll)
        guard daily.count >= 7 else { return .insufficientData }

        let firstDate = daily.first!.date
        let lastDate = daily.last!.date
        let spanDays = lastDate.timeIntervalSince(firstDate) / 86400.0
        guard spanDays >= 7 else { return .insufficientData }

        // 3. Uruchom Holt's Double Exponential Smoothing
        let (level, trend) = holtSmooth(daily: daily, alpha: alpha, beta: beta)

        // 4. Interpretuj wynik
        let epsilon = 1e-6
        guard abs(trend) > epsilon else { return .flatTrend }

        // Sprawdź kierunek trendu vs cel
        let movingTowardGoal: Bool
        switch goal.direction {
        case .increase:
            movingTowardGoal = trend > 0
        case .decrease:
            movingTowardGoal = trend < 0
        }

        guard movingTowardGoal else { return .trendOpposite }

        // 5. Oblicz horyzont (w dniach)
        let remaining = goal.targetValue - level
        let horizon = remaining / trend  // trend jest per-day
        guard horizon.isFinite, horizon > 0 else { return .trendOpposite }

        let maxDays = 5.0 * 365.0
        guard horizon <= maxDays else { return .tooFarOut }

        let predictedDate = lastDate.addingTimeInterval(horizon * 86400.0)
        return .onTrack(date: predictedDate)
    }

    // MARK: - Internal

    /// Punkt danych zagregowany do jednego dnia.
    struct DailyPoint {
        let date: Date
        let value: Double
    }

    /// Grupuje próbki wg dnia kalendarzowego i uśrednia wartości.
    static func aggregateDaily(_ sorted: [MetricSample]) -> [DailyPoint] {
        let calendar = Calendar.current
        var groups: [(day: Date, values: [Double])] = []

        for sample in sorted {
            let dayStart = calendar.startOfDay(for: sample.date)
            if let last = groups.last, last.day == dayStart {
                groups[groups.count - 1].values.append(sample.value)
            } else {
                groups.append((day: dayStart, values: [sample.value]))
            }
        }

        return groups.map { group in
            let avg = group.values.reduce(0, +) / Double(group.values.count)
            return DailyPoint(date: group.day, value: avg)
        }
    }

    /// Holt's Double Exponential Smoothing z obsługą nieregularnych interwałów.
    ///
    /// - Returns: (level, trendPerDay) — końcowy poziom i trend dzienny.
    static func holtSmooth(
        daily: [DailyPoint],
        alpha: Double,
        beta: Double
    ) -> (level: Double, trend: Double) {
        guard daily.count >= 2 else { return (daily.first?.value ?? 0, 0) }

        // Inicjalizacja
        var s = daily[0].value
        let dt0 = max(daily[1].date.timeIntervalSince(daily[0].date) / 86400.0, 1.0)
        var b = (daily[1].value - daily[0].value) / dt0

        // Iteracja od drugiego punktu
        for i in 1..<daily.count {
            let dt = max(daily[i].date.timeIntervalSince(daily[i - 1].date) / 86400.0, 1.0)
            let prevS = s

            // Aktualizacja poziomu
            s = alpha * daily[i].value + (1 - alpha) * (prevS + b * dt)

            // Aktualizacja trendu (znormalizowany do per-day)
            b = beta * ((s - prevS) / dt) + (1 - beta) * b
        }

        return (s, b)
    }

    // MARK: - Weight Prediction Rates

    /// Wynik obliczeń trzech temp zmiany wagi (commitment / current / overall).
    struct WeightPredictionRates {
        /// Tempo zadeklarowane przez użytkownika (kg/tydzień), nil gdy nie ustawione.
        let commitmentRate: Double?
        /// Tempo z ostatnich 30 dni (kg/tydzień), nil gdy kierunek niezgodny z celem lub brak danych.
        let currentRate: Double?
        /// Tempo od początku celu (kg/tydzień), nil gdy kierunek niezgodny z celem lub brak danych.
        let overallRate: Double?
        /// Pozostała odległość do celu w jednostkach bazowych (zawsze ≥ 0).
        let remaining: Double
        /// Bieżąca wartość (ostatni pomiar) w jednostkach bazowych.
        let currentValue: Double

        /// Oblicza prognozowaną datę osiągnięcia celu przy danym tempie tygodniowym.
        func projectedDate(forRate rate: Double?, from now: Date = AppClock.now) -> Date? {
            guard let rate, rate > 0, remaining > 0 else { return nil }
            let weeks = remaining / rate
            return Calendar.current.date(byAdding: .day, value: Int(ceil(weeks * 7)), to: now)
        }

        /// Formatuje "in X days" / "in X weeks" na podstawie różnicy dat.
        func relativeLabel(for date: Date, from now: Date = AppClock.now) -> String {
            let days = max(Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0, 1)
            if days < 14 {
                return AppLocalization.plural("prediction.in_days", days)
            } else {
                let weeks = days / 7
                return AppLocalization.plural("prediction.in_weeks", weeks)
            }
        }
    }

    /// Oblicza trzy tempa zmiany wagi dla rozwinięcej karty predykcji.
    static func calculateWeightRates(
        samples: [MetricSample],
        goal: MetricGoal
    ) -> WeightPredictionRates? {
        let sorted = samples.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }

        let remaining = abs(goal.remainingToGoal(currentValue: latest.value))

        // --- Current rate (ostatnie 30 dni) ---
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
        let recent = sorted.filter { $0.date >= thirtyDaysAgo }
        let currentRate: Double? = {
            guard recent.count >= 2,
                  let first = recent.first, let last = recent.last else { return nil }
            let daySpan = last.date.timeIntervalSince(first.date) / 86400.0
            guard daySpan >= 3 else { return nil }
            let weekSpan = daySpan / 7.0
            let change = last.value - first.value
            let ratePerWeek = change / weekSpan
            // Sprawdź czy kierunek zgadza się z celem
            let movingToward: Bool
            switch goal.direction {
            case .increase: movingToward = ratePerWeek > 0
            case .decrease: movingToward = ratePerWeek < 0
            }
            return movingToward ? abs(ratePerWeek) : nil
        }()

        // --- Overall rate (od początku celu) ---
        let overallRate: Double? = {
            let startDate = goal.startDate ?? goal.createdDate
            let startValue: Double
            if let sv = goal.startValue {
                startValue = sv
            } else {
                // Znajdź próbkę najbliższą dacie startu
                guard let closest = sorted.min(by: {
                    abs($0.date.timeIntervalSince(startDate)) < abs($1.date.timeIntervalSince(startDate))
                }) else { return nil }
                startValue = closest.value
            }
            let daySpan = latest.date.timeIntervalSince(startDate) / 86400.0
            guard daySpan >= 7 else { return nil }
            let weekSpan = daySpan / 7.0
            let change = latest.value - startValue
            let ratePerWeek = change / weekSpan
            let movingToward: Bool
            switch goal.direction {
            case .increase: movingToward = ratePerWeek > 0
            case .decrease: movingToward = ratePerWeek < 0
            }
            return movingToward ? abs(ratePerWeek) : nil
        }()

        return WeightPredictionRates(
            commitmentRate: goal.commitmentWeeklyRate,
            currentRate: currentRate,
            overallRate: overallRate,
            remaining: remaining,
            currentValue: latest.value
        )
    }
}
