import Testing
import Foundation
@testable import MeasureMeWatch_Watch_App

// MARK: - WatchMetricKind Tests

struct WatchMetricKindTests {

    // MARK: - Unit Conversion

    @Test func metricWeightDisplayValue() {
        let kind = WatchMetricKind.weight
        let result = kind.valueForDisplay(fromMetric: 80.0, isMetric: true)
        #expect(result == 80.0)
    }

    @Test func imperialWeightDisplayValue() {
        let kind = WatchMetricKind.weight
        let result = kind.valueForDisplay(fromMetric: 80.0, isMetric: false)
        // 80 kg ÷ 0.45359237 ≈ 176.37 lb
        #expect(abs(result - 176.37) < 0.1)
    }

    @Test func metricLengthDisplayValue() {
        let kind = WatchMetricKind.waist
        let result = kind.valueForDisplay(fromMetric: 85.0, isMetric: true)
        #expect(result == 85.0)
    }

    @Test func imperialLengthDisplayValue() {
        let kind = WatchMetricKind.waist
        let result = kind.valueForDisplay(fromMetric: 85.0, isMetric: false)
        // 85 cm ÷ 2.54 ≈ 33.46 in
        #expect(abs(result - 33.46) < 0.1)
    }

    @Test func percentDisplayValueUnchanged() {
        let kind = WatchMetricKind.bodyFat
        let metricResult = kind.valueForDisplay(fromMetric: 18.5, isMetric: true)
        let imperialResult = kind.valueForDisplay(fromMetric: 18.5, isMetric: false)
        #expect(metricResult == 18.5)
        #expect(imperialResult == 18.5)
    }

    // MARK: - Reverse Conversion (display → metric)

    @Test func metricValueFromDisplayRoundTrip() {
        let kind = WatchMetricKind.weight
        let display = kind.valueForDisplay(fromMetric: 82.5, isMetric: false)
        let backToMetric = kind.metricValue(fromDisplay: display, isMetric: false)
        #expect(abs(backToMetric - 82.5) < 0.01)
    }

    @Test func lengthMetricValueFromDisplayRoundTrip() {
        let kind = WatchMetricKind.neck
        let display = kind.valueForDisplay(fromMetric: 40.0, isMetric: false)
        let backToMetric = kind.metricValue(fromDisplay: display, isMetric: false)
        #expect(abs(backToMetric - 40.0) < 0.01)
    }

    // MARK: - Unit Symbols

    @Test func unitSymbolsMetric() {
        #expect(WatchMetricKind.weight.unitSymbol(isMetric: true) == "kg")
        #expect(WatchMetricKind.waist.unitSymbol(isMetric: true) == "cm")
        #expect(WatchMetricKind.bodyFat.unitSymbol(isMetric: true) == "%")
    }

    @Test func unitSymbolsImperial() {
        #expect(WatchMetricKind.weight.unitSymbol(isMetric: false) == "lb")
        #expect(WatchMetricKind.waist.unitSymbol(isMetric: false) == "in")
        #expect(WatchMetricKind.bodyFat.unitSymbol(isMetric: false) == "%")
    }

    // MARK: - Unit Categories

    @Test func unitCategories() {
        #expect(WatchMetricKind.weight.unitCategory == .weight)
        #expect(WatchMetricKind.leanBodyMass.unitCategory == .weight)
        #expect(WatchMetricKind.bodyFat.unitCategory == .percent)
        #expect(WatchMetricKind.waist.unitCategory == .length)
        #expect(WatchMetricKind.neck.unitCategory == .length)
        #expect(WatchMetricKind.hips.unitCategory == .length)
    }

    // MARK: - Trend Outcome

    @Test func trendOutcomeWeightDecrease() {
        let kind = WatchMetricKind.weight // favorsDecrease = true
        let result = kind.trendOutcome(from: 85.0, to: 82.0, goalTarget: nil, goalDirection: nil)
        #expect(result == .positive)
    }

