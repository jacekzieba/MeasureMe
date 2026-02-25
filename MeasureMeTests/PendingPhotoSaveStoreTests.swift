import XCTest
import SwiftData
@testable import MeasureMe

@MainActor
final class PendingPhotoSaveStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingPhotoSaveStoreTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testEnqueueSingle_CreatesSpoolAndPendingItem() async throws {
        let store = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        store.configure(container: try makeContainer())

        let id = try await store.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_000_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        XCTAssertEqual(store.pendingItems.count, 1)
        XCTAssertEqual(store.pendingItems.first?.id, id)

        let spoolDir = tempDirectory.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).source.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).thumb.jpg").path))
    }

    func testEnqueueMany_CreatesPendingItemsAndSpoolFiles() async throws {
        let store = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        store.configure(container: try makeContainer())

        let images = [makeImage(), makeImage(), makeImage()]
        let ids = try await store.enqueueMany(
            sourceImages: images,
            date: Date(timeIntervalSince1970: 1_735_050_000),
            tags: [.wholeBody, .waist],
            metricValues: [:],
            unitsSystem: "metric"
        )

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(store.pendingItems.count, 3)

        let spoolDir = tempDirectory.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
        for id in ids {
            XCTAssertTrue(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).json").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).source.jpg").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).thumb.jpg").path))
        }
    }

    func testRestoreAndResume_LoadsPendingItemsFromDisk() async throws {
        let container = try makeContainer()

        let first = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        first.configure(container: container)
        let id = try await first.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_100_000),
            tags: [.wholeBody],
            metricValues: [.waist: 90],
            unitsSystem: "metric"
        )
        XCTAssertEqual(first.pendingItems.count, 1)

        let restored = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        restored.configure(container: container)
        restored.restoreAndResume()

        XCTAssertEqual(restored.pendingItems.count, 1)
        XCTAssertEqual(restored.pendingItems.first?.id, id)
        XCTAssertEqual(restored.pendingItems.first?.status, .queued)
    }

    func testCompletion_RemovesSpoolAndEmitsCompletedEvent() async throws {
        let container = try makeContainer()
        let store = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory)
        store.configure(container: container)

        let id = try await store.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_200_000),
            tags: [.wholeBody],
            metricValues: [.waist: 86],
            unitsSystem: "metric"
        )

        try await waitUntil(timeout: 5) {
            store.pendingItems.isEmpty && store.completedEvent?.id == id
        }

        let spoolDir = tempDirectory.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).json").path))

        let context = ModelContext(container)
        let photos = try context.fetch(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(store.completedEvent?.id, id)
    }

    func testFailure_RemovesPendingAndSetsFailureMessage() async throws {
        let store = PendingPhotoSaveStore(
            baseDirectoryURL: tempDirectory,
            encodeSourceData: { _ in nil }
        )
        store.configure(container: try makeContainer())

        _ = try await store.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_300_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        try await waitUntil(timeout: 5) {
            store.pendingItems.isEmpty && store.lastFailureMessage != nil
        }

        XCTAssertNotNil(store.lastFailureMessage)
        XCTAssertNil(store.completedEvent)
    }

    func testProgress_IsMonotonicAndCompletes() async throws {
        let store = PendingPhotoSaveStore(
            baseDirectoryURL: tempDirectory,
            encodeSourceData: { sourceData in
                Thread.sleep(forTimeInterval: 0.35)
                guard let image = UIImage(data: sourceData) else { return nil }
                return PhotoUtilities.encodeForStorage(image, maxSize: 2_000_000)
            }
        )
        store.configure(container: try makeContainer())

        _ = try await store.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_400_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        var samples: [Double] = []
        let start = Date.now
        while Date.now.timeIntervalSince(start) < 8 {
            if let first = store.pendingItems.first {
                samples.append(first.progress)
            }
            if store.completedEvent != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(30))
        }

        XCTAssertFalse(samples.isEmpty)
        for pair in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0, pair.1 + 0.0001)
        }
        XCTAssertNotNil(store.completedEvent)
        XCTAssertEqual(store.lastCompletedProgress, 1.0)
    }
}

private extension PendingPhotoSaveStoreTests {
    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: PhotoEntry.self,
            MetricSample.self,
            MetricGoal.self,
            configurations: config
        )
    }

    func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800))
        return renderer.image { ctx in
            UIColor(red: 0.14, green: 0.68, blue: 0.74, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            let text = "Pending Test" as NSString
            text.draw(
                at: CGPoint(x: 24, y: 24),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 52),
                    .foregroundColor: UIColor.white
                ]
            )
        }
    }

    func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Condition was not met before timeout")
    }
}
