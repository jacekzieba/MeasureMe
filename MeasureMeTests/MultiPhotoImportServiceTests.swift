/// Cel testów: Weryfikuje logikę batch importu zdjęć w MultiPhotoImportService.
/// Dlaczego to ważne: Serwis odpowiada za zapis wielu zdjęć do SwiftData — błąd może
/// skutkować utratą danych, zduplikowanymi wpisami lub niepoprawnym postępem UI.
/// Kryteria zaliczenia: Poprawna liczba PhotoEntry, zgodność metadanych, monotoniczny progress.
///
/// UWAGA ARCHITEKTURALNA: Testy używają JEDNEJ metody async testowej z wieloma
/// subtestami. Jest to obejście znanych problemów XCTest + @MainActor + async:
/// - Wiele metod async testowych → deadlock po 2-3 testach (MainActor queue stuck)
/// - Sync testy z XCTestExpectation + Task → race condition przy równoległym wykonaniu
/// Pojedyncza metoda async gwarantuje sekwencyjne wykonanie bez deadlocka.

import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class MultiPhotoImportServiceTests: XCTestCase {

    // MARK: - Setup

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Generuje minimalny UIImage wypełniony jednolitym kolorem.
    /// Rozmiar 64×64 jest celowo mały — testujemy logikę serwisu, nie jakość kompresji.
    /// UWAGA: format.opaque = true jest wymagane — HEIC encoder crashuje
    /// na małych obrazach z alpha channel ("AlphaLast" warning → crash).
    private func makeTestImage(
        color: UIColor = .red,
        size: CGSize = CGSize(width: 64, height: 64)
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - All tests in one async method

    /// Uruchamia wszystkie subtesty sekwencyjnie w jednej async metodzie.
    /// Każdy subtest ma własny in-memory ModelContainer — pełna izolacja.
    func testAllImportScenarios() async throws {
        try await subtestImportSinglePhoto()
        try await subtestImportMultiplePhotos()
        try await subtestImportedEntryHasCorrectDateAndTags()
        try await subtestImportWithoutTagsCreatesEntryWithEmptyTags()
        try await subtestEmptyArrayReturnsZeroCounts()
        try await subtestImportIsAdditive()
        try await subtestProgressCallbackFiresForEachImage()
        try await subtestProgressValuesAreMonotonicallyIncreasing()
        try await subtestProgressNotCalledForEmptyArray()
        try await subtestAllEntriesReceiveSameDate()
        try await subtestSavedCountMatchesDatabaseCount()
    }

    // MARK: - Subtesty

    /// Jeden obraz → jeden PhotoEntry w bazie.
    private func subtestImportSinglePhoto() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let result = try await MultiPhotoImportService.importPhotos(
            [makeTestImage()], date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false
        )

        let count = try context.fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(count, 1, "📸 SinglePhoto: powinien stworzyć 1 PhotoEntry")
        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
    }

    /// N obrazów → N PhotoEntry.
    private func subtestImportMultiplePhotos() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let n = 5
        let images = (0..<n).map { makeTestImage(color: .init(hue: CGFloat($0) / CGFloat(n), saturation: 1, brightness: 1, alpha: 1)) }

        let result = try await MultiPhotoImportService.importPhotos(
            images, date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false
        )

        let count = try context.fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(count, n, "📸 MultiplePhotos: powinien stworzyć \(n) PhotoEntry")
        XCTAssertEqual(result.savedCount, n)
        XCTAssertEqual(result.failedCount, 0)
    }

    /// Data i tagi z parametrów trafiają do PhotoEntry.
    private func subtestImportedEntryHasCorrectDateAndTags() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let targetDate = Date(timeIntervalSince1970: 1_700_000_000)
        let targetTags: [PhotoTag] = [.wholeBody, .waist]

        _ = try await MultiPhotoImportService.importPhotos(
            [makeTestImage()], date: targetDate, tags: targetTags,
            context: context, useBackgroundEncoding: false
        )

        let entries = try context.fetch(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(entries.count, 1, "📸 DateAndTags: powinien mieć 1 entry")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.date, targetDate, "📸 DateAndTags: data musi się zgadzać")
        XCTAssertEqual(Set(entry.tags), Set(targetTags), "📸 DateAndTags: tagi muszą się zgadzać")
    }

    /// Import z pustymi tagami tworzy PhotoEntry z tags == [].
    private func subtestImportWithoutTagsCreatesEntryWithEmptyTags() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        _ = try await MultiPhotoImportService.importPhotos(
            [makeTestImage()], date: .now, tags: [],
            context: context, useBackgroundEncoding: false
        )

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<PhotoEntry>()).first)
        XCTAssertTrue(entry.tags.isEmpty, "📸 EmptyTags: tagi powinny być puste")
    }

    /// Pusta tablica → ImportResult(0, 0), bez wyjątku.
    private func subtestEmptyArrayReturnsZeroCounts() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let result = try await MultiPhotoImportService.importPhotos(
            [], date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false
        )

        XCTAssertEqual(result.savedCount, 0, "📸 EmptyArray: savedCount == 0")
        XCTAssertEqual(result.failedCount, 0, "📸 EmptyArray: failedCount == 0")
        let count = try context.fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(count, 0, "📸 EmptyArray: baza pusta")
    }

    /// Import nie usuwa wcześniej istniejących PhotoEntry.
    private func subtestImportIsAdditive() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        _ = try await MultiPhotoImportService.importPhotos(
            [makeTestImage(color: .red), makeTestImage(color: .blue)],
            date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false
        )
        _ = try await MultiPhotoImportService.importPhotos(
            [makeTestImage(color: .green)],
            date: .now, tags: [.waist],
            context: context, useBackgroundEncoding: false
        )

        let count = try context.fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(count, 3, "📸 Additive: dwa importy powinny zsumować się do 3")
    }

    /// Callback progress odpala się dokładnie raz per zdjęcie.
    private func subtestProgressCallbackFiresForEachImage() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let n = 4
        let images = (0..<n).map { makeTestImage(color: .init(hue: CGFloat($0) / CGFloat(n), saturation: 1, brightness: 1, alpha: 1)) }

        var callCount = 0
        var lastCurrent = 0
        var lastTotal = 0

        _ = try await MultiPhotoImportService.importPhotos(
            images, date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false,
            progress: { current, total in
                callCount += 1
                lastCurrent = current
                lastTotal = total
            }
        )

        XCTAssertEqual(callCount, n, "📸 ProgressCount: callback powinien odpalić \(n) razy")
        XCTAssertEqual(lastCurrent, n, "📸 ProgressCount: ostatni current == \(n)")
        XCTAssertEqual(lastTotal, n, "📸 ProgressCount: total == \(n)")
    }

    /// Wartości current rosną monotonicznie.
    private func subtestProgressValuesAreMonotonicallyIncreasing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let n = 5
        let images = (0..<n).map { makeTestImage(color: .init(hue: CGFloat($0) / CGFloat(n), saturation: 1, brightness: 1, alpha: 1)) }

        var progressValues: [Int] = []

        _ = try await MultiPhotoImportService.importPhotos(
            images, date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false,
            progress: { current, _ in progressValues.append(current) }
        )

        XCTAssertEqual(progressValues.count, n, "📸 Monotonic: \(n) wywołań")
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i - 1],
                "📸 Monotonic: wartości nie mogą maleć: \(progressValues)")
        }
    }

    /// Progress nie jest wywoływane gdy tablica jest pusta.
    private func subtestProgressNotCalledForEmptyArray() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var callCount = 0
        _ = try await MultiPhotoImportService.importPhotos(
            [], date: .now, tags: [],
            context: context, useBackgroundEncoding: false,
            progress: { _, _ in callCount += 1 }
        )

        XCTAssertEqual(callCount, 0, "📸 EmptyProgress: callback nie powinien być wołany")
    }

    /// Każdy PhotoEntry z batcha dostaje tę samą datę.
    private func subtestAllEntriesReceiveSameDate() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let targetDate = Date(timeIntervalSince1970: 1_710_000_000)
        let images = [makeTestImage(color: .red), makeTestImage(color: .blue), makeTestImage(color: .green)]

        _ = try await MultiPhotoImportService.importPhotos(
            images, date: targetDate, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false
        )

        let entries = try context.fetch(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(entries.count, 3, "📸 SameDate: 3 entries")
        for entry in entries {
            XCTAssertEqual(entry.date, targetDate, "📸 SameDate: data musi być taka sama")
        }
    }

    /// ImportResult.savedCount zgadza się z liczbą rekordów w bazie.
    private func subtestSavedCountMatchesDatabaseCount() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let n = 3
        let images = (0..<n).map { makeTestImage(color: .init(hue: CGFloat($0) / CGFloat(n), saturation: 1, brightness: 1, alpha: 1)) }

        let result = try await MultiPhotoImportService.importPhotos(
            images, date: .now, tags: [.wholeBody],
            context: context, useBackgroundEncoding: false
        )

        let dbCount = try context.fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(result.savedCount, dbCount,
            "📸 CountMatch: savedCount (\(result.savedCount)) == dbCount (\(dbCount))")
    }
}
