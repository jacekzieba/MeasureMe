import XCTest
@testable import MeasureMe

final class MetricInsightServiceCacheTests: XCTestCase {

    private var testDiskCacheSuite: String!
    private var originalSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testDiskCacheSuite = "MetricInsightServiceCacheTests.\(UUID().uuidString)"
        originalSuiteName = InsightDiskCache.suiteName
        InsightDiskCache.suiteName = testDiskCacheSuite
    }

    override func tearDownWithError() throws {
        if let suite = testDiskCacheSuite {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        InsightDiskCache.suiteName = originalSuiteName
        try super.tearDownWithError()
    }

    private func makeInput(title: String) -> MetricInsightInput {
        MetricInsightInput(
            userName: nil,
            metricTitle: title,
            measurementContext: "body weight",
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

    /// Co sprawdza: Drugie wywolanie z tym samym inputem zwraca z cache
    /// Dlaczego: Unikniecie zbednych generacji AI
    /// Kryteria: generationCount == 1 po dwoch wywolaniach
    func testSecondCallReturnsCached() async {
        let service = MetricInsightService()
        let generationCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (_: MetricInsightInput) async throws -> MetricInsightPair in
            generationCount.increment()
            return MetricInsightPair(shortText: "S", detailedText: "D")
        })

        let input = makeInput(title: "Weight")
        _ = await service.generateInsight(for: input)
        _ = await service.generateInsight(for: input)

        XCTAssertEqual(generationCount.value, 1)
    }

    /// Co sprawdza: invalidate(for:) czysci pasujace wpisy
    /// Dlaczego: Po nowym pomiarze insight musi byc odswiezony
    /// Kryteria: Po invalidacji generuje ponownie
    func testInvalidate_clearsMatchingEntries() async {
        let service = MetricInsightService()
        let generationCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (_: MetricInsightInput) async throws -> MetricInsightPair in
            generationCount.increment()
            return MetricInsightPair(shortText: "S", detailedText: "D")
        })

        let input = makeInput(title: "Weight")
        _ = await service.generateInsight(for: input)
        XCTAssertEqual(generationCount.value, 1)

        await service.invalidate(for: "Weight")
        _ = await service.generateInsight(for: input)
        XCTAssertEqual(generationCount.value, 2, "Should regenerate after invalidation")
    }

    /// Co sprawdza: Cache overflow (>cacheLimit) powoduje czyszczenie
    /// Dlaczego: Kontrola zuzycia pamieci
    /// Kryteria: Po przekroczeniu limitu cache dalej dziala
    func testCacheOverflow_clearsAll() async {
        let service = MetricInsightService()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateOverride({ @Sendable (input: MetricInsightInput) async throws -> MetricInsightPair in
            MetricInsightPair(shortText: input.metricTitle, detailedText: "D")
        })

        for i in 0..<(MetricInsightService.cacheLimit + 5) {
            _ = await service.generateInsight(for: makeInput(title: "Metric\(i)"))
        }

        let result = await service.generateInsight(for: makeInput(title: "Fresh"))
        XCTAssertNotNil(result)
    }

    /// Co sprawdza: invalidateHealth czysci health cache
    /// Dlaczego: Po nowym pomiarze zdrowotnym insight musi byc odswiezony
    /// Kryteria: Po invalidacji generuje ponownie
    func testInvalidateHealth_clearsHealthCache() async {
        let service = MetricInsightService()
        let generationCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateHealthOverride({ @Sendable (_: HealthInsightInput) async throws -> String in
            generationCount.increment()
            return "Health insight"
        })

        let input = HealthInsightInput(
            userName: nil, ageText: nil, genderText: nil,
            latestWeightText: "80 kg", latestWaistText: nil,
            latestBodyFatText: nil, latestLeanMassText: nil,
            weightDelta7dText: nil, waistDelta7dText: nil,
            coreWHtRText: nil, coreBMIText: nil, coreRFMText: nil
        )

        _ = await service.generateHealthInsight(for: input)
        XCTAssertEqual(generationCount.value, 1)

        _ = await service.generateHealthInsight(for: input)
        XCTAssertEqual(generationCount.value, 1, "Should use cache")

        await service.invalidateHealth()
        _ = await service.generateHealthInsight(for: input)
        XCTAssertEqual(generationCount.value, 2, "Should regenerate after invalidation")
    }

    /// Co sprawdza: invalidateSections czysci section cache
    func testInvalidateSections_clearsSectionCache() async {
        let service = MetricInsightService()
        let generationCount = AtomicCounter()

        await service.setTestAvailabilityOverride(true)
        await service.setTestGenerateSectionOverride({ @Sendable (_: SectionInsightInput) async throws -> String in
            generationCount.increment()
            return "Section insight"
        })

        let input = SectionInsightInput(
            sectionID: "measurements",
            sectionTitle: "Body Measurements",
            userName: nil,
            contextLines: ["Waist: 85 cm"]
        )

        _ = await service.generateSectionInsight(for: input)
        XCTAssertEqual(generationCount.value, 1)

        _ = await service.generateSectionInsight(for: input)
        XCTAssertEqual(generationCount.value, 1, "Should use cache")

        await service.invalidateSections()
        _ = await service.generateSectionInsight(for: input)
        XCTAssertEqual(generationCount.value, 2, "Should regenerate after invalidation")
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
}
