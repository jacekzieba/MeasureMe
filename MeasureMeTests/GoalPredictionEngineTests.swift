import XCTest
@testable import MeasureMe

/// Tests for GoalPredictionEngine (Holt's Double Exponential Smoothing).
@MainActor
final class GoalPredictionEngineTests: XCTestCase {

    // MARK: - Helpers

    private let baseDate = Date(timeIntervalSince1970: 1_770_000_000)

    /// Creates samples with daily intervals starting from baseDate.
    private func makeSamples(
        kind: MetricKind = .weight,
        values: [Double],
        startDay: Int = 0
    ) -> [MetricSample] {
        values.enumerated().map { i, value in
            MetricSample(
                kind: kind,
                value: value,
                date: baseDate.addingTimeInterval(Double(startDay + i) * 86400)
            )
        }
    }

    private func makeGoal(
        kind: MetricKind = .weight,
        target: Double,
        direction: MetricGoal.Direction
    ) -> MetricGoal {
        MetricGoal(kind: kind, targetValue: target, direction: direction, createdDate: baseDate)
    }

    // MARK: - Insufficient Data

    func testInsufficientData_TooFewSamples() {
        let samples = makeSamples(values: [80, 79, 78, 77, 76, 75]) // 6 points
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .insufficientData)
    }

    func testInsufficientData_LessThan7DaySpan() {
        // 7 samples all within 3 days
        let samples = (0..<7).map { i in
            MetricSample(
                kind: .weight,
                value: 80 - Double(i) * 0.5,
                date: baseDate.addingTimeInterval(Double(i) * 86400 * 0.4) // ~9.6h apart
            )
        }
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .insufficientData)
    }

    // MARK: - Goal Already Achieved

    func testAchieved_DecreaseGoal() {
        let samples = makeSamples(values: [80, 79, 78, 77, 76, 75, 69])
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .achieved)
    }

    func testAchieved_IncreaseGoal() {
        let samples = makeSamples(values: [30, 31, 32, 33, 34, 35, 41])
        let goal = makeGoal(target: 40, direction: .increase)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .achieved)
    }

    // MARK: - On Track

    func testOnTrack_SteadyWeightLoss() {
        // Losing ~1 kg/day → from 80 to 73 over 7 days. Goal: 65 kg (decrease).
        let samples = makeSamples(values: [80, 79, 78, 77, 76, 75, 74, 73])
        let goal = makeGoal(target: 65, direction: .decrease)
        let result = GoalPredictionEngine.predict(samples: samples, goal: goal)

        if case .onTrack(let date) = result {
            let daysUntilGoal = date.timeIntervalSince(baseDate.addingTimeInterval(7 * 86400)) / 86400
            // ~8 kg remaining at ~1 kg/day rate → should be roughly 8 days
            XCTAssertGreaterThan(daysUntilGoal, 5, "Should need at least a few days")
            XCTAssertLessThan(daysUntilGoal, 15, "Should not be too far in the future")
        } else {
            XCTFail("Expected .onTrack, got \(result)")
        }
    }

    func testOnTrack_SteadyMuscleGain() {
        // Biceps gaining ~0.5 cm/day. Goal: increase to 40 cm.
        let samples = makeSamples(
            kind: .leftBicep,
            values: [35, 35.5, 36, 36.5, 37, 37.5, 38, 38.5]
        )
        let goal = makeGoal(kind: .leftBicep, target: 40, direction: .increase)
        let result = GoalPredictionEngine.predict(samples: samples, goal: goal)

        if case .onTrack = result {
            // Success
        } else {
            XCTFail("Expected .onTrack, got \(result)")
        }
    }

    // MARK: - Trend Opposite

    func testTrendOpposite_WantDecrease_ButGaining() {
        // Weight going UP but goal is to decrease
        let samples = makeSamples(values: [80, 81, 82, 83, 84, 85, 86, 87])
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .trendOpposite)
    }

    func testTrendOpposite_WantIncrease_ButLosing() {
        // Value going DOWN but goal is to increase
        let samples = makeSamples(kind: .leftBicep, values: [40, 39.5, 39, 38.5, 38, 37.5, 37, 36.5])
        let goal = makeGoal(kind: .leftBicep, target: 45, direction: .increase)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .trendOpposite)
    }

    // MARK: - Flat Trend

    func testFlatTrend() {
        // All values essentially the same
        let samples = makeSamples(values: [80, 80, 80, 80, 80, 80, 80, 80])
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .flatTrend)
    }

    // MARK: - Too Far Out

    func testTooFarOut_VerySlowProgress() {
        // Losing 0.001 kg/day → goal 10 kg away → 10000 days ≈ 27 years
        let samples = makeSamples(values: [80, 79.999, 79.998, 79.997, 79.996, 79.995, 79.994, 79.993])
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .tooFarOut)
    }

    // MARK: - Irregular Intervals

    func testIrregularIntervals_StillPredicts() {
        // Samples with gaps: day 0, 1, 3, 5, 8, 12, 15, 20
        let days = [0, 1, 3, 5, 8, 12, 15, 20]
        let samples = days.enumerated().map { _, day in
            MetricSample(
                kind: .weight,
                value: 80 - Double(day) * 0.5,
                date: baseDate.addingTimeInterval(Double(day) * 86400)
            )
        }
        let goal = makeGoal(target: 65, direction: .decrease)
        let result = GoalPredictionEngine.predict(samples: samples, goal: goal)

        if case .onTrack = result {
            // Success — irregular intervals handled
        } else {
            XCTFail("Expected .onTrack with irregular intervals, got \(result)")
        }
    }

    // MARK: - Duplicate Dates

    func testDuplicateDates_AveragedCorrectly() {
        // Two samples per day for first few days
        var samples: [MetricSample] = []
        for day in 0..<10 {
            let date = baseDate.addingTimeInterval(Double(day) * 86400)
            let baseValue = 80 - Double(day) * 1.0
            samples.append(MetricSample(kind: .weight, value: baseValue - 0.5, date: date))
            samples.append(MetricSample(kind: .weight, value: baseValue + 0.5, date: date.addingTimeInterval(3600)))
        }
        let goal = makeGoal(target: 65, direction: .decrease)
        let result = GoalPredictionEngine.predict(samples: samples, goal: goal)

        if case .onTrack = result {
            // Success
        } else {
            XCTFail("Expected .onTrack with duplicate dates, got \(result)")
        }
    }

    // MARK: - Exactly 7 Points

    func testExactly7Points_Spanning7Days_Works() {
        // 8 samples: day 0..7 = exactly 7-day span
        let samples = makeSamples(values: [80, 79, 78, 77, 76, 75, 74, 73])
        let goal = makeGoal(target: 70, direction: .decrease)
        let result = GoalPredictionEngine.predict(samples: samples, goal: goal)
        XCTAssertNotEqual(result, .insufficientData)
    }

    func testExactly7Points_Under7DaySpan_InsufficientData() {
        // 7 samples: day 0..6 = 6-day span → insufficient
        let samples = makeSamples(values: [80, 79, 78, 77, 76, 75, 74])
        let goal = makeGoal(target: 70, direction: .decrease)
        XCTAssertEqual(GoalPredictionEngine.predict(samples: samples, goal: goal), .insufficientData)
    }

    // MARK: - Daily Aggregation

    func testAggregateDaily_GroupsByDay() {
        let samples = [
            MetricSample(kind: .weight, value: 80, date: baseDate),
            MetricSample(kind: .weight, value: 82, date: baseDate.addingTimeInterval(3600)),
            MetricSample(kind: .weight, value: 78, date: baseDate.addingTimeInterval(86400)),
        ]
        let sorted = samples.sorted { $0.date < $1.date }
        let daily = GoalPredictionEngine.aggregateDaily(sorted)

        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily[0].value, 81.0, accuracy: 0.01) // average of 80, 82
        XCTAssertEqual(daily[1].value, 78.0, accuracy: 0.01)
    }

    // MARK: - Holt Smoothing

    func testHoltSmooth_LinearData_MatchesSlope() {
        // Perfectly linear: 100, 99, 98, 97... (slope = -1/day)
        let daily = (0..<30).map { day in
            GoalPredictionEngine.DailyPoint(
                date: baseDate.addingTimeInterval(Double(day) * 86400),
                value: 100 - Double(day)
            )
        }
        let (level, trend) = GoalPredictionEngine.holtSmooth(daily: daily, alpha: 0.15, beta: 0.05)

        // Level should be close to last value (71)
        XCTAssertEqual(level, 71, accuracy: 2.0)
        // Trend should be close to -1.0 per day
        XCTAssertEqual(trend, -1.0, accuracy: 0.2)
    }

    // MARK: - Weight Prediction Rates

    func testCalculateWeightRates_CurrentRate_MovingTowardGoal() {
        // 30 days of weight loss: 90 → ~86 (4 kg in ~30 days ≈ ~0.93 kg/week)
        let values = (0..<31).map { 90.0 - Double($0) * 0.133 }
        let samples = makeSamples(values: values)
        let goal = MetricGoal(
            kind: .weight, targetValue: 80, direction: .decrease,
            createdDate: baseDate, startValue: 90, startDate: baseDate
        )

        let rates = GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)
        XCTAssertNotNil(rates)
        XCTAssertNotNil(rates?.currentRate)
        XCTAssertGreaterThan(rates?.currentRate ?? 0, 0)
    }

    func testCalculateWeightRates_CurrentRate_NilWhenMovingAway() {
        // Weight going UP but goal is to decrease
        let values = (0..<31).map { 90.0 + Double($0) * 0.1 }
        let samples = makeSamples(values: values)
        let goal = MetricGoal(
            kind: .weight, targetValue: 80, direction: .decrease,
            createdDate: baseDate, startValue: 90, startDate: baseDate
        )

        let rates = GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)
        XCTAssertNotNil(rates)
        XCTAssertNil(rates?.currentRate, "Current rate should be nil when moving away from goal")
    }

    func testCalculateWeightRates_OverallRate() {
        // 60 days, losing ~0.5 kg/week
        let values = (0..<61).map { 90.0 - Double($0) * (0.5 / 7.0) }
        let samples = makeSamples(values: values)
        let goal = MetricGoal(
            kind: .weight, targetValue: 80, direction: .decrease,
            createdDate: baseDate, startValue: 90, startDate: baseDate
        )

        let rates = GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)
        XCTAssertNotNil(rates?.overallRate)
        XCTAssertEqual(rates!.overallRate!, 0.5, accuracy: 0.05)
    }

    func testCalculateWeightRates_CommitmentPassthrough() {
        let values = (0..<31).map { 90.0 - Double($0) * 0.1 }
        let samples = makeSamples(values: values)
        let goal = MetricGoal(
            kind: .weight, targetValue: 80, direction: .decrease,
            createdDate: baseDate, startValue: 90, startDate: baseDate,
            commitmentWeeklyRate: 0.5
        )

        let rates = GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)
        XCTAssertEqual(rates?.commitmentRate, 0.5)
    }

    func testCalculateWeightRates_ProjectedDate() {
        let values = (0..<31).map { 90.0 - Double($0) * 0.1 }
        let samples = makeSamples(values: values)
        let goal = MetricGoal(
            kind: .weight, targetValue: 80, direction: .decrease,
            createdDate: baseDate, startValue: 90, startDate: baseDate,
            commitmentWeeklyRate: 0.5
        )

        let rates = GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)!
        let date = rates.projectedDate(forRate: rates.commitmentRate, from: baseDate)
        XCTAssertNotNil(date, "Should project a date with valid commitment rate and remaining > 0")
    }

    func testCalculateWeightRates_InsufficientData_ReturnsNil() {
        let samples = makeSamples(values: [90])
        let goal = makeGoal(target: 80, direction: .decrease)

        let rates = GoalPredictionEngine.calculateWeightRates(samples: samples, goal: goal)
        // Should still return rates (with nil current/overall), because we have at least 1 sample
        XCTAssertNotNil(rates)
        XCTAssertNil(rates?.currentRate)
    }
}
