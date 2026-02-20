import XCTest

final class PerformanceUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode"]
    }

    @MainActor
    func testAppLaunchDurationPerformance() throws {
#if targetEnvironment(simulator)
        measure(metrics: [
            XCTApplicationLaunchMetric()
        ]) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        }
#else
        throw XCTSkip("XCTApplicationLaunchMetric is unstable on this physical-device setup; use App Launch Instruments trace for device launch profiling.")
#endif
    }

    @MainActor
    func testAppStartupResourcePerformance() {
        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app)
        ]) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        }
    }

    @MainActor
    func testTabSwitchingPerformance() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app)
        ]) {
            tapTab(named: "Measurements")
            tapTab(named: "Photos")
            tapTab(named: "Settings")
            tapTab(named: "Home")
        }
    }

    @MainActor
    func testSeedPhotosForStorageAudit() {
        app.launchArguments = ["-uiTestMode", "-uiTestSeedPhotos", "120"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        sleep(2)
        app.terminate()
    }

    private func tapTab(named name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected tab \(name) to exist.")
        button.tap()
    }
}
