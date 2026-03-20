import XCTest
@testable import MeasureMe

final class SettingsExporterPDFSmokeTests: XCTestCase {
    func testBuildMetricsPDF_ReturnsNonEmptyPDFDataWithValidHeader() {
        let date = Date(timeIntervalSince1970: 1_736_500_000)
        let rows = [
            SettingsExporter.MetricCSVRowSnapshot(
                kindRaw: MetricKind.weight.rawValue,
                metricTitle: MetricKind.weight.englishTitle,
                metricValue: 80.0,
                metricUnit: "kg",
                displayValue: 80.0,
                unit: "kg",
                date: date
            )
        ]
        let goals = [
            SettingsExporter.MetricGoalSnapshot(
                kindRaw: MetricKind.weight.rawValue,
                metricTitle: MetricKind.weight.englishTitle,
                direction: MetricGoal.Direction.decrease.rawValue,
                targetMetricValue: 75.0,
                targetMetricUnit: "kg",
                targetDisplayValue: 75.0,
                targetDisplayUnit: "kg",
                startMetricValue: 82.0,
                startDisplayValue: 82.0,
                startDate: date,
                createdDate: date
            )
        ]

        let pdfData = SettingsExporter.buildMetricsPDF(
            metrics: rows,
            goals: goals,
            unitsSystem: "metric",
            dateRange: (start: date, end: date.addingTimeInterval(3600)),
            logoImage: nil
        )

        XCTAssertGreaterThan(pdfData.count, 100)
        let header = String(data: pdfData.prefix(5), encoding: .ascii)
        XCTAssertEqual(header, "%PDF-")
    }
}
