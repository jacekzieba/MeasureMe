/// Cel testow: Sprawdza odtwarzanie definicji wlasnych metryk, ktorych pomiary lub cele przetrwaly bez definicji.
/// Dlaczego to wazne: Dodanie pomiaru ze Skrotow otwieralo baze schematem bez CustomMetricDefinition i kasowalo
///   wszystkie definicje; pomiary zostawaly, ale bez metryki nie bylo ich widac w aplikacji.
/// Kryteria zaliczenia: Kazdy osierocony identyfikator dostaje definicje z tym samym identyfikatorem, istniejace
///   definicje i swiadomie wylaczone metryki zostaja nietkniete.

import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class CustomMetricRecoveryTests: XCTestCase {
    private var context: ModelContext!
    private var settings: AppSettingsStore!
    private var suiteName: String!

    override func setUpWithError() throws {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        context = ModelContext(container)
        suiteName = "CustomMetricRecoveryTests.\(UUID().uuidString)"
        settings = AppSettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        context = nil
        settings = nil
    }

    func testOrphanedSamplesGetADefinitionWithTheSameIdentifier() throws {
        context.insert(MetricSample(kindRaw: "custom_A", value: 16, date: Date(timeIntervalSince1970: 1_700_000_500)))
        context.insert(MetricSample(kindRaw: "custom_A", value: 17, date: Date(timeIntervalSince1970: 1_700_000_100)))
        try context.save()

        let recovered = try CustomMetricRecovery.recoverOrphanedDefinitions(in: context, settings: settings)

        XCTAssertEqual(recovered, 1)
        let definition = try XCTUnwrap(try context.fetch(FetchDescriptor<CustomMetricDefinition>()).first)
        XCTAssertEqual(definition.identifier, "custom_A")
        XCTAssertEqual(definition.name, String(format: AppLocalization.string("Recovered metric %d"), 1))
        XCTAssertEqual(definition.createdDate, Date(timeIntervalSince1970: 1_700_000_100), "Dated from the earliest entry")
        XCTAssertTrue(settings.bool(forKey: AppSettingsKeys.Metrics.customEnabled("custom_A")), "Shown, so the data is visible again")
    }

    func testOrphanedGoalIsRecoveredToo() throws {
        context.insert(MetricGoal(kindRaw: "custom_G", targetValue: 10, direction: .increase, createdDate: .now))
        try context.save()

        XCTAssertEqual(try CustomMetricRecovery.recoverOrphanedDefinitions(in: context, settings: settings), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomMetricDefinition>()).map(\.identifier), ["custom_G"])
    }

    func testMetricsWithADefinitionAreLeftAlone() throws {
        let existing = CustomMetricDefinition(name: "Wrist", unitLabel: "cm")
        context.insert(existing)
        context.insert(MetricSample(kindRaw: existing.identifier, value: 16, date: .now))
        context.insert(MetricSample(kind: .weight, value: 80, date: .now))
        try context.save()

        XCTAssertEqual(try CustomMetricRecovery.recoverOrphanedDefinitions(in: context, settings: settings), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomMetricDefinition>()).map(\.name), ["Wrist"])
    }

    func testSeveralOrphansAreNumberedByFirstUse() throws {
        context.insert(MetricSample(kindRaw: "custom_LATER", value: 1, date: Date(timeIntervalSince1970: 1_700_000_900)))
        context.insert(MetricSample(kindRaw: "custom_EARLIER", value: 1, date: Date(timeIntervalSince1970: 1_700_000_100)))
        try context.save()

        _ = try CustomMetricRecovery.recoverOrphanedDefinitions(in: context, settings: settings)

        let byIdentifier = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<CustomMetricDefinition>()).map { ($0.identifier, $0.name) }
        )
        XCTAssertEqual(byIdentifier["custom_EARLIER"], String(format: AppLocalization.string("Recovered metric %d"), 1))
        XCTAssertEqual(byIdentifier["custom_LATER"], String(format: AppLocalization.string("Recovered metric %d"), 2))
    }

    func testMetricTheUserSwitchedOffStaysOff() throws {
        settings.set(false, forKey: AppSettingsKeys.Metrics.customEnabled("custom_OFF"))
        context.insert(MetricSample(kindRaw: "custom_OFF", value: 1, date: .now))
        try context.save()

        _ = try CustomMetricRecovery.recoverOrphanedDefinitions(in: context, settings: settings)

        XCTAssertFalse(settings.bool(forKey: AppSettingsKeys.Metrics.customEnabled("custom_OFF")))
    }
}
