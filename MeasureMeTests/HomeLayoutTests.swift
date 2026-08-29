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

    /// Co sprawdza: Zapisany uklad z aktualna schema, ale bez modulu modelu ciala, dostaje go
    ///   jako widoczny.
    /// Dlaczego: To sciezka kazdego istniejacego uzytkownika po tej aktualizacji. Normalizator
    ///   dosypuje brakujace rodzaje tylko z domyslnego ukladu, wiec gdyby wpis w defaultV1
    ///   wypadl, kafelek nie pokazalby sie nikomu poza swiezymi instalacjami — i nikt by tego
    ///   nie zauwazyl, bo schema by sie zgadzala.
    /// Kryteria: Modul .bodyModel istnieje i jest widoczny.
    func testExistingLayoutGainsVisibleBodyModelModule() {
        let snapshot = makeSnapshot()
        let saved = HomeLayoutSnapshot(
            schemaVersion: HomeLayoutSnapshot.currentSchemaVersion,
            items: HomeLayoutSnapshot.defaultV1(using: snapshot).items.filter { $0.kind != .bodyModel }
        )

        let normalized = HomeLayoutNormalizer.normalize(saved, using: snapshot)

        XCTAssertEqual(normalized.item(for: .bodyModel)?.isVisible, true)
    }

    /// Co sprawdza: Uzytkownik, ktory sam ukryl kafelek, nie dostaje go z powrotem.
    /// Dlaczego: Normalizator biegnie przy kazdym odczycie ukladu; nadpisanie decyzji
    ///   uzytkownika przy starcie byloby bledem, ktorego nikt nie zglosi — po prostu wylaczy apke.
    /// Kryteria: Ukryty .bodyModel zostaje ukryty.
    func testHiddenBodyModelModuleStaysHidden() {
        let snapshot = makeSnapshot()
        var saved = HomeLayoutSnapshot.defaultV1(using: snapshot)
        saved.setVisibility(false, for: .bodyModel)

        let normalized = HomeLayoutNormalizer.normalize(saved, using: snapshot)

        XCTAssertEqual(normalized.item(for: .bodyModel)?.isVisible, false)
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
