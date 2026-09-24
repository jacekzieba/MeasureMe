import Testing
import WatchConnectivity
import SwiftData
@testable import MeasureMe

struct WatchSessionManagerTests {
    @Test func sendsOnSimulatorWhenActivatedEvenIfNotPaired() {
        let result = WatchSessionManager.shouldSendApplicationContext(
            activationState: .activated,
            isPaired: false,
            isWatchAppInstalled: false,
            isRunningOnSimulator: true
        )

        #expect(result == true)
    }

    @Test func doesNotSendWhenNotActivatedOnSimulator() {
        let result = WatchSessionManager.shouldSendApplicationContext(
            activationState: .inactive,
            isPaired: true,
            isWatchAppInstalled: true,
            isRunningOnSimulator: true
        )

        #expect(result == false)
    }

    @Test func sendsOnDeviceWhenActivatedAndWatchReady() {
        let result = WatchSessionManager.shouldSendApplicationContext(
            activationState: .activated,
            isPaired: true,
            isWatchAppInstalled: true,
            isRunningOnSimulator: false
        )

        #expect(result == true)
    }

    @Test func doesNotSendOnDeviceWhenNotPaired() {
        let result = WatchSessionManager.shouldSendApplicationContext(
            activationState: .activated,
            isPaired: false,
            isWatchAppInstalled: true,
            isRunningOnSimulator: false
        )

        #expect(result == false)
    }

    @Test func doesNotSendOnDeviceWhenWatchAppMissing() {
        let result = WatchSessionManager.shouldSendApplicationContext(
            activationState: .activated,
            isPaired: true,
            isWatchAppInstalled: false,
            isRunningOnSimulator: false
        )

        #expect(result == false)
    }

    /// The receive path lost its HealthKit write (the watch already writes to Health itself);
    /// the measurement must still reach the store.
    @MainActor
    @Test func watchMeasurementIsSaved() async throws {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        WatchSessionManager.shared.configure(container: container)

        WatchSessionManager.shared.session(WCSession.default, didReceiveUserInfo: [
            "type": "measurement",
            "entries": [["kind": "weight", "metricValue": 80.0, "date": 1_700_000_000.0]]
        ])

        let context = ModelContext(container)
        var attempts = 0
        while try context.fetchCount(FetchDescriptor<MetricSample>()) == 0, attempts < 100 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try context.fetchCount(FetchDescriptor<MetricSample>()) == 1)
    }
}

