import XCTest
@testable import MeasureMe

@MainActor
final class AppNavigationRouteDispatcherTests: XCTestCase {
    private let appGroupID = "group.com.jacek.measureme"
    private let pendingKey = "widget_pending_quick_add_kind"

    override func tearDownWithError() throws {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: pendingKey)
        try super.tearDownWithError()
    }

    func testConsumePendingRoute_FromWidgetAppGroup_WithMetric() {
        UserDefaults(suiteName: appGroupID)?.set(MetricKind.waist.rawValue, forKey: pendingKey)

        let route = AppNavigationRouteDispatcher.consumePendingRoute()

        XCTAssertEqual(route, .quickAdd(kindRaw: MetricKind.waist.rawValue))
        XCTAssertNil(UserDefaults(suiteName: appGroupID)?.string(forKey: pendingKey))
    }

    func testConsumePendingRoute_FromWidgetAppGroup_WithoutMetric() {
        UserDefaults(suiteName: appGroupID)?.set("__NONE__", forKey: pendingKey)

        let route = AppNavigationRouteDispatcher.consumePendingRoute()

        XCTAssertEqual(route, .quickAdd(kindRaw: nil))
        XCTAssertNil(UserDefaults(suiteName: appGroupID)?.string(forKey: pendingKey))
    }
}
