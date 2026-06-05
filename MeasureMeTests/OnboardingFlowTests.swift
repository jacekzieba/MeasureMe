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
            [.weight, .chest, .leftBicep, .waist]
        )
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .improveHealth),
            [.weight, .waist, .chest, .leftBicep]
        )
        XCTAssertEqual(
            GoalMetricPack.recommendedKinds(for: .trackHealth),
            [.weight, .waist]
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
        XCTAssertEqual(
            OnboardingCopy.priorityTitle(.improveHealth),
            FlowLocalization.app(
                "Recomposition",
                "Rekompozycja",
                "Recomposición",
                "Rekomposition",
                "Recomposition",
                "Recomposição"
            )
        )
        XCTAssertEqual(OnboardingView.WelcomeGoal.recomposition.priority, .improveHealth)
        XCTAssertEqual(OnboardingView.WelcomeGoal.recomposition.title, "Recomposition")
    }

    func testWelcomeGoalMapsToCurrentPriorityModel() {
        XCTAssertEqual(OnboardingView.WelcomeGoal.loseWeight.priority, .loseWeight)
        XCTAssertEqual(OnboardingView.WelcomeGoal.buildMuscle.priority, .buildMuscle)
        XCTAssertEqual(OnboardingView.WelcomeGoal.recomposition.priority, .improveHealth)
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.priority, .trackHealth)
    }

    func testInputStepsUseShortActivationFlowWithoutPremium() {
        XCTAssertEqual(
            OnboardingView.InputStep.allCases.map(\.analyticsName),
            ["welcome", "goal", "starting_point", "health_import"]
        )
        XCTAssertEqual(OnboardingView.InputStep.healthImport.rawValue, 3)
    }

    func testActivationTaskOrderingSupportsManualMeasurementBeforePhoto() {
        XCTAssertEqual(ActivationTask.initial, .firstMeasurement)
        XCTAssertEqual(ActivationTask.allCases, [.firstMeasurement, .chooseMetrics, .setReminders, .addPhoto, .connectHealth, .personalizeProfile, .explorePremium])
    }
}
