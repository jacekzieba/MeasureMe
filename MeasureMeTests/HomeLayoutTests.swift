import XCTest
@testable import MeasureMe

@MainActor
final class HomeLayoutTests: XCTestCase {
    private func makeSnapshot() -> AppSettingsSnapshot {
        let suite = "HomeLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.register(defaults: AppSettingsSnapshot.registeredDefaults)
        return AppSettingsSnapshot.load(from: defaults)
    }

    func testHomeLayoutRoundTripSerialization() throws {
        let snapshot = makeSnapshot()
        let layout = HomeLayoutSnapshot.defaultV1(using: snapshot)
        let encoded = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(HomeLayoutSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, layout)
    }

    func testPinnedActionRoundTripSerialization() throws {
        let encoded = try JSONEncoder().encode(HomePinnedAction.comparePhotos)
        let decoded = try JSONDecoder().decode(HomePinnedAction.self, from: encoded)

        XCTAssertEqual(decoded, .comparePhotos)
    }

    func testNormalizerAddsMissingModulesAndRemovesDuplicates() {
        let snapshot = makeSnapshot()
        let layout = HomeLayoutSnapshot(
            schemaVersion: 0,
            items: [
                HomeModuleLayoutItem(kind: .summaryHero, isVisible: true, size: .large, row: 0, column: 0),
                HomeModuleLayoutItem(kind: .summaryHero, isVisible: false, size: .small, row: 5, column: 5),
                HomeModuleLayoutItem(kind: .recentPhotos, isVisible: false, size: .large, row: 2, column: 0)
            ]
        )

        let normalized = HomeLayoutNormalizer.normalize(layout, using: snapshot)

        XCTAssertEqual(normalized.items.count, HomeModuleKind.activeCases.count)
        XCTAssertEqual(normalized.item(for: .summaryHero)?.isVisible, true)
        XCTAssertEqual(normalized.item(for: .quickActions)?.isVisible, false)
        XCTAssertNotNil(normalized.item(for: .healthSummary))
    }

    func testCompactorProducesTopDownLayoutWithoutGaps() {
        let items = [
            HomeModuleLayoutItem(kind: .summaryHero, isVisible: true, size: .large, row: 0, column: 0),
            HomeModuleLayoutItem(kind: .activationHub, isVisible: true, size: .wide, row: 5, column: 0),
            HomeModuleLayoutItem(kind: .recentPhotos, isVisible: false, size: .large, row: 8, column: 0),
            HomeModuleLayoutItem(kind: .keyMetrics, isVisible: true, size: .large, row: 12, column: 0)
        ]

        let compacted = HomeLayoutCompactor.compact(items, columns: 2)

        XCTAssertEqual(compacted.map(\.kind), [.summaryHero, .activationHub, .keyMetrics])
        XCTAssertEqual(compacted[0].row, 0)
        XCTAssertEqual(compacted[1].row, 2)
        XCTAssertEqual(compacted[2].row, 3)
    }

    func testResettingToDefaultGeometryPreservesVisibility() {
        let snapshot = makeSnapshot()
        var layout = HomeLayoutSnapshot.defaultV1(using: snapshot)
        layout.setVisibility(false, for: .keyMetrics)
        layout.setVisibility(false, for: .activationHub)

        let reset = layout.resettingToDefaultGeometry(using: snapshot)

        XCTAssertEqual(reset.item(for: .keyMetrics)?.isVisible, false)
        XCTAssertEqual(reset.item(for: .activationHub)?.isVisible, false)
        XCTAssertEqual(reset.item(for: .summaryHero)?.row, 0)
        XCTAssertEqual(reset.item(for: .activationHub)?.column, 2)
    }
}
