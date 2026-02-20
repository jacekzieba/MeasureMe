import XCTest
@testable import MeasureMe

final class AuditConfigTests: XCTestCase {
    func testFixedDateParsesFromLaunchArgument() throws {
        let config = AuditConfig.from(
            args: ["MeasureMe", "-auditCapture", "-fixedDate", "2026-02-20T12:00:00Z"],
            environment: [:]
        )

        let fixedDate = try XCTUnwrap(config.fixedDate)
        XCTAssertEqual(fixedDate.timeIntervalSince1970, 1_771_588_800, accuracy: 0.001)
    }

    func testFixedDateParsesFromEnvironmentWhenArgumentMissing() throws {
        let config = AuditConfig.from(
            args: ["MeasureMe"],
            environment: ["FIXED_DATE": "2026-02-20T12:00:00Z"]
        )

        let fixedDate = try XCTUnwrap(config.fixedDate)
        XCTAssertEqual(fixedDate.timeIntervalSince1970, 1_771_588_800, accuracy: 0.001)
    }

    func testLaunchArgumentFixedDateTakesPriorityOverEnvironment() throws {
        let config = AuditConfig.from(
            args: ["MeasureMe", "-fixedDate", "2026-02-20T12:00:00Z"],
            environment: ["FIXED_DATE": "2025-01-01T00:00:00Z"]
        )

        let fixedDate = try XCTUnwrap(config.fixedDate)
        XCTAssertEqual(fixedDate.timeIntervalSince1970, 1_771_588_800, accuracy: 0.001)
    }

    func testAuditRouteParsesFromLaunchArguments() {
        let config = AuditConfig.from(
            args: ["MeasureMe", "-auditCapture", "-auditRoute", "settings"],
            environment: [:]
        )

        XCTAssertEqual(config.route, .settings)
        XCTAssertTrue(config.isEnabled)
    }

    func testFixedDateNilWhenNoValueProvided() {
        let config = AuditConfig.from(
            args: ["MeasureMe", "-auditCapture"],
            environment: [:]
        )

        XCTAssertNil(config.fixedDate)
    }
}
