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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
}
