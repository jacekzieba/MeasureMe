import Foundation
import SwiftData
import UIKit

@MainActor
enum PhotoThumbnailTelemetry {
    private static var photosReloadStartedAt: ContinuousClock.Instant?
    private static var firstThumbnailLoggedForCurrentReload = false
    private static var seenPhotoIDsInCurrentReload: Set<String> = []
    private static var thumbnailHitCount: Int = 0
    private static var thumbnailMissCount: Int = 0

    static func beginPhotosReload() {
        photosReloadStartedAt = ContinuousClock.now
        firstThumbnailLoggedForCurrentReload = false
        seenPhotoIDsInCurrentReload.removeAll()
        thumbnailHitCount = 0
        thumbnailMissCount = 0
    }

    static func recordPhotosTileAppearance(photoID: String, hasStoredThumbnail: Bool) {
        guard seenPhotoIDsInCurrentReload.insert(photoID).inserted else { return }

        if hasStoredThumbnail {
            thumbnailHitCount += 1
        } else {
            thumbnailMissCount += 1
        }

        if !firstThumbnailLoggedForCurrentReload, let startedAt = photosReloadStartedAt {
            firstThumbnailLoggedForCurrentReload = true
            let elapsed = startedAt.duration(to: .now)
            let elapsedMs = Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            AppLog.debug("📊 Photos thumbnails: firstVisibleMs=\(elapsedMs)")
        }

        AppLog.debug(
            "📊 Photos thumbnails: hits=\(thumbnailHitCount) misses=\(thumbnailMissCount) uniqueTiles=\(seenPhotoIDsInCurrentReload.count)"
        )
    }
}

actor PhotoThumbnailBackfillService {
    typealias ThumbnailGenerator = @Sendable (Data) -> Data?
    typealias ThumbnailPersister = @Sendable (PersistentIdentifier, Data, ModelContainer) async -> Bool

    private struct BackfillJob {
        let photoID: PersistentIdentifier
        let imageData: Data
        let modelContainer: ModelContainer
        let source: String
    }

    static let shared = PhotoThumbnailBackfillService()

    private let maxConcurrentJobs: Int
    private let generateThumbnail: ThumbnailGenerator
    private let persistThumbnail: ThumbnailPersister

    private var queue: [BackfillJob] = []
    private var queuedIDs: Set<PersistentIdentifier> = []
    private var inFlightIDs: Set<PersistentIdentifier> = []
    private var inFlightJobs: [PersistentIdentifier: BackfillJob] = [:]
    private var activeJobs: Int = 0

    init(
        maxConcurrentJobs: Int = 2,
        generateThumbnail: @escaping ThumbnailGenerator = PhotoThumbnailBackfillService.defaultGenerateThumbnail,
        persistThumbnail: @escaping ThumbnailPersister = PhotoThumbnailBackfillService.defaultPersistThumbnail
    ) {
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
        self.generateThumbnail = generateThumbnail
        self.persistThumbnail = persistThumbnail
    }

    func enqueueIfNeeded(
        photoID: PersistentIdentifier,
        originalImageData: Data,
        existingThumbnailData: Data?,
        modelContainer: ModelContainer?,
        source: String
    ) {
        guard existingThumbnailData == nil else { return }
        guard let modelContainer else { return }
        guard !queuedIDs.contains(photoID), !inFlightIDs.contains(photoID) else { return }

        let job = BackfillJob(
            photoID: photoID,
            imageData: originalImageData,
            modelContainer: modelContainer,
            source: source
        )
        queue.append(job)
        queuedIDs.insert(photoID)
        scheduleIfPossible()
    }

    func debugState() -> (queued: Int, inFlight: Int, active: Int) {
        (queue.count, inFlightIDs.count, activeJobs)
    }

    private func scheduleIfPossible() {
        while activeJobs < maxConcurrentJobs, !queue.isEmpty {
            let job = queue.removeFirst()
            queuedIDs.remove(job.photoID)
            inFlightIDs.insert(job.photoID)
            inFlightJobs[job.photoID] = job
            activeJobs += 1

            let photoID = job.photoID
            let imageData = job.imageData
            let source = job.source
            let generateThumbnail = generateThumbnail
            let startedAt = ContinuousClock.now

            Task.detached(priority: .utility) {
                let generatedData = generateThumbnail(imageData)
                let elapsed = startedAt.duration(to: .now)
                let elapsedMs = Int(elapsed.components.seconds * 1_000)
                    + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                await self.finishJob(
                    photoID: photoID,
                    generatedData: generatedData,
                    source: source,
                    elapsedMs: elapsedMs
                )
            }
        }
    }

    private func finishJob(
        photoID: PersistentIdentifier,
        generatedData: Data?,
        source: String,
        elapsedMs: Int
    ) async {
        defer {
            inFlightJobs.removeValue(forKey: photoID)
            inFlightIDs.remove(photoID)
            activeJobs = max(activeJobs - 1, 0)
            scheduleIfPossible()
        }

        guard let job = inFlightJobs[photoID] else { return }
        guard let generatedData else {
            AppLog.debug("⚠️ Thumbnail backfill: source=\(source) id=\(photoID) generated=false elapsedMs=\(elapsedMs)")
            return
        }

        let persisted = await persistThumbnail(photoID, generatedData, job.modelContainer)
        AppLog.debug(
            "📊 Thumbnail backfill: source=\(source) id=\(photoID) persisted=\(persisted) bytes=\(generatedData.count) elapsedMs=\(elapsedMs)"
        )
    }

    private static func defaultGenerateThumbnail(imageData: Data) -> Data? {
        PhotoUtilities.makeGridThumbnailData(from: imageData)
    }

    private static func defaultPersistThumbnail(
        photoID: PersistentIdentifier,
        thumbnailData: Data,
        modelContainer: ModelContainer
    ) async -> Bool {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        guard let photo = context.model(for: photoID) as? PhotoEntry else {
            return false
        }
        guard photo.thumbnailData == nil else {
            return true
        }

        photo.thumbnailData = thumbnailData
        do {
            try context.save()
            return true
        } catch {
            AppLog.debug("⚠️ Thumbnail backfill: save failed for \(photoID): \(error)")
            return false
        }
    }
}
