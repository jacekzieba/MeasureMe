import Testing
import WatchConnectivity
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
}
