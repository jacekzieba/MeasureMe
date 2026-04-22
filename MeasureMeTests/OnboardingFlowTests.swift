import XCTest
@testable import MeasureMe

final class OnboardingFlowTests: XCTestCase {
    func testRecommendedMetricPackMatchesPriority() {
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .loseWeight),
            [.weight, .waist]
        )
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .buildMuscle),
            [.chest, .leftBicep]
        )
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .improveHealth),
            [.waist, .chest]
        )
    }

    func testRecommendedMetricPackMergesMultipleGoalsWithoutDuplicates() {
        let merged = GoalMetricPack.recommendedKinds(for: [.buildMuscle, .trackHealth])

        XCTAssertTrue(merged.contains(.chest))
        XCTAssertTrue(merged.contains(.waist))
        XCTAssertTrue(merged.contains(.leftBicep))
        XCTAssertEqual(merged.count, Set(merged).count)
    }

    func testMaintainRecompKeepsImproveHealthRawValueForCompatibility() {
        XCTAssertEqual(OnboardingPriority.improveHealth.rawValue, "improveHealth")
        XCTAssertEqual(OnboardingCopy.priorityTitle(.improveHealth), "Recomposition")
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.priority, .improveHealth)
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.title, "Maintain / recomp")
    }

    func testWelcomeGoalMapsToCurrentPriorityModel() {
        XCTAssertEqual(OnboardingView.WelcomeGoal.loseWeight.priority, .loseWeight)
        XCTAssertEqual(OnboardingView.WelcomeGoal.buildMuscle.priority, .buildMuscle)
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.priority, .improveHealth)
    }

    func testActivationTaskOrderingSupportsManualMeasurementBeforePhoto() {
        XCTAssertEqual(ActivationTask.initial, .addPhoto)
        XCTAssertEqual(ActivationTask.allCases, [.firstMeasurement, .addPhoto, .chooseMetrics, .setGoal])
    }
}
