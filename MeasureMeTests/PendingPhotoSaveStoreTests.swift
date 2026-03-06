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

    func testRestoreAndResumeAsync_LoadsPendingItemsFromDisk() async throws {
        let container = try makeContainer()

        let first = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        first.configure(container: container)
        let id = try await first.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_120_000),
            tags: [.wholeBody],
            metricValues: [.waist: 88],
            unitsSystem: "metric"
        )
        XCTAssertEqual(first.pendingItems.count, 1)

        let restored = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        restored.configure(container: container)
        await restored.restoreAndResumeAsync()

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
        XCTAssertNotNil(photos.first?.thumbnailData)
        if let thumbnailSize = photos.first?.thumbnailData?.count {
            XCTAssertLessThanOrEqual(thumbnailSize, PhotoUtilities.gridThumbnailMaxBytes)
        }
        XCTAssertEqual(store.completedEvent?.id, id)
        XCTAssertNotNil(store.completedEvent?.entryPersistentModelID)
        if let persistentID = store.completedEvent?.entryPersistentModelID {
            XCTAssertTrue(photos.contains(where: { $0.persistentModelID == persistentID }))
        }
    }

    func testCancelPendingBatch_RemovesPendingAndSpool() async throws {
        let store = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        store.configure(container: try makeContainer())

        let batchID = UUID()
        let ids = try await store.enqueueMany(
            sourceImages: [makeImage(), makeImage(), makeImage()],
            date: Date(timeIntervalSince1970: 1_735_260_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric",
            batchID: batchID
        )
        XCTAssertEqual(store.pendingItems.count, 3)

        store.cancelPending(batchIDs: [batchID])
        XCTAssertTrue(store.pendingItems.isEmpty)

        let spoolDir = tempDirectory.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
        for id in ids {
            XCTAssertFalse(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).source.jpg").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: spoolDir.appendingPathComponent("\(id.uuidString).thumb.jpg").path))
        }
    }

    func testCancelPendingBatch_DropsLateCompletion() async throws {
        let container = try makeContainer()
        let store = PendingPhotoSaveStore(
            baseDirectoryURL: tempDirectory,
            encodeSourceData: { sourceData in
                Thread.sleep(forTimeInterval: 0.9)
                guard let image = UIImage(data: sourceData) else { return nil }
                return PhotoUtilities.encodeForStorage(image, maxSize: 2_000_000)
            }
        )
        store.configure(container: container)

        let batchID = UUID()
        _ = try await store.enqueueMany(
            sourceImages: [makeImage(), makeImage()],
            date: Date(timeIntervalSince1970: 1_735_280_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric",
            batchID: batchID
        )

        store.cancelPending(batchIDs: [batchID])

        try await waitUntil(timeout: 6) {
            store.pendingItems.isEmpty
        }

        XCTAssertNil(store.completedEvent)
        let context = ModelContext(container)
        let count = try context.fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(count, 0)
    }

    func testProcessingOrder_UsesDeterministicQueueWithoutResortingLoop() async throws {
        let container = try makeContainer()
        let queuer = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        queuer.configure(container: container)

        let firstDate = Date(timeIntervalSince1970: 1_736_000_000)
        let thirdDate = firstDate.addingTimeInterval(1)
        let firstID: UUID
        let secondID: UUID
        let thirdID: UUID
        defer { AppClock.overrideNowForTesting = nil }

        AppClock.overrideNowForTesting = firstDate
        firstID = try await queuer.enqueueSingle(
            sourceImage: makeImage(),
            date: firstDate,
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        AppClock.overrideNowForTesting = firstDate
        secondID = try await queuer.enqueueSingle(
            sourceImage: makeImage(),
            date: firstDate,
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        AppClock.overrideNowForTesting = thirdDate
        thirdID = try await queuer.enqueueSingle(
            sourceImage: makeImage(),
            date: thirdDate,
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        let processor = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory)
        processor.configure(container: container)
        processor.restoreAndResume()

        let completedIDs = try await collectCompletedIDs(from: processor, expectedCount: 3, timeout: 8)
        let expectedIDs = [firstID, secondID, thirdID].sorted { lhs, rhs in
            let lhsDate = lhs == thirdID ? thirdDate : firstDate
            let rhsDate = rhs == thirdID ? thirdDate : firstDate
            if lhsDate == rhsDate {
                return lhs.uuidString < rhs.uuidString
            }
            return lhsDate < rhsDate
        }
        XCTAssertEqual(completedIDs, expectedIDs)
    }

    func testCancelRemovesIDsFromProcessingOrder() async throws {
        let container = try makeContainer()
        let batchToCancel = UUID()
        let batchToKeep = UUID()

        let queuer = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        queuer.configure(container: container)

        let cancelledIDs = try await queuer.enqueueMany(
            sourceImages: [makeImage(), makeImage()],
            date: Date(timeIntervalSince1970: 1_736_010_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric",
            batchID: batchToCancel
        )
        let keptIDs = try await queuer.enqueueMany(
            sourceImages: [makeImage()],
            date: Date(timeIntervalSince1970: 1_736_010_100),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric",
            batchID: batchToKeep
        )

        queuer.cancelPending(batchIDs: [batchToCancel])
        XCTAssertEqual(queuer.pendingItems.count, keptIDs.count)

        let processor = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory)
        processor.configure(container: container)
        processor.restoreAndResume()

        let completedIDs = try await collectCompletedIDs(from: processor, expectedCount: keptIDs.count, timeout: 8)
        XCTAssertEqual(Set(completedIDs), Set(keptIDs))
        XCTAssertTrue(Set(completedIDs).isDisjoint(with: Set(cancelledIDs)))
    }

    // MARK: - Spool directory failure tests

    /// When the spool directory cannot be created (a regular file blocks its path),
    /// `enqueueSingle` must throw `spoolWriteFailed` and leave `pendingItems` empty.
    func testEnqueueSingle_ThrowsSpoolWriteFailed_WhenDirectoryIsBlocked() async throws {
        // Create a file where the PendingPhotoSaves *directory* should be, blocking its creation.
        let blockedPath = tempDirectory.appendingPathComponent("PendingPhotoSaves")
        FileManager.default.createFile(atPath: blockedPath.path, contents: Data())

        let store = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        store.configure(container: try makeContainer())

        var caught: Error?
        do {
            _ = try await store.enqueueSingle(
                sourceImage: makeImage(),
                date: Date(timeIntervalSince1970: 1_735_500_000),
                tags: [.wholeBody],
                metricValues: [:],
                unitsSystem: "metric"
            )
            XCTFail("Expected enqueueSingle to throw")
        } catch {
            caught = error
        }

        XCTAssertEqual(
            caught as? PendingPhotoSaveStore.PendingSaveError,
            .spoolWriteFailed,
            "Error must be spoolWriteFailed"
        )
        XCTAssertTrue(store.pendingItems.isEmpty, "No item should be added when spool write fails")
    }

    /// Regression guard: when a spool write fails, no files should appear in the system
    /// /tmp directory. This guards against the previous behaviour where URL helpers
    /// silently fell back to `URL(fileURLWithPath: "/tmp/<uuid>.<ext>")` on failure.
    func testEnqueueSingle_WritesNoFilesToTmp_WhenSpoolDirectoryIsBlocked() async throws {
        let blockedPath = tempDirectory.appendingPathComponent("PendingPhotoSaves")
        FileManager.default.createFile(atPath: blockedPath.path, contents: Data())

        let store = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        store.configure(container: try makeContainer())

        // Snapshot /tmp *before* the failed attempt so we detect only newly created files.
        let tmpURL = URL(fileURLWithPath: "/tmp")
        let namesBefore = Set(
            ((try? FileManager.default.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)) ?? [])
                .map(\.lastPathComponent)
        )

        _ = try? await store.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_510_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        let namesAfter = Set(
            ((try? FileManager.default.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)) ?? [])
                .map(\.lastPathComponent)
        )
        let newNames = namesAfter.subtracting(namesBefore)
        let spoolRelated = newNames.filter {
            $0.hasSuffix(".json") || $0.hasSuffix(".source.jpg") || $0.hasSuffix(".thumb.jpg")
        }

        XCTAssertTrue(
            spoolRelated.isEmpty,
            "No spool-related files should be written to /tmp on failure, found: \(spoolRelated)"
        )
    }

    /// When the source image file is removed from the spool directory after a successful
    /// enqueue but before processing starts, the job must fail gracefully with a
    /// `lastFailureMessage` rather than silently succeeding or reading from wrong paths.
    func testProcessing_FailsWithLastFailureMessage_WhenSourceFileDeletedAfterEnqueue() async throws {
        let container = try makeContainer()

        // Stage 1: enqueue with processing disabled so spool files are written but not consumed.
        let queuer = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory, autoStartProcessing: false)
        queuer.configure(container: container)
        let id = try await queuer.enqueueSingle(
            sourceImage: makeImage(),
            date: Date(timeIntervalSince1970: 1_735_520_000),
            tags: [.wholeBody],
            metricValues: [:],
            unitsSystem: "metric"
        )

        // Stage 2: delete the source image from the spool directory,
        // simulating the file becoming inaccessible before the job runs.
        let spoolDir = tempDirectory.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
        try FileManager.default.removeItem(
            at: spoolDir.appendingPathComponent("\(id.uuidString).source.jpg")
        )

        // Stage 3: a fresh store restores the queued item from disk and starts processing.
        let processor = PendingPhotoSaveStore(baseDirectoryURL: tempDirectory)
        processor.configure(container: container)
        processor.restoreAndResume()

        try await waitUntil(timeout: 5) {
            processor.pendingItems.isEmpty && processor.lastFailureMessage != nil
        }

        XCTAssertNotNil(processor.lastFailureMessage, "User must be informed of the failure")
        XCTAssertNil(processor.completedEvent, "No photo should be saved when source is missing")
        let savedCount = try ModelContext(container).fetchCount(FetchDescriptor<PhotoEntry>())
        XCTAssertEqual(savedCount, 0, "No PhotoEntry should be persisted when source file is missing")
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

    func collectCompletedIDs(
        from store: PendingPhotoSaveStore,
        expectedCount: Int,
        timeout: TimeInterval
    ) async throws -> [UUID] {
        let deadline = Date.now.addingTimeInterval(timeout)
        var ids: [UUID] = []
        var seenEventIDs: Set<UUID> = []

        while Date.now < deadline {
            if let event = store.completedEvent, !seenEventIDs.contains(event.eventID) {
                seenEventIDs.insert(event.eventID)
                ids.append(event.id)
                if ids.count == expectedCount {
                    return ids
                }
            }
            try? await Task.sleep(for: .milliseconds(40))
        }

        XCTFail("Expected \(expectedCount) completed events, got \(ids.count)")
        return ids
    }
}
