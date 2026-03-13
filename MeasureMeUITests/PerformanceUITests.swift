import XCTest

final class PerformanceUITests: XCTestCase {
    private struct PerfTrendStore: Codable {
        var metrics: [String: Double] = [:]
    }

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode"]
    }

    @MainActor
    func testAppLaunchDurationPerformance() throws {
        let manualAverageMs = averageColdLaunchDurationMs(sampleCount: 2)
        logTrend(metric: "app_launch_ms", currentMs: manualAverageMs)
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
        XCTAssertGreaterThan(manualAverageMs, 0)
        #endif
    }

    @MainActor
    func testAppStartupResourcePerformance() {
        let manualAverageMs = averageColdLaunchDurationMs(sampleCount: 2)
        logTrend(metric: "startup_clock_ms", currentMs: manualAverageMs)
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
            tapTab(named: "tab.measurements")
            tapTab(named: "tab.photos")
            tapTab(named: "tab.settings")
            tapTab(named: "tab.home")
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
        if uiTestNext.waitForExistence(timeout: 0.5) {
            return uiTestNext
        }
        return app.buttons["onboarding.next"].firstMatch
    }

    private func averageColdLaunchDurationMs(sampleCount: Int) -> Double {
        guard sampleCount > 0 else { return 0 }
        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            app.terminate()
            let start = Date()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
            samples.append(Date().timeIntervalSince(start) * 1_000)
        }
        let averageMs = samples.reduce(0, +) / Double(samples.count)
        print("📊 PERF baseline samplesMs=\(samples.map { String(format: "%.0f", $0) }.joined(separator: ",")) avgMs=\(String(format: "%.1f", averageMs))")
        return averageMs
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
