import XCTest
@testable import MeasureMe

final class OnboardingFlowTests: XCTestCase {
    func testRecommendedMetricPackMatchesPriority() {
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .loseWeight),
            [.weight, .waist, .bodyFat]
        )
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .buildMuscle),
            [.weight, .chest, .leftBicep, .rightBicep, .leftThigh, .rightThigh]
        )
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .improveHealth),
            [.weight, .waist, .bodyFat, .height]
        )
    }

    func testRecommendedMetricPackMergesMultipleGoalsWithoutDuplicates() {
        let merged = GoalMetricPack.recommendedKinds(for: [.buildMuscle, .trackHealth])

        XCTAssertEqual(merged.first, .weight)
        XCTAssertTrue(merged.contains(.chest))
        XCTAssertTrue(merged.contains(.waist))
        XCTAssertTrue(merged.contains(.height))
        XCTAssertEqual(merged.count, Set(merged).count)
    }

    func testActivationTaskOrderingStartsWithMetricAndEndsWithCelebrate() {
        XCTAssertEqual(ActivationTask.initial, .addMetric)
        XCTAssertEqual(ActivationTask.allCases.last, .celebrate)
    }
}