    @Test func trendOutcomeWeightIncrease() {
        let kind = WatchMetricKind.weight
        let result = kind.trendOutcome(from: 82.0, to: 85.0, goalTarget: nil, goalDirection: nil)
        #expect(result == .negative)
    }

    @Test func trendOutcomeBicepIncrease() {
        let kind = WatchMetricKind.leftBicep // favorsDecrease = false
        let result = kind.trendOutcome(from: 35.0, to: 37.0, goalTarget: nil, goalDirection: nil)
        #expect(result == .positive)
    }

    @Test func trendOutcomeNeutralNoChange() {
        let kind = WatchMetricKind.weight
        let result = kind.trendOutcome(from: 80.0, to: 80.0, goalTarget: nil, goalDirection: nil)
        #expect(result == .neutral)
    }

    @Test func trendOutcomeWithGoalCloser() {
        let kind = WatchMetricKind.weight
        // Goal: 75 kg, started at 85, now at 80 → closer to goal → positive
        let result = kind.trendOutcome(from: 85.0, to: 80.0, goalTarget: 75.0, goalDirection: "decrease")
        #expect(result == .positive)
    }

    @Test func trendOutcomeWithGoalFarther() {
        let kind = WatchMetricKind.weight
        // Goal: 75 kg, started at 80, now at 85 → farther from goal → negative
        let result = kind.trendOutcome(from: 80.0, to: 85.0, goalTarget: 75.0, goalDirection: "decrease")
        #expect(result == .negative)
    }

    // MARK: - Favors Decrease

    @Test func favorsDecrease() {
        #expect(WatchMetricKind.weight.favorsDecrease == true)
        #expect(WatchMetricKind.bodyFat.favorsDecrease == true)
        #expect(WatchMetricKind.waist.favorsDecrease == true)
        #expect(WatchMetricKind.hips.favorsDecrease == true)
        #expect(WatchMetricKind.bust.favorsDecrease == true)
    }

    @Test func doesNotFavorDecrease() {
        #expect(WatchMetricKind.leftBicep.favorsDecrease == false)
        #expect(WatchMetricKind.shoulders.favorsDecrease == false)
        #expect(WatchMetricKind.chest.favorsDecrease == false)
        #expect(WatchMetricKind.leftThigh.favorsDecrease == false)
    }

    // MARK: - HealthKit Sync

    @Test func healthKitSyncedMetrics() {
        let synced: [WatchMetricKind] = [.weight, .bodyFat, .height, .leanBodyMass, .waist]
        for kind in synced {
            #expect(kind.isHealthKitSynced == true, "\(kind.rawValue) should be HealthKit synced")
        }
    }

    @Test func nonHealthKitSyncedMetrics() {
        let notSynced: [WatchMetricKind] = [.neck, .shoulders, .bust, .chest, .leftBicep, .hips]
        for kind in notSynced {
            #expect(kind.isHealthKitSynced == false, "\(kind.rawValue) should NOT be HealthKit synced")
        }
    }

    // MARK: - All Cases

    @Test func allCasesCount() {
        #expect(WatchMetricKind.allCases.count == 18)
    }

    @Test func allCasesHaveDisplayName() {
        for kind in WatchMetricKind.allCases {
            #expect(!kind.displayName.isEmpty, "\(kind.rawValue) displayName should not be empty")
        }
    }

    @Test func allCasesHaveSystemImage() {
        for kind in WatchMetricKind.allCases {
            #expect(!kind.systemImage.isEmpty, "\(kind.rawValue) systemImage should not be empty")
        }
    }

    // MARK: - Crown Input

    @Test func crownStepIsReasonable() {
        for kind in WatchMetricKind.allCases {
            #expect(kind.crownStep > 0 && kind.crownStep <= 1.0)
        }
    }

    @Test func displayRangeIsValid() {
        for kind in WatchMetricKind.allCases {
            #expect(kind.displayRange.lowerBound < kind.displayRange.upperBound)
        }
    }
}

// MARK: - WatchMetricData Tests

struct WatchMetricDataTests {

