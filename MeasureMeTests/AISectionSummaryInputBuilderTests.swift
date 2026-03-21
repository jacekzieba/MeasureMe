import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class AISectionSummaryInputBuilderTests: XCTestCase {

    func testMetricsInputAddsBodyRecompositionSignal() {
        let now = Date()
        let weightOld = MetricSample(kind: .weight, value: 80.0, date: now.addingTimeInterval(-29 * 86_400))
        let weightNew = MetricSample(kind: .weight, value: 80.2, date: now.addingTimeInterval(-1 * 86_400))
        let waistOld = MetricSample(kind: .waist, value: 90.0, date: now.addingTimeInterval(-29 * 86_400))
        let waistNew = MetricSample(kind: .waist, value: 88.4, date: now.addingTimeInterval(-1 * 86_400))
        let leanOld = MetricSample(kind: .leanBodyMass, value: 60.0, date: now.addingTimeInterval(-29 * 86_400))
        let leanNew = MetricSample(kind: .leanBodyMass, value: 60.3, date: now.addingTimeInterval(-1 * 86_400))

        let input = AISectionSummaryInputBuilder.metricsInput(
            userName: "Jacek",
            activeKinds: [.weight, .waist, .leanBodyMass],
            latestByKind: [
                .weight: weightNew,
                .waist: waistNew,
                .leanBodyMass: leanNew
            ],
            samplesByKind: [
                .weight: [weightOld, weightNew],
                .waist: [waistOld, waistNew],
                .leanBodyMass: [leanOld, leanNew]
            ],
            unitsSystem: "metric"
        )

        XCTAssertNotNil(input)
        XCTAssertTrue(input?.contextLines.contains(where: { $0.contains("body recomposition") }) == true)
    }

    func testHealthInputAddsScaleVsWaistMismatchSignal() {
        let now = Date()
        let weightOld = MetricSample(kind: .weight, value: 70.4, date: now.addingTimeInterval(-29 * 86_400))
        let weightNew = MetricSample(kind: .weight, value: 70.0, date: now.addingTimeInterval(-1 * 86_400))
        let waistOld = MetricSample(kind: .waist, value: 89.0, date: now.addingTimeInterval(-29 * 86_400))
        let waistNew = MetricSample(kind: .waist, value: 88.0, date: now.addingTimeInterval(-1 * 86_400))

        let input = AISectionSummaryInputBuilder.healthInput(
            userName: "Jacek",
            userGender: .male,
            latestWaist: 88.0,
            latestHeight: 175.0,
            latestWeight: 70.0,
            latestHips: 96.0,
            latestBodyFat: nil,
            latestLeanMass: nil,
            samplesByKind: [
                .weight: [weightOld, weightNew],
                .waist: [waistOld, waistNew]
            ],
            unitsSystem: "metric"
        )

        XCTAssertNotNil(input)
        XCTAssertTrue(input?.contextLines.contains(where: { $0.contains("BMI looks normal") }) == true)
    }

    func testPhysiqueInputAddsVTaperSignal() {
        let now = Date()
        let shouldersOld = MetricSample(kind: .shoulders, value: 118.0, date: now.addingTimeInterval(-29 * 86_400))
        let shouldersNew = MetricSample(kind: .shoulders, value: 120.0, date: now.addingTimeInterval(-1 * 86_400))
        let waistOld = MetricSample(kind: .waist, value: 88.0, date: now.addingTimeInterval(-29 * 86_400))
        let waistNew = MetricSample(kind: .waist, value: 86.5, date: now.addingTimeInterval(-1 * 86_400))

        let input = AISectionSummaryInputBuilder.physiqueInput(
            userName: "Jacek",
            userGender: .male,
            latestWaist: 86.5,
            latestHeight: 182.0,
            latestBodyFat: 16.0,
            latestShoulders: 120.0,
            latestChest: nil,
            latestBust: nil,
            latestHips: 97.0,
            samplesByKind: [
                .shoulders: [shouldersOld, shouldersNew],
                .waist: [waistOld, waistNew]
            ],
            unitsSystem: "metric"
        )

        XCTAssertNotNil(input)
        XCTAssertTrue(input?.contextLines.contains(where: { $0.contains("V-taper") }) == true)
    }
}
