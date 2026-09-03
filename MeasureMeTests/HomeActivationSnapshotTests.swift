import XCTest
@testable import MeasureMe

/// `HomeActivationCard` sizes its progress bar with
/// `geo.size.width * snapshot.progressFraction`. A non-finite fraction there is what
/// CoreGraphics reports as "Invalid frame dimension (negative or non-finite)", so the
/// arithmetic is asserted here rather than through the view — SwiftUI state on a
/// non-installed view is not observable from a test.
final class HomeActivationSnapshotTests: XCTestCase {

    private func makeSnapshot(stepIndex: Int, totalSteps: Int) -> HomeActivationSnapshot {
        HomeActivationSnapshot(
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            title: "title",
            body: "body",
            primaryCTA: "primary",
            skipCTA: "skip",
            dismissCTA: "dismiss"
        )
    }

    /// The visible task sequence is a filter that empties once every task is completed,
    /// skipped or already satisfied — the state a seeded UI-test run lands in.
    func testProgressFractionIsZeroWhenSequenceIsEmpty() {
        let snapshot = makeSnapshot(stepIndex: 0, totalSteps: 0)

        XCTAssertTrue(snapshot.progressFraction.isFinite)
        XCTAssertEqual(snapshot.progressFraction, 0)
    }

    func testProgressFractionStaysFiniteForEveryStepCount() {
        for total in 0...6 {
            for step in 0...max(total, 1) {
                let fraction = makeSnapshot(stepIndex: step, totalSteps: total).progressFraction
                XCTAssertTrue(fraction.isFinite, "step=\(step) total=\(total) produced \(fraction)")
                XCTAssertGreaterThanOrEqual(fraction, 0)
                XCTAssertLessThanOrEqual(fraction, 1)
            }
        }
    }

    func testProgressFractionReportsPartialProgress() {
        XCTAssertEqual(makeSnapshot(stepIndex: 1, totalSteps: 4).progressFraction, 0.25)
        XCTAssertEqual(makeSnapshot(stepIndex: 4, totalSteps: 4).progressFraction, 1)
    }
}
