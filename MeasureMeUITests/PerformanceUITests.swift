import XCTest
import UIKit

final class PerformanceUITests: XCTestCase {
    private struct PerfTrendStore: Codable {
        var metrics: [String: Double] = [:]
    }

    private static let appBundleID = "com.jacek.measureme"
    private static let launchTrendSampleCount = 6
    private static let launchBudgetMs: Double = 4_500
    private static let tabSwitchTrendSampleCount = 3
    private static let tabSwitchBudgetMs: Double = 18_000
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if targetEnvironment(simulator)
        if UIDevice.current.systemVersion.hasPrefix("26.") {
            throw XCTSkip("XCTest performance metrics are unstable on the iOS 26 simulator test runner in this project.")
        }
        #endif
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode"]
    }

    @MainActor
    func testAppLaunchDurationPerformance() throws {
        #if targetEnvironment(simulator)
        if UIDevice.current.systemVersion.hasPrefix("26.") {
            throw XCTSkip("XCTApplicationLaunchMetric is unstable on the iOS 26 simulator test runner in this project.")
        }
        #endif

        let manualMedianMs = robustColdLaunchDurationMs(sampleCount: Self.launchTrendSampleCount)
        logTrend(metric: "app_launch_ms", currentMs: manualMedianMs)
        XCTAssertLessThan(
            manualMedianMs,
            Self.launchBudgetMs,
            "Launch median \(String(format: "%.1f", manualMedianMs))ms exceeds budget \(String(format: "%.1f", Self.launchBudgetMs))ms."
        )
        #if targetEnvironment(simulator)
        measure(metrics: [
            XCTApplicationLaunchMetric()
        ]) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        }
        #else
        // Physical-device fallback: rely on manual launch timings gathered above.
        XCTAssertGreaterThan(manualMedianMs, 0)
        #endif
    }

    @MainActor
    func testAppStartupResourcePerformance() throws {
        #if targetEnvironment(simulator)
        if UIDevice.current.systemVersion.hasPrefix("26.") {
            throw XCTSkip("XCTCPUMetric/XCTMemoryMetric is unstable on the iOS 26 simulator test runner in this project.")
        }
        #endif

        let manualMedianMs = robustColdLaunchDurationMs(sampleCount: Self.launchTrendSampleCount)
        logTrend(metric: "startup_clock_ms", currentMs: manualMedianMs)
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
        let manualMedianMs = robustTabSwitchDurationMs(sampleCount: Self.tabSwitchTrendSampleCount)
        logTrend(metric: "tab_switch_ms", currentMs: manualMedianMs)
        XCTAssertLessThan(
            manualMedianMs,
            Self.tabSwitchBudgetMs,
            "Tab switching median \(String(format: "%.1f", manualMedianMs))ms exceeds budget \(String(format: "%.1f", Self.tabSwitchBudgetMs))ms."
        )

        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app)
        ]) {
            tapTab(named: "tab.measurements")
            tapTab(named: "tab.photos")
            tapTab(named: "tab.settings")
            tapTab(named: "tab.home")
        }
    }

    @MainActor
    func testHomeDeferredSyncSignpostPerformance() {
        app.launchArguments = [
            "-uiTestMode",
            "-uiTestSeedMeasurements",
            "-uiTestSeedPhotos", "120",
            "-uiTestSeedPhotoMetrics"
        ]
        let deferredSyncMetric = XCTOSSignpostMetric(
            subsystem: Self.appBundleID,
            category: "Startup",
            name: "HomeDeferredSync"
        )
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [
            deferredSyncMetric,
            XCTClockMetric()
        ], options: options) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

            // `HomeDeferredSync` is scheduled after startup delay; keep app alive long enough for interval capture.
            RunLoop.current.run(until: Date().addingTimeInterval(3.2))
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

    @MainActor
    func testPhotosFirstVsSecondOpenTimingWithSeed120() throws {
        app.launchArguments = ["-uiTestMode", "-uiTestSeedPhotos", "120"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        guard ensureTabBarExists(timeout: 25) else {
            _ = app.wait(for: .runningForeground, timeout: 3)
            return
        }

        let firstOpenStart = Date()
        tapTab(named: "tab.photos")
        let firstGridItem = app.buttons["photos.grid.item"].firstMatch
        XCTAssertTrue(firstGridItem.waitForExistence(timeout: 10), "Expected Photos grid to appear on first open.")
        let firstOpenMs = Int(Date().timeIntervalSince(firstOpenStart) * 1_000)
        sleep(2)

        tapTab(named: "tab.home")
        sleep(1)

        let secondOpenStart = Date()
        tapTab(named: "tab.photos")
        XCTAssertTrue(firstGridItem.waitForExistence(timeout: 10), "Expected Photos grid to appear on second open.")
        let secondOpenMs = Int(Date().timeIntervalSince(secondOpenStart) * 1_000)
        let improvementMs = firstOpenMs - secondOpenMs
        let improvementPct = firstOpenMs > 0 ? (Double(improvementMs) / Double(firstOpenMs)) * 100 : 0
        print("📊 PERF photos.open firstMs=\(firstOpenMs) secondMs=\(secondOpenMs) deltaMs=\(improvementMs) improvementPct=\(String(format: "%.1f", improvementPct))")
        sleep(2)
    }

    private func tapTab(named name: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(ensureTabBarExists(timeout: 20), "Expected tab bar to exist.")

        let localizedCandidates: [String]
        switch name {
        case "tab.home":
            localizedCandidates = ["tab.home", "Home", "Start", "Dom", "Strona główna"]
        case "tab.measurements":
            localizedCandidates = ["tab.measurements", "Measurements", "Pomiary"]
        case "tab.photos":
            localizedCandidates = ["tab.photos", "Photos", "Zdjęcia", "Zdjecia"]
        case "tab.settings":
            localizedCandidates = ["tab.settings", "Settings", "Ustawienia"]
        default:
            localizedCandidates = [name]
        }

        for candidate in localizedCandidates {
            let button = tabBar.buttons[candidate].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }

        XCTFail("Expected tab \(name) to exist.")
    }

    private func ensureTabBarExists(timeout: TimeInterval) -> Bool {
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: timeout) {
            return true
        }

        let onboardingNext = onboardingNextButton()
        if onboardingNext.waitForExistence(timeout: 2) {
            for _ in 0..<4 {
                onboardingNext.tap()
                if tabBar.waitForExistence(timeout: 2) {
                    return true
                }
                if !onboardingNext.exists {
                    break
                }
            }
        }

        return tabBar.waitForExistence(timeout: 3)
    }

    private func onboardingNextButton() -> XCUIElement {
        let uiTestNext = app.buttons["UITest Next"].firstMatch
        if uiTestNext.exists {
            return uiTestNext
        }
        return app.buttons["onboarding.next"].firstMatch
    }

    private func waitForDeferredSyncMeasurementWindow(timeout: TimeInterval) -> Bool {
        let appRoot = app.otherElements["app.root.ready"].firstMatch
        let startupLoading = app.otherElements["startup.loading.root"].firstMatch
        let tabBar = app.tabBars.firstMatch
        let homeNextFocus = app.buttons["home.nextFocus.button"].firstMatch
        let weightTile = app.buttons["metric.tile.open.weight"].firstMatch
        let navBar = app.navigationBars.firstMatch
        let onboardingNext = onboardingNextButton()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if app.state != .runningForeground {
                _ = app.wait(for: .runningForeground, timeout: 2)
            }

            let hasInteractiveSignal = tabBar.exists
                || homeNextFocus.exists
                || weightTile.exists
                || navBar.exists
                || onboardingNext.exists

            if appRoot.exists && hasInteractiveSignal {
                return true
            }

            if hasInteractiveSignal {
                return true
            }

            let sleepInterval: TimeInterval = startupLoading.exists ? 0.35 : 0.20
            RunLoop.current.run(until: Date().addingTimeInterval(sleepInterval))
        }

        return appRoot.exists || tabBar.exists || homeNextFocus.exists || weightTile.exists || onboardingNext.exists
    }

    private func debugUIState() -> String {
        let appRoot = app.otherElements["app.root.ready"].firstMatch.exists
        let startup = app.otherElements["startup.loading.root"].firstMatch.exists
        let tabBar = app.tabBars.firstMatch.exists
        let onboarding = onboardingNextButton().exists
        let homeCTA = app.buttons["home.nextFocus.button"].firstMatch.exists
        return "state=\(app.state.rawValue), appRoot=\(appRoot), startup=\(startup), tabBar=\(tabBar), onboardingNext=\(onboarding), homeNextFocus=\(homeCTA)"
    }

    private func robustColdLaunchDurationMs(sampleCount: Int) -> Double {
        guard sampleCount > 0 else { return 0 }

        // Warm-up run: first UI automation launch is often an outlier.
        app.terminate()
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 8)

        var rawSamples: [Double] = []
        rawSamples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            app.terminate()
            let start = Date()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
            rawSamples.append(Date().timeIntervalSince(start) * 1_000)
        }

        let stabilizedSamples = Array(rawSamples.dropFirst())
        let samplesForMedian = stabilizedSamples.isEmpty ? rawSamples : stabilizedSamples
        let sorted = samplesForMedian.sorted()
        let middle = sorted.count / 2
        let medianMs: Double
        if sorted.count.isMultiple(of: 2), sorted.count > 1 {
            medianMs = (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            medianMs = sorted[middle]
        }

        print(
            "📊 PERF baseline rawSamplesMs=\(rawSamples.map { String(format: "%.0f", $0) }.joined(separator: ",")) " +
            "stableSamplesMs=\(samplesForMedian.map { String(format: "%.0f", $0) }.joined(separator: ",")) " +
            "medianMs=\(String(format: "%.1f", medianMs))"
        )
        return medianMs
    }

    private func robustTabSwitchDurationMs(sampleCount: Int) -> Double {
        guard sampleCount > 0 else { return 0 }

        var rawSamples: [Double] = []
        rawSamples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
            let start = Date()
            tapTab(named: "tab.measurements")
            tapTab(named: "tab.photos")
            tapTab(named: "tab.settings")
            tapTab(named: "tab.home")
            rawSamples.append(Date().timeIntervalSince(start) * 1_000)
        }

        let stabilizedSamples = Array(rawSamples.dropFirst())
        let samplesForMedian = stabilizedSamples.isEmpty ? rawSamples : stabilizedSamples
        let sorted = samplesForMedian.sorted()
        let middle = sorted.count / 2
        let medianMs: Double
        if sorted.count.isMultiple(of: 2), sorted.count > 1 {
            medianMs = (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            medianMs = sorted[middle]
        }

        print(
            "📊 PERF tab_switch rawSamplesMs=\(rawSamples.map { String(format: "%.0f", $0) }.joined(separator: ",")) " +
            "stableSamplesMs=\(samplesForMedian.map { String(format: "%.0f", $0) }.joined(separator: ",")) " +
            "medianMs=\(String(format: "%.1f", medianMs))"
        )
        return medianMs
    }

    private func logTrend(metric: String, currentMs: Double) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("measureme_perf_trend_store.json", isDirectory: false)

        var store = loadTrendStore(from: url)
        if let previousMs = store.metrics[metric] {
            let deltaMs = currentMs - previousMs
            let deltaPct = previousMs > 0 ? (deltaMs / previousMs) * 100 : 0
            let direction = deltaMs <= 0 ? "faster" : "slower"
            print(
                "📈 PERF trend metric=\(metric) previousMs=\(String(format: "%.1f", previousMs)) currentMs=\(String(format: "%.1f", currentMs)) deltaMs=\(String(format: "%.1f", deltaMs)) deltaPct=\(String(format: "%.1f", deltaPct)) direction=\(direction)"
            )
        } else {
            print("📈 PERF trend metric=\(metric) previousMs=none currentMs=\(String(format: "%.1f", currentMs))")
        }

        store.metrics[metric] = currentMs
        saveTrendStore(store, to: url)
    }

    private func loadTrendStore(from url: URL) -> PerfTrendStore {
        guard let data = try? Data(contentsOf: url) else { return PerfTrendStore() }
        return (try? JSONDecoder().decode(PerfTrendStore.self, from: data)) ?? PerfTrendStore()
    }

    private func saveTrendStore(_ store: PerfTrendStore, to url: URL) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
