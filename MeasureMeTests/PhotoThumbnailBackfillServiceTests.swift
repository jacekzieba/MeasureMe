import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class PhotoThumbnailBackfillServiceTests: XCTestCase {
    func testThumbnailFallbackPrefersStoredThumbnail() {
        let imageData = Data([0xAA, 0xBB, 0xCC])
        let thumbnailData = Data([0x01, 0x02, 0x03])
        let entry = PhotoEntry(
            imageData: imageData,
            thumbnailData: thumbnailData,
            tags: [.wholeBody]
        )

        XCTAssertEqual(entry.thumbnailOrImageData, thumbnailData)
    }

    func testThumbnailFallbackUsesImageDataWhenThumbnailMissing() {
        let imageData = Data([0x11, 0x22, 0x33])
        let entry = PhotoEntry(
            imageData: imageData,
            thumbnailData: nil,
            tags: [.wholeBody]
        )

        XCTAssertEqual(entry.thumbnailOrImageData, imageData)
    }

    func testBackfillDeduplicatesInFlightRequests() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let entry = PhotoEntry(
            imageData: Data([0x10, 0x20, 0x30]),
            thumbnailData: nil,
            tags: [.wholeBody]
        )
        context.insert(entry)
        try context.save()

        let generatedCounter = LockedCounter()
        let persistedCounter = LockedCounter()
        let service = PhotoThumbnailBackfillService(
            maxConcurrentJobs: 2,
            generateThumbnail: { data in
                generatedCounter.increment()
                Thread.sleep(forTimeInterval: 0.12)
                return data + Data([0x99])
            },
            persistThumbnail: { _, _, _ in
                persistedCounter.increment()
                return true
            }
        )

        let photoID = entry.persistentModelID
        await service.enqueueIfNeeded(
            photoID: photoID,
            originalImageData: entry.imageData,
            existingThumbnailData: nil,
            modelContainer: container,
            source: "unit_test"
        )
        await service.enqueueIfNeeded(
            photoID: photoID,
            originalImageData: entry.imageData,
            existingThumbnailData: nil,
            modelContainer: container,
            source: "unit_test"
        )

        try await waitUntil(timeout: 2.0) {
            let state = await service.debugState()
            return state.queued == 0 && state.inFlight == 0 && state.active == 0
        }

        XCTAssertEqual(generatedCounter.value, 1)
        XCTAssertEqual(persistedCounter.value, 1)
    }
}

private extension PhotoThumbnailBackfillServiceTests {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([MetricSample.self, MetricGoal.self, PhotoEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func waitUntil(timeout: TimeInterval, condition: @escaping () async -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Condition was not met before timeout")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        let current = _value
        lock.unlock()
        return current
    }
}
