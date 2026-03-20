/// Cel testow: Sprawdza persystencje i integralnosc modeli po zapisie i odczycie (round-trip).
/// Dlaczego to wazne: Regresje w persystencji niszcza historie pomiarow i zaufanie do aplikacji.
/// Kryteria zaliczenia: Dane po zapisie/odczycie pozostaja spojne i kompletne.

import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class PersistenceAndModelIntegrityTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Co sprawdza: Sprawdza scenariusz: SwiftDataCRUDAndDeleteAllFlow.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testSwiftDataCRUDAndDeleteAllFlow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sample = MetricSample(kind: .weight, value: 80, date: .now)
        let goal = MetricGoal(kind: .weight, targetValue: 75, direction: .decrease)
        let photo = PhotoEntry(
            imageData: Data([0x01, 0x02, 0x03]),
            date: .now,
            tags: [.wholeBody],
            linkedMetrics: [MetricValueSnapshot(kind: .weight, value: 80, unit: "kg")]
        )

        context.insert(sample)
        context.insert(goal)
        context.insert(photo)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhotoEntry>()), 1)

        try context.fetch(FetchDescriptor<MetricSample>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<MetricGoal>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PhotoEntry>()).forEach { context.delete($0) }
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricSample>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MetricGoal>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhotoEntry>()), 0)
    }

    /// Co sprawdza: Sprawdza scenariusz: InvalidKindRawDoesNotFallbackToWeight.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testInvalidKindRawDoesNotFallbackToWeight() {
        let sample = MetricSample(kind: .weight, value: 80, date: .now)
        sample.kindRaw = "invalid-kind"
        XCTAssertNil(sample.kind)

        let goal = MetricGoal(kind: .waist, targetValue: 85, direction: .decrease)
        goal.kindRaw = "invalid-kind"
        XCTAssertNil(goal.kind)
    }

    /// Co sprawdza: Nowy cel zapisuje się poprawnie, a kolejne ustawienie robi update zamiast duplikatu.
    /// Dlaczego: To zabezpiecza regresję "Set Goal" zarówno dla insertu, jak i edycji.
    /// Kryteria: W bazie pozostaje jeden goal dla metryki, a próbka startowa nie duplikuje się przy update.
    func testMetricGoalStoreUpsertsGoalAndAvoidsDuplicateStartSample() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let startDate = Date(timeIntervalSince1970: 1_710_000_000)

        let inserted = MetricGoalStore.upsertGoal(
            kind: .weight,
            targetValue: 75,
            direction: .decrease,
            startValue: 80,
            startDate: startDate,
            in: context,
            existingGoal: nil,
            existingSamples: [],
            now: startDate
        )
        try context.save()

        var goals = try context.fetch(FetchDescriptor<MetricGoal>())
        var samples = try context.fetch(FetchDescriptor<MetricSample>())
        XCTAssertEqual(goals.count, 1, "Pierwsze ustawienie celu powinno tworzyć jeden rekord")
        XCTAssertEqual(samples.count, 1, "Pierwsze ustawienie celu z punktem startowym powinno dodać próbkę startową")
        XCTAssertEqual(inserted.targetValue, 75, accuracy: 0.001)
        XCTAssertEqual(inserted.startValue ?? 0, 80, accuracy: 0.001)

        _ = MetricGoalStore.upsertGoal(
            kind: .weight,
            targetValue: 74,
            direction: .decrease,
            startValue: 80,
            startDate: startDate,
            in: context,
            existingGoal: goals.first,
            existingSamples: samples,
            now: startDate.addingTimeInterval(3600)
        )
        try context.save()

        goals = try context.fetch(FetchDescriptor<MetricGoal>())
        samples = try context.fetch(FetchDescriptor<MetricSample>())
        XCTAssertEqual(goals.count, 1, "Kolejne ustawienie celu powinno aktualizować istniejący rekord")
        XCTAssertEqual(samples.count, 1, "Aktualizacja nie powinna duplikować próbki startowej")
        XCTAssertEqual(goals[0].targetValue, 74, accuracy: 0.001)
        XCTAssertEqual(goals[0].createdDate.timeIntervalSince1970, startDate.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 0.001)
    }
}
