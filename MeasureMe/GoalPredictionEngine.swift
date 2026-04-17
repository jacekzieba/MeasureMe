// GoalPredictionEngine.swift
//
// **GoalPredictionEngine**
// Goal date prediction using Double Exponential Smoothing (Holt's method).
//
// **Algorithm:**
// Holt's Linear Trend Method models two components:
//   - Level (s_t): smoothed current data level
//   - Trend (b_t): smoothed change per day
//
// Update formulas (for irregular intervals):
//   s_i = α * y_i + (1 - α) * (s_{i-1} + b_{i-1} * Δt)
//   b_i = β * ((s_i - s_{i-1}) / Δt) + (1 - β) * b_{i-1}
//
// Forecast: ŷ(t + h) = s_n + b_n * h
// Goal date: h = (targetValue - s_n) / b_n
//
// **Parameters:**
// - α = 0.15 (data smoothing) — dampens daily fluctuations of ±1 kg
// - β = 0.05 (trend smoothing) — stable trend, changes slowly
//
// **Minimum requirements:** 7 data points spread over ≥ 7 days
//
import Foundation

/// Goal prediction result.
enum GoalPredictionResult: Equatable {
    /// Goal already achieved.
    case achieved
    /// Predicted date of goal achievement.
    case onTrack(date: Date)
    /// Trend is moving in the opposite direction from the goal.
    case trendOpposite
    /// Trend is flat — no significant change.
    case flatTrend
    /// Prediction exceeds 5 years.
    case tooFarOut
    /// Insufficient data (< 7 measurements or < 7 days span).
    case insufficientData
}

/// Goal prediction engine based on Double Exponential Smoothing (Holt's Linear Trend).
enum GoalPredictionEngine {

    // MARK: - Public API

    /// Calculates goal achievement prediction based on historical measurements.
    ///
    /// - Parameters:
    ///   - samples: All samples for the given metric (any order).
    ///   - goal: User's goal with direction and target value.
    ///   - alpha: Data smoothing coefficient (default 0.15).
    ///   - beta: Trend smoothing coefficient (default 0.05).
    /// - Returns: Prediction result.
    static func predict(
        samples: [MetricSample],
        goal: MetricGoal,
        alpha: Double = 0.15,
        beta: Double = 0.05
    ) -> GoalPredictionResult {

        // 1. Check if the goal is already achieved (based on the raw latest value)
        let sortedAll = samples.sorted { $0.date < $1.date }
        if let latest = sortedAll.last, goal.isAchieved(currentValue: latest.value) {
            return .achieved
        }

        // 2. Aggregate samples to one per day (average) and sort
        let daily = aggregateDaily(sortedAll)
        guard daily.count >= 7,
              let firstDate = daily.first?.date,
              let lastDate = daily.last?.date
        else { return .insufficientData }

        let spanDays = lastDate.timeIntervalSince(firstDate) / 86400.0
        guard spanDays >= 7 else { return .insufficientData }

        // 3. Run Holt's Double Exponential Smoothing
        let (level, trend) = holtSmooth(daily: daily, alpha: alpha, beta: beta)

        // 4. Interpret the result
        let epsilon = 1e-6
        guard abs(trend) > epsilon else { return .flatTrend }

        // Check trend direction vs goal
        let movingTowardGoal: Bool
        switch goal.direction {
        case .increase:
            movingTowardGoal = trend > 0
        case .decrease:
            movingTowardGoal = trend < 0
        }

        guard movingTowardGoal else { return .trendOpposite }

        // 5. Calculate horizon (in days)
        let remaining = goal.targetValue - level
        let horizon = remaining / trend  // trend is per-day
        guard horizon.isFinite, horizon > 0 else { return .trendOpposite }

        let maxDays = 5.0 * 365.0
        guard horizon <= maxDays else { return .tooFarOut }

        let predictedDate = lastDate.addingTimeInterval(horizon * 86400.0)
        return .onTrack(date: predictedDate)
    }

    // MARK: - Internal

    /// Data point aggregated to a single day.
    struct DailyPoint {
        let date: Date
        let value: Double
    }

    /// Groups samples by calendar day and averages values.
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

    /// Holt's Double Exponential Smoothing with support for irregular intervals.
    ///
    /// - Returns: (level, trendPerDay) — final level and daily trend.
    static func holtSmooth(
        daily: [DailyPoint],
        alpha: Double,
        beta: Double
    ) -> (level: Double, trend: Double) {
        guard daily.count >= 2 else { return (daily.first?.value ?? 0, 0) }

        // Initialization
        var s = daily[0].value
        let dt0 = max(daily[1].date.timeIntervalSince(daily[0].date) / 86400.0, 1.0)
        var b = (daily[1].value - daily[0].value) / dt0

        // Iterate from the second point
        for i in 1..<daily.count {
            let dt = max(daily[i].date.timeIntervalSince(daily[i - 1].date) / 86400.0, 1.0)
            let prevS = s

            // Update level
            s = alpha * daily[i].value + (1 - alpha) * (prevS + b * dt)

            // Update trend (normalized to per-day)
            b = beta * ((s - prevS) / dt) + (1 - beta) * b
        }

        return (s, b)
    }

    // MARK: - Weight Prediction Rates

    /// Result of three weight change rate calculations (commitment / current / overall).
    struct WeightPredictionRates {
        /// Rate declared by the user (kg/week), nil when not set.
        let commitmentRate: Double?
        /// Rate from the last 30 days (kg/week), nil when direction doesn't match the goal or no data.
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
        // Anchor "current" rate to the latest sample date, not wall clock date.
        // This keeps the calculation stable for historical datasets and tests.
        let referenceDate = latest.date
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: referenceDate) ?? referenceDate
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
