import XCTest
@testable import MeasureMe

/// The selection both Measurements layouts share on iPhone Duo: the compact stack (outer display)
/// pushes `path`, and the list-and-detail split (inner display) shows its last entry.
final class MeasurementsDetailSelectionTests: XCTestCase {
    private let custom = "custom_neck"

    func testSplitStartsOnTheFirstActiveBuiltInMetric() {
        XCTAssertEqual(
            MeasurementsDetailSelection().splitDetail(activeKinds: [.waist, .weight], activeCustomIdentifiers: [custom]),
            .metric(.waist)
        )
    }

    func testSplitFallsBackToACustomMetricWhenNoBuiltInIsTracked() {
        XCTAssertEqual(
            MeasurementsDetailSelection().splitDetail(activeKinds: [], activeCustomIdentifiers: [custom]),
            .customMetric(custom)
        )
    }

    func testSplitIsEmptyOnlyWithoutAnyTrackedMetric() {
        XCTAssertNil(MeasurementsDetailSelection().splitDetail(activeKinds: [], activeCustomIdentifiers: []))
    }

    func testOpeningAMetricReplacesWhateverWasOpen() {
        var selection = MeasurementsDetailSelection()
        selection.openCustomMetric(custom)
        selection.openMetric(.bodyFat)

        XCTAssertEqual(selection.path, [.metric(.bodyFat)])
        XCTAssertEqual(
            selection.splitDetail(activeKinds: [.weight], activeCustomIdentifiers: [custom]),
            .metric(.bodyFat)
        )
    }

    /// Folding hands the path to the compact stack, so a custom metric must not leave a built-in
    /// detail underneath it.
    func testOpeningACustomMetricReplacesTheBuiltInOne() {
        var selection = MeasurementsDetailSelection()
        selection.openMetric(.weight)
        selection.openCustomMetric(custom)

        XCTAssertEqual(selection.path, [.customMetric(custom)])
        XCTAssertEqual(
            selection.splitDetail(activeKinds: [.weight], activeCustomIdentifiers: [custom]),
            .customMetric(custom)
        )
    }

    /// Unfolding shows the compact stack's top entry in the split's detail column.
    func testTheSplitShowsTheLastMetricPushedOnTheCompactStack() {
        var selection = MeasurementsDetailSelection()
        selection.path = [.metric(.weight), .metric(.hips)]

        XCTAssertEqual(
            selection.splitDetail(activeKinds: [.weight], activeCustomIdentifiers: []),
            .metric(.hips)
        )
    }

    func testPoppingBackToTheListReturnsToTheDefaultDetail() {
        var selection = MeasurementsDetailSelection()
        selection.openCustomMetric(custom)
        selection.path.removeLast()

        XCTAssertEqual(
            selection.splitDetail(activeKinds: [.weight], activeCustomIdentifiers: [custom]),
            .metric(.weight)
        )
    }

    /// A custom metric switched off in Settings while open must not stay in the detail column.
    func testAnUntrackedCustomMetricFallsBackToTheDefaultDetail() {
        var selection = MeasurementsDetailSelection()
        selection.openCustomMetric(custom)

        XCTAssertEqual(
            selection.splitDetail(activeKinds: [.weight], activeCustomIdentifiers: []),
            .metric(.weight)
        )
    }

    /// The compact stack would otherwise push an empty page for a custom metric switched off in Settings.
    func testDroppingUntrackedCustomMetricsKeepsTrackedEntries() {
        var selection = MeasurementsDetailSelection()
        selection.path = [.metric(.weight), .customMetric(custom), .customMetric("custom_other")]

        selection.dropUntrackedCustomMetrics(activeCustomIdentifiers: ["custom_other"])

        XCTAssertEqual(selection.path, [.metric(.weight), .customMetric("custom_other")])
    }
}
