import XCTest
@testable import MeasureMe

final class InsightConcurrencyTests: XCTestCase {

    private var originalSuiteName: String!
    private var testSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testSuiteName = "InsightConcurrencyTests.\(UUID().uuidString)"
        originalSuiteName = InsightDiskCache.suiteName
        InsightDiskCache.suiteName = testSuiteName
    }

    override func tearDownWithError() throws {
        if let suite = testSuiteName {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        InsightDiskCache.suiteName = originalSuiteName
        try super.tearDownWithError()
    }

    private func makeInput(title: String) -> MetricInsightInput {
        MetricInsightInput(
            userName: nil,
            metricTitle: title,
            latestValueText: "80 kg",
            timeframeLabel: "30 days",
            sampleCount: 10,
            delta7DaysText: nil,
            delta14DaysText: nil,
            delta30DaysText: nil,
            delta90DaysText: nil,
            goalStatusText: nil,
            goalDirectionText: nil,
            defaultFavorableDirectionText: "decrease"
        )
    }

    /// Co sprawdza: Max 2 rownolegle generacje
    /// Dlaczego: Ograniczenie obciazenia modelu AI
    /// Kryteria: W kazdym momencie activeCount <= 2
    func testMaxTwoConcurrentGenerations() async {
        let service = MetricInsightService()

        let maxObserved = MaxCounter()
        let activeCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (_: MetricInsightInput) async throws -> MetricInsightPair in
            let current = activeCount.increment()
            maxObserved.update(current)
            try await Task.sleep(for: .milliseconds(100))
            activeCount.decrement()
            return MetricInsightPair(shortText: "S", detailedText: "D")
        })

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    _ = await service.generateInsight(for: self.makeInput(title: "Metric\(i)"))
                }
            }
        }

        XCTAssertLessThanOrEqual(maxObserved.value, 2, "Max concurrent generations should not exceed 2")
        XCTAssertGreaterThan(maxObserved.value, 0, "At least one generation should have run")
    }

    /// Co sprawdza: Wszystkie zakolejkowane taski sie koncza
    /// Dlaczego: Zaden request nie powinien zostac zagubiony
    /// Kryteria: 5 requestow = 5 wynikow
    func testQueuedTasksEventuallyComplete() async {
        let service = MetricInsightService()
        let completedCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (_: MetricInsightInput) async throws -> MetricInsightPair in
            try await Task.sleep(for: .milliseconds(50))
            completedCount.increment()
            return MetricInsightPair(shortText: "Done", detailedText: "Done")
        })

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let result = await service.generateInsight(for: self.makeInput(title: "M\(i)"))
                    XCTAssertNotNil(result)
                }
            }
        }

        XCTAssertEqual(completedCount.value, 5)
    }

    /// Co sprawdza: Cache hit nie zajmuje slotu kolejki
    /// Dlaczego: Tylko prawdziwe generacje powinny byc limitowane
    /// Kryteria: Drugie wywolanie z tym samym inputem nie czeka
    func testCacheHitDoesNotConsumeSlot() async {
        let service = MetricInsightService()
        let generationCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (_: MetricInsightInput) async throws -> MetricInsightPair in
            generationCount.increment()
            return MetricInsightPair(shortText: "Cached", detailedText: "Cached")
        })

        let input = makeInput(title: "Weight")

        _ = await service.generateInsight(for: input)
        XCTAssertEqual(generationCount.value, 1)

        _ = await service.generateInsight(for: input)
        XCTAssertEqual(generationCount.value, 1, "Second call should use cache, not generate again")
    }

    /// Co sprawdza: Sekwencyjne wywolanie z tym samym inputem uzywa cache
    /// Dlaczego: Unikniecie duplikacji pracy — drugie wywolanie powinno trafic w cache
    /// Kryteria: generationCount == 1
    func testSequentialCallsSameInput_usesCache() async {
        let service = MetricInsightService()
        let generationCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (_: MetricInsightInput) async throws -> MetricInsightPair in
            generationCount.increment()
            return MetricInsightPair(shortText: "S", detailedText: "D")
        })

        let input = makeInput(title: "Weight")

        let first = await service.generateInsight(for: input)
        XCTAssertNotNil(first)

        let second = await service.generateInsight(for: input)
        XCTAssertNotNil(second)

        XCTAssertEqual(generationCount.value, 1, "Second call with same input should use cache")
    }
}

// MARK: - Test Helpers

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }

    func decrement() {
        lock.lock()
        defer { lock.unlock() }
        _value -= 1
    }
}

private final class MaxCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func update(_ current: Int) {
        lock.lock()
        defer { lock.unlock() }
        if current > _value { _value = current }
    }
}
