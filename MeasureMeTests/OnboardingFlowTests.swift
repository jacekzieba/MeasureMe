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
            [.chest, .leftBicep, .rightBicep]
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
        XCTAssertTrue(merged.contains(.rightBicep))
        XCTAssertEqual(merged.count, Set(merged).count)
    }

    func testTrackedMetricPackAlwaysIncludesWeightAndBodyFat() {
        for priority in OnboardingPriority.allCases {
            let tracked = GoalMetricPack.trackedKinds(for: priority)

            XCTAssertTrue(tracked.contains(.weight), "\(priority.rawValue) should keep weight enabled")
            XCTAssertTrue(tracked.contains(.bodyFat), "\(priority.rawValue) should keep body fat enabled")
            XCTAssertEqual(tracked.count, Set(tracked).count)
        }

        XCTAssertEqual(
            GoalMetricPack.trackedKinds(for: .buildMuscle),
            [.weight, .bodyFat, .chest, .leftBicep, .rightBicep]
        )
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
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.priority, .improveHealth)
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.title, "Maintain / recomp")
    }

    func testWelcomeGoalMapsToCurrentPriorityModel() {
        XCTAssertEqual(OnboardingView.WelcomeGoal.loseWeight.priority, .loseWeight)
        XCTAssertEqual(OnboardingView.WelcomeGoal.buildMuscle.priority, .buildMuscle)
        XCTAssertEqual(OnboardingView.WelcomeGoal.trackHealth.priority, .improveHealth)
    }

    func testInputStepsEndAtOptionalHealthStep() {
        XCTAssertEqual(
            OnboardingView.InputStep.allCases.map(\.analyticsName),
            ["welcome", "profile", "metrics", "photos", "health"]
        )
        XCTAssertEqual(OnboardingView.InputStep.health.rawValue, 4)
    }

    func testActivationTaskOrderingSupportsManualMeasurementBeforePhoto() {
        XCTAssertEqual(ActivationTask.initial, .addPhoto)
        XCTAssertEqual(ActivationTask.allCases, [.firstMeasurement, .addPhoto, .personalizeProfile, .connectHealth, .chooseMetrics, .setReminders, .explorePremium])
    }
}