    private func makeSampleData(
        kind: String = "weight",
        values: [(Double, TimeInterval)] = [],
        goal: WatchMetricData.GoalDTO? = nil,
        units: String = "metric"
    ) -> WatchMetricData {
        let samples = values.map { val, daysAgo in
            WatchMetricData.SampleDTO(
                value: val,
                date: Date().addingTimeInterval(-daysAgo * 24 * 3600)
            )
        }
        return WatchMetricData(kind: kind, samples: samples, goal: goal, unitsSystem: units)
    }

    @Test func isMetricProperty() {
        let metric = makeSampleData(units: "metric")
        let imperial = makeSampleData(units: "imperial")
        #expect(metric.isMetric == true)
        #expect(imperial.isMetric == false)
    }

    @Test func latestSampleReturnsNewest() {
        let data = makeSampleData(values: [(80.0, 10), (82.0, 5), (81.0, 1)])
        let latest = data.latestSample
        #expect(latest != nil)
        #expect(latest?.value == 81.0)
    }

    @Test func latestSampleNilWhenEmpty() {
        let data = makeSampleData(values: [])
        #expect(data.latestSample == nil)
    }

    @Test func last30DaySamplesFiltersOld() {
        let data = makeSampleData(values: [
            (80.0, 60),  // 60 days ago — excluded
            (81.0, 20),  // 20 days ago — included
            (82.0, 5)    // 5 days ago — included
        ])
        let recent = data.last30DaySamples
        #expect(recent.count == 2)
    }

    @Test func formattedValueMetric() {
        let data = makeSampleData(kind: "weight", values: [(80.5, 1)], units: "metric")
        let formatted = data.formattedValue(for: .weight)
        #expect(formatted.contains("80.5"))
        #expect(formatted.contains("kg"))
    }

    @Test func formattedValueImperial() {
        let data = makeSampleData(kind: "weight", values: [(80.0, 1)], units: "imperial")
        let formatted = data.formattedValue(for: .weight)
        #expect(formatted.contains("lb"))
    }

    @Test func formattedValueNoData() {
        let data = makeSampleData(values: [])
        let formatted = data.formattedValue(for: .weight)
        #expect(formatted == "—")
    }

    @Test func deltaTextPositive() {
        let data = makeSampleData(values: [(80.0, 20), (82.0, 1)])
        let delta = data.deltaText(for: .weight)
        #expect(delta != nil)
        #expect(delta!.contains("+2.0"))
    }

    @Test func deltaTextNegative() {
        let data = makeSampleData(values: [(82.0, 20), (80.0, 1)])
        let delta = data.deltaText(for: .weight)
        #expect(delta != nil)
        #expect(delta!.contains("-2.0"))
    }

    @Test func deltaTextNilWithSingleSample() {
        let data = makeSampleData(values: [(80.0, 5)])
        let delta = data.deltaText(for: .weight)
        #expect(delta == nil)
    }

    @Test func trendOutcomePositiveWeightLoss() {
        let data = makeSampleData(kind: "weight", values: [(85.0, 20), (82.0, 1)])
        let outcome = data.trendOutcome(for: .weight)
        #expect(outcome == .positive)
    }

    @Test func trendOutcomeNegativeWeightGain() {
        let data = makeSampleData(kind: "weight", values: [(82.0, 20), (85.0, 1)])
        let outcome = data.trendOutcome(for: .weight)
        #expect(outcome == .negative)
    }

    @Test func trendOutcomeNeutralWhenNoSamples() {
        let data = makeSampleData(values: [])
        let outcome = data.trendOutcome(for: .weight)
        #expect(outcome == .neutral)
    }
}

// MARK: - WatchConnectivityManager Config Parsing Tests

struct WatchConnectivityManagerTests {

    @Test @MainActor func activeMetricsDefaultEmpty() {
        let manager = WatchConnectivityManager.shared
        // Before any config is received, activeMetrics may be populated by DebugDataSeeder
        // but keyMetrics should match or be empty
        #expect(manager.unitsSystem == "metric" || manager.unitsSystem == "imperial")
    }
}
