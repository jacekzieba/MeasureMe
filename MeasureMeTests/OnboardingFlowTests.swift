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

    func testMaintainRecompKeepsImproveHealthRawValueForCompatibility() {
        XCTAssertEqual(OnboardingPriority.improveHealth.rawValue, "improveHealth")
        XCTAssertEqual(OnboardingCopy.priorityTitle(.improveHealth), "Maintain / recomp")
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.priority, .improveHealth)
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.title, "Maintain / recomp")
    }

    func testPrioritySelectionPolicyCapsAtTwoSelections() {
        var selected: Set<OnboardingPriority> = []

        selected = OnboardingPrioritySelectionPolicy.toggled(.loseWeight, in: selected)
        selected = OnboardingPrioritySelectionPolicy.toggled(.buildMuscle, in: selected)
        selected = OnboardingPrioritySelectionPolicy.toggled(.improveHealth, in: selected)

        XCTAssertEqual(selected, [.loseWeight, .buildMuscle])

        selected = OnboardingPrioritySelectionPolicy.toggled(.loseWeight, in: selected)
        selected = OnboardingPrioritySelectionPolicy.toggled(.improveHealth, in: selected)

        XCTAssertEqual(selected, [.buildMuscle, .improveHealth])
    }

    func testActivationTaskOrderingSupportsManualMeasurementBeforePhoto() {
        XCTAssertEqual(ActivationTask.initial, .addPhoto)
        XCTAssertEqual(ActivationTask.allCases, [.firstMeasurement, .addPhoto, .chooseMetrics, .setGoal])
    }
}
