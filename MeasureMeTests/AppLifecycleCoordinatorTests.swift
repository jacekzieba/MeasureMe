import BackgroundTasks
import SwiftData
import XCTest
@testable import MeasureMe

@MainActor
final class AppLifecycleCoordinatorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        AppLifecycleCoordinator.resetDependencies()
    }

    override func tearDownWithError() throws {
        AppLifecycleCoordinator.resetDependencies()
        container = nil
        try super.tearDownWithError()
    }

    func testHandleWillResignActiveFlushesAndPersistsButSkipsBackupInXCTest() {
        var flushCount = 0
        var persistCount = 0
        var backupCount = 0
        AppLifecycleCoordinator.dependencies = AppLifecycleCoordinator.Dependencies(
            flushPendingWidgetWrites: { flushCount += 1 },
            persistCrashLogBuffer: { persistCount += 1 },
            runScheduledBackup: { _ in backupCount += 1 },
            submitBackgroundTaskRequest: { _ in }
        )

        AppLifecycleCoordinator.handleWillResignActive(container: container, isRunningXCTest: true)

        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(backupCount, 0)
    }

    func testHandleWillResignActiveFlushesAndPersistsWithoutContainer() {
        var flushCount = 0
        var persistCount = 0
        var backupCount = 0
        AppLifecycleCoordinator.dependencies = AppLifecycleCoordinator.Dependencies(
            flushPendingWidgetWrites: { flushCount += 1 },
            persistCrashLogBuffer: { persistCount += 1 },
            runScheduledBackup: { _ in backupCount += 1 },
            submitBackgroundTaskRequest: { _ in }
        )

        AppLifecycleCoordinator.handleWillResignActive(container: nil, isRunningXCTest: false)

        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(backupCount, 0)
    }

    func testHandleWillResignActiveRunsBackupOutsideXCTestWhenContainerExists() async {
        var flushCount = 0
        var persistCount = 0
        let backupRan = expectation(description: "backup ran")
        AppLifecycleCoordinator.dependencies = AppLifecycleCoordinator.Dependencies(
            flushPendingWidgetWrites: { flushCount += 1 },
            persistCrashLogBuffer: { persistCount += 1 },
            runScheduledBackup: { _ in backupRan.fulfill() },
            submitBackgroundTaskRequest: { _ in }
        )

        AppLifecycleCoordinator.handleWillResignActive(container: container, isRunningXCTest: false)

        await fulfillment(of: [backupRan], timeout: 1)
        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(persistCount, 1)
    }

    func testScheduleBackgroundBackupSubmitsExpectedProcessingRequest() throws {
        let before = Date()
        var submittedRequest: BGTaskRequest?
        AppLifecycleCoordinator.dependencies = AppLifecycleCoordinator.Dependencies(
            flushPendingWidgetWrites: {},
            persistCrashLogBuffer: {},
            runScheduledBackup: { _ in },
            submitBackgroundTaskRequest: { request in submittedRequest = request }
        )

        AppLifecycleCoordinator.scheduleBackgroundBackup()

        let request = try XCTUnwrap(submittedRequest as? BGProcessingTaskRequest)
        XCTAssertEqual(request.identifier, "com.jacek.measureme.icloud-backup")
        XCTAssertTrue(request.requiresNetworkConnectivity)
        let earliest = try XCTUnwrap(request.earliestBeginDate)
        XCTAssertGreaterThanOrEqual(earliest.timeIntervalSince(before), 86_300)
        XCTAssertLessThanOrEqual(earliest.timeIntervalSince(before), 86_500)
    }

    func testScheduleBackgroundAINotificationsSubmitsExpectedProcessingRequest() throws {
        let before = Date()
        var submittedRequest: BGTaskRequest?
        AppLifecycleCoordinator.dependencies = AppLifecycleCoordinator.Dependencies(
            flushPendingWidgetWrites: {},
            persistCrashLogBuffer: {},
            runScheduledBackup: { _ in },
            submitBackgroundTaskRequest: { request in submittedRequest = request }
        )

        AppLifecycleCoordinator.scheduleBackgroundAINotifications()

        let request = try XCTUnwrap(submittedRequest as? BGProcessingTaskRequest)
        XCTAssertEqual(request.identifier, "com.jacek.measureme.ai-notifications")
        XCTAssertFalse(request.requiresNetworkConnectivity)
        let earliest = try XCTUnwrap(request.earliestBeginDate)
        XCTAssertGreaterThanOrEqual(earliest.timeIntervalSince(before), 21_500)
        XCTAssertLessThanOrEqual(earliest.timeIntervalSince(before), 21_700)
    }
}
