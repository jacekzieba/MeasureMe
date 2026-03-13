import XCTest
@testable import MeasureMe

final class AddMeasurementIntentValidationTests: XCTestCase {
    func testActiveOptionsReturnOnlyEnabledMetrics() {
        let suiteName = "AddMeasurementIntentValidationTests.active.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: "metric_weight_enabled")
        defaults.set(false, forKey: "metric_bodyFat_enabled")
        defaults.set(false, forKey: "metric_nonFatMass_enabled")
        defaults.set(true, forKey: "metric_waist_enabled")

        let options = AppIntentMetricResolver.activeIntentMetrics(defaults: defaults)
        XCTAssertEqual(options, [.weight, .waist])
    }

    @MainActor
    func testValidatorConvertsImperialWeightToMetric() throws {
        let result = try AddMeasurementIntentValidator.validateAndConvert(
            metric: .weight,
            inputValue: 220,
            unitsSystem: "imperial",
            activeMetrics: [.weight]
        )

        XCTAssertEqual(result.kind, .weight)
        XCTAssertEqual(result.metricValue, 99.7903214, accuracy: 0.000001)
    }

    @MainActor
    func testValidatorRejectsInactiveMetric() {
        XCTAssertThrowsError(
            try AddMeasurementIntentValidator.validateAndConvert(
                metric: .waist,
                inputValue: 80,
                unitsSystem: "metric",
                activeMetrics: [.weight]
            )
        ) { error in
            XCTAssertEqual(error as? AddMeasurementIntentError, .metricNotActive)
        }
    }
}
