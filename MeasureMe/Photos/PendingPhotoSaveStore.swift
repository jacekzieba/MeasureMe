import Foundation
import SwiftData
import SwiftUI
import UIKit
import Combine

enum PendingPhotoSaveStatus: String, Codable {
    case queued
    case encoding
    case saving
    case finalizing
    case done

    var title: String {
        switch self {
        case .queued:
            return AppLocalization.string("Preparing")
        case .encoding:
            return AppLocalization.string("Preparing")
        case .saving:
            return AppLocalization.string("Saving")
        case .finalizing:
            return AppLocalization.string("Finalizing")
        case .done:
            return AppLocalization.string("Done")
        }
    }
}

struct PendingPhotoSaveItem: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let batchID: UUID?
    let date: Date
    let tags: [PhotoTag]
    let thumbnailData: Data
    var progress: Double
    var status: PendingPhotoSaveStatus
}

struct PendingPhotoSaveCompletedEvent {
    let id: UUID
    let entryPersistentModelID: PersistentIdentifier
    let batchID: UUID?
    let eventID: UUID
}

private nonisolated struct PendingPhotoSaveMetricRecord: Codable {
    let kindRaw: String
    let displayValue: Double
}

private nonisolated struct PendingPhotoSpoolRecord: Codable {
    let id: UUID
    let createdAt: Date
    let batchID: UUID?
    let date: Date
    let tags: [String]
    let metricValues: [PendingPhotoSaveMetricRecord]
    let unitsSystem: String
}

private struct PendingEnqueuePreparedArtifacts {
    let sourceData: Data
    let thumbnailData: Data
}

private struct RestoredPendingSnapshot: Sendable {
    let id: UUID
    let createdAt: Date
    let batchID: UUID?
    let date: Date
    let tagRawValues: [String]
    let thumbnailData: Data
}

private struct RestorePayload: Sendable {
    let hasDirectory: Bool
    let restoredItems: [RestoredPendingSnapshot]
    let orphanIDs: [UUID]
}

private struct UncheckedUIImageBox: @unchecked Sendable {
    let image: UIImage
}

@MainActor
final class PendingPhotoSaveStore: ObservableObject {
    enum PendingSaveError: LocalizedError, Equatable {
        case modelContainerNotConfigured
        case sourceEncodingFailed
        case spoolWriteFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .modelContainerNotConfigured:
                return "PendingPhotoSaveStore is not configured"
            case .sourceEncodingFailed:
                return "Could not encode source image"
            case .spoolWriteFailed:
                return "Could not persist queued image"
            case .cancelled:
                return "Pending photo save job cancelled"
            }
        }
    }

    @Published private(set) var pendingItems: [PendingPhotoSaveItem] = []
    @Published var lastFailureMessage: String?
    @Published private(set) var completedEvent: PendingPhotoSaveCompletedEvent?
    @Published private(set) var lastCompletedProgress: Double = 0

    private let fileManager: FileManager
    private let baseDirectoryURL: URL?
    private let autoStartProcessing: Bool
    private let encodeSourceData: @Sendable (Data) -> PhotoUtilities.EncodedPhoto?

    private var modelContainer: ModelContainer?
    private var processingTask: Task<Void, Never>?
    private var progressAnimationTasks: [UUID: Task<Void, Never>] = [:]
    private var movingAverageEncodeDuration: TimeInterval = 0.85
    private var didInjectUITestFailure = false
    private var cancelledBatchIDs: Set<UUID> = []
    private var cancelledJobIDs: Set<UUID> = []
    private var processingOrder: [UUID] = []
    private var processingOrderSet: Set<UUID> = []

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        autoStartProcessing: Bool = true,
        encodeSourceData: @escaping @Sendable (Data) -> PhotoUtilities.EncodedPhoto? = { sourceData in
            guard let image = UIImage(data: sourceData) else { return nil }
            let prepared: UIImage
            if PhotoUtilities.isPreparedForImport(image, maxDimension: 2048) {
                prepared = image
            } else {
                prepared = PhotoUtilities.prepareImportedImage(image)
            }
            return PhotoUtilities.encodeForStorage(prepared, maxSize: 2_000_000, alreadyPrepared: true)
        }
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL
        self.autoStartProcessing = autoStartProcessing
        self.encodeSourceData = encodeSourceData
    }

    func configure(container: ModelContainer) {
        modelContainer = container
    }

    func restoreAndResume() {
        do {
            let directory = try spoolDirectoryURL()
            let payload = try Self.loadRestorePayload(from: directory)
            applyRestorePayload(payload)
        } catch {
            AppLog.debug("⚠️ PendingPhotoSaveStore restore failed: \(error)")
        }
    }

    func restoreAndResumeAsync() async {
        do {
            let directory = try spoolDirectoryURL()
            let payload = try await Task.detached(priority: .utility) {
                try Self.loadRestorePayload(from: directory)
            }.value
            applyRestorePayload(payload)
        } catch {
            AppLog.debug("⚠️ PendingPhotoSaveStore restore failed: \(error)")
        }
    }

    private func applyRestorePayload(_ payload: RestorePayload) {
        guard payload.hasDirectory else {
            pendingItems = []
            rebuildProcessingOrder(from: [])
            processQueueIfNeeded()
            return
        }

        for orphanID in payload.orphanIDs {
            try? cleanupSpoolFiles(for: orphanID)
        }

        let restoredItems = payload.restoredItems.map { snapshot in
            PendingPhotoSaveItem(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                batchID: snapshot.batchID,
                date: snapshot.date,
                tags: snapshot.tagRawValues.compactMap(PhotoTag.init(rawValue:)),
                thumbnailData: snapshot.thumbnailData,
                progress: 0.10,
                status: .queued
            )
        }
        var uniqueByID: [UUID: PendingPhotoSaveItem] = [:]
        for item in restoredItems {
            uniqueByID[item.id] = item
        }
        pendingItems = uniqueByID.values.sorted { lhs, rhs in
            compareQueuePriority(
                lhsID: lhs.id,
                lhsCreatedAt: lhs.createdAt,
                rhsID: rhs.id,
                rhsCreatedAt: rhs.createdAt
            )
        }
        rebuildProcessingOrder(from: pendingItems)
        processQueueIfNeeded()
    }

    private nonisolated static func loadRestorePayload(from directory: URL) throws -> RestorePayload {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return RestorePayload(hasDirectory: false, restoredItems: [], orphanIDs: [])
        }

        let jsonURLs = try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var restored: [RestoredPendingSnapshot] = []
        var orphanIDs: [UUID] = []

        for jsonURL in jsonURLs {
            guard let id = UUID(uuidString: jsonURL.deletingPathExtension().lastPathComponent) else { continue }
            let jsonData = try Data(contentsOf: jsonURL)
            let record = try JSONDecoder().decode(PendingPhotoSpoolRecord.self, from: jsonData)
            let thumbURL = directory.appendingPathComponent("\(id.uuidString).thumb.jpg", isDirectory: false)
            guard fileManager.fileExists(atPath: thumbURL.path) else {
                orphanIDs.append(id)
                continue
            }
            let thumbData = try Data(contentsOf: thumbURL)
            restored.append(
                RestoredPendingSnapshot(
                    id: record.id,
                    createdAt: record.createdAt,
                    batchID: record.batchID,
                    date: record.date,
                    tagRawValues: record.tags,
                    thumbnailData: thumbData
                )
            )
        }

        return RestorePayload(
            hasDirectory: true,
            restoredItems: restored,
            orphanIDs: orphanIDs
        )
    }

    func enqueueSingle(
        sourceImage: UIImage,
        date: Date,
        tags: Set<PhotoTag>,
        metricValues: [MetricKind: Double],
        unitsSystem: String,
        batchID: UUID? = nil
    ) async throws -> UUID {
        guard modelContainer != nil else {
            throw PendingSaveError.modelContainerNotConfigured
        }

        let id = UUID()
        let createdAt = AppClock.now
        let preparedArtifacts = try await prepareEnqueueArtifacts(sourceImage: sourceImage)

        let metricRecords = metricValues
            .filter { $0.value > 0 }
            .map { PendingPhotoSaveMetricRecord(kindRaw: $0.key.rawValue, displayValue: $0.value) }

        let record = PendingPhotoSpoolRecord(
            id: id,
            createdAt: createdAt,
            batchID: batchID,
            date: date,
            tags: tags.map(\.rawValue),
            metricValues: metricRecords,
            unitsSystem: unitsSystem
        )

        do {
            try persist(
                record: record,
                sourceData: preparedArtifacts.sourceData,
                thumbnailData: preparedArtifacts.thumbnailData
            )
        } catch {
            throw PendingSaveError.spoolWriteFailed
        }

        let pendingItem = PendingPhotoSaveItem(
            id: id,
            createdAt: createdAt,
            batchID: batchID,
            date: date,
            tags: Array(tags),
            thumbnailData: preparedArtifacts.thumbnailData,
            progress: 0.10,
            status: .queued
        )

        insertPendingItemSorted(pendingItem)
        insertIntoProcessingOrder(id: pendingItem.id, createdAt: pendingItem.createdAt)
        processQueueIfNeeded()
        return id
    }

    func enqueueMany(
        sourceImages: [UIImage],
        date: Date,
        tags: Set<PhotoTag>,
        metricValues: [MetricKind: Double],
        unitsSystem: String,
        batchID: UUID = UUID(),
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [UUID] {
        guard modelContainer != nil else {
            throw PendingSaveError.modelContainerNotConfigured
        }
        guard !sourceImages.isEmpty else { return [] }

        let total = sourceImages.count
        var queuedIDs: [UUID] = []

        for (index, image) in sourceImages.enumerated() {
            do {
                let id = try await enqueueSingle(
                    sourceImage: image,
                    date: date,
                    tags: tags,
                    metricValues: metricValues,
                    unitsSystem: unitsSystem,
                    batchID: batchID
                )
                queuedIDs.append(id)
            } catch {
                AppLog.debug("⚠️ PendingPhotoSaveStore: enqueueMany skipped \(index + 1)/\(total): \(error)")
            }
            progress?(index + 1, total)
        }

        guard !queuedIDs.isEmpty else {
            throw PendingSaveError.spoolWriteFailed
        }

        AppLog.debug("📸 PendingPhotoSaveStore: enqueueMany queued=\(queuedIDs.count) batchID=\(batchID.uuidString)")
        return queuedIDs
    }

    func cancelPending(batchIDs: Set<UUID>) {
        guard !batchIDs.isEmpty else { return }

        cancelledBatchIDs.formUnion(batchIDs)
        let matchedJobs = pendingItems.filter { item in
            guard let batchID = item.batchID else { return false }
            return batchIDs.contains(batchID)
        }
        cancelledJobIDs.formUnion(matchedJobs.map(\.id))

        for item in matchedJobs {
            progressAnimationTasks[item.id]?.cancel()
            progressAnimationTasks[item.id] = nil
            try? cleanupSpoolFiles(for: item.id)
            removeFromProcessingOrder(id: item.id)
        }

        pendingItems.removeAll { item in
            guard let batchID = item.batchID else { return false }
            return batchIDs.contains(batchID)
        }

        AppLog.debug(
            "🧹 PendingPhotoSaveStore: cancelledBatchCount=\(batchIDs.count) cancelledJobsCount=\(matchedJobs.count)"
        )
    }

    func clearFailureMessage() {
        lastFailureMessage = nil
    }

    private func processQueueIfNeeded() {
        guard autoStartProcessing else { return }
        guard processingTask == nil else { return }
        guard !pendingItems.isEmpty else { return }

        processingTask = Task { [weak self] in
            await self?.processQueueLoop()
        }
    }

    private func processQueueLoop() async {
        defer { processingTask = nil }

        while let nextID = nextPendingProcessingID() {
            await processJob(id: nextID)
        }
    }

    private func processJob(id: UUID) async {
        defer {
            cancelledJobIDs.remove(id)
        }

        do {
            guard modelContainer != nil else {
                throw PendingSaveError.modelContainerNotConfigured
            }
            guard let record = try loadRecord(for: id) else {
                throw PendingSaveError.spoolWriteFailed
            }
            if isCancelled(jobID: id, batchID: record.batchID) {
                throw PendingSaveError.cancelled
            }

            updateItem(id: id, status: .encoding)
            let encodeDuration = estimateEncodeDuration(for: id)
            startProgressAnimation(id: id, to: 0.85, duration: encodeDuration)

            await sleepForUITestIfNeeded(milliseconds: 2_000)

            let sourceData = try Data(contentsOf: sourceURL(for: id))
            let encodeStart = ContinuousClock.now
            let encoded = await Task.detached(priority: .userInitiated) { [encodeSourceData] in
                encodeSourceData(sourceData)
            }.value
            let encodeElapsed = encodeStart.duration(to: .now)
            updateEncodeAverage(with: encodeElapsed)
            completeProgressAnimation(id: id, to: 0.85)

            if isCancelled(jobID: id, batchID: record.batchID) {
                throw PendingSaveError.cancelled
            }

            guard let encoded else {
                throw PendingSaveError.sourceEncodingFailed
            }

            updateItem(id: id, status: .saving)
            startProgressAnimation(id: id, to: 0.97, duration: 0.35)

            if shouldInjectUITestFailure {
                await sleepForUITestIfNeeded(milliseconds: 2_000)
                throw PendingSaveError.sourceEncodingFailed
            }

            await sleepForUITestIfNeeded(milliseconds: 2_000)

            let queuedThumbnailData = try? Data(contentsOf: thumbnailURL(for: id))
            let saveResult = try saveRecord(
                record,
                encoded: encoded,
                thumbnailData: queuedThumbnailData
            )
            completeProgressAnimation(id: id, to: 0.97)

            if isCancelled(jobID: id, batchID: record.batchID) {
                try deleteEntryByPersistentModelID(saveResult.entryPersistentModelID)
                AppLog.debug(
                    "🧹 PendingPhotoSaveStore: postCancelLateCompletionDropped jobID=\(id.uuidString) batchID=\(record.batchID?.uuidString ?? "none")"
                )
                throw PendingSaveError.cancelled
            }

            updateItem(id: id, status: .finalizing)
            startProgressAnimation(id: id, to: 1.0, duration: 0.18)
            await sleepForUITestIfNeeded(milliseconds: 1_500)
            completeProgressAnimation(id: id, to: 1.0)

            progressAnimationTasks[id]?.cancel()
            progressAnimationTasks[id] = nil
            removePendingItem(id: id)
            try? cleanupSpoolFiles(for: id)

            completedEvent = PendingPhotoSaveCompletedEvent(
                id: id,
                entryPersistentModelID: saveResult.entryPersistentModelID,
                batchID: record.batchID,
                eventID: UUID()
            )
            lastCompletedProgress = 1.0

            let prewarmData = saveResult.prewarmData
            let prewarmCacheID = saveResult.prewarmCacheID
            Task.detached(priority: .utility) {
                await ImagePipeline.prewarmRecentPhotoVariants(
                    imageData: prewarmData,
                    cacheID: prewarmCacheID
                )
            }

            NotificationManager.shared.recordPhotoAdded(date: record.date)
            StreakManager.shared.recordPhotoSaved(date: record.date)
        } catch {
            progressAnimationTasks[id]?.cancel()
            progressAnimationTasks[id] = nil
            removePendingItem(id: id)
            try? cleanupSpoolFiles(for: id)

            if isCancellationError(error, jobID: id) {
                AppLog.debug("ℹ️ PendingPhotoSaveStore: job=\(id.uuidString) cancelled")
                return
            }

            lastFailureMessage = AppLocalization.string("Could not save photo. Please try again.")
            AppLog.debug("❌ PendingPhotoSaveStore: job=\(id.uuidString) failed: \(error)")
        }
    }

    private func saveRecord(
        _ record: PendingPhotoSpoolRecord,
        encoded: PhotoUtilities.EncodedPhoto,
        thumbnailData: Data?
    ) throws -> (entryPersistentModelID: PersistentIdentifier, prewarmData: Data, prewarmCacheID: String) {
        guard let modelContainer else {
            throw PendingSaveError.modelContainerNotConfigured
        }

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let previousPhotoCount = AnalyticsFirstEventTracker.photoCount(in: context)

        var snapshots: [MetricValueSnapshot] = []
        for metricRecord in record.metricValues {
            guard let kind = MetricKind(rawValue: metricRecord.kindRaw), metricRecord.displayValue > 0 else { continue }
            let metric = kind.valueToMetric(fromDisplay: metricRecord.displayValue, unitsSystem: record.unitsSystem)
            let sample = MetricSample(kind: kind, value: metric, date: record.date)
            context.insert(sample)

            snapshots.append(
                MetricValueSnapshot(
                    kind: kind,
                    value: metric,
                    unit: kind.unitSymbol(unitsSystem: "metric")
                )
            )
        }

        let resolvedThumbnailData = thumbnailData
            ?? PhotoUtilities.makeGridThumbnailData(from: encoded.data)

        let resolvedTags = record.tags.compactMap { PhotoTag(rawValue: $0) }
        let entry = PhotoEntry(
            imageData: encoded.data,
            thumbnailData: resolvedThumbnailData,
            date: record.date,
            tags: resolvedTags.isEmpty ? [.wholeBody] : resolvedTags,
            linkedMetrics: snapshots
        )
        context.insert(entry)
        try context.save()
        AnalyticsFirstEventTracker.trackFirstPhotoIfNeeded(previousPhotoCount: previousPhotoCount)

        return (
            entryPersistentModelID: entry.persistentModelID,
            prewarmData: encoded.data,
            prewarmCacheID: String(describing: entry.id)
        )
    }

    private func updateItem(id: UUID, status: PendingPhotoSaveStatus? = nil, progress: Double? = nil) {
        guard let idx = pendingItems.firstIndex(where: { $0.id == id }) else { return }
        if let status {
            pendingItems[idx].status = status
        }
        if let progress {
            pendingItems[idx].progress = max(pendingItems[idx].progress, min(max(progress, 0), 1))
        }
    }

    private func startProgressAnimation(id: UUID, to target: Double, duration: TimeInterval) {
        guard duration > 0.01 else {
            updateItem(id: id, progress: target)
            return
        }

        progressAnimationTasks[id]?.cancel()
        let startValue = pendingItems.first(where: { $0.id == id })?.progress ?? 0

        progressAnimationTasks[id] = Task { [weak self] in
            guard let self else { return }
            let startDate = Date.now
            while !Task.isCancelled {
                let elapsed = Date.now.timeIntervalSince(startDate)
                if elapsed >= duration {
                    break
                }
                let fraction = elapsed / duration
                let value = startValue + (target - startValue) * fraction
                self.updateItem(id: id, progress: value)
                try? await Task.sleep(for: .milliseconds(16))
            }
            self.updateItem(id: id, progress: target)
        }
    }

    private func completeProgressAnimation(id: UUID, to value: Double) {
        progressAnimationTasks[id]?.cancel()
        progressAnimationTasks[id] = nil
        updateItem(id: id, progress: value)
    }

    private func estimateEncodeDuration(for id: UUID) -> TimeInterval {
        let sourceSize = (try? Data(contentsOf: sourceURL(for: id)).count) ?? 1_000_000
        let sizeFactor = min(max(Double(sourceSize) / 1_500_000.0, 0.6), 2.0)
        return min(max(movingAverageEncodeDuration * sizeFactor, 0.30), 2.5)
    }

    private func updateEncodeAverage(with duration: Duration) {
        let elapsed = Double(duration.components.seconds)
            + (Double(duration.components.attoseconds) / 1_000_000_000_000_000_000.0)
        let value = min(max(elapsed, 0.10), 3.0)
        movingAverageEncodeDuration = movingAverageEncodeDuration * 0.75 + value * 0.25
    }

    private func prepareEnqueueArtifacts(sourceImage: UIImage) async throws -> PendingEnqueuePreparedArtifacts {
        let box = UncheckedUIImageBox(image: sourceImage)
        return try await Task.detached(priority: .userInitiated) {
            guard let sourceData = box.image.jpegData(compressionQuality: 0.95) ?? box.image.pngData() else {
                throw PendingSaveError.sourceEncodingFailed
            }
            guard let thumbData = PhotoUtilities.makeGridThumbnailData(from: box.image) else {
                throw PendingSaveError.sourceEncodingFailed
            }
            return PendingEnqueuePreparedArtifacts(
                sourceData: sourceData,
                thumbnailData: thumbData
            )
        }.value
    }

    private func isCancelled(jobID: UUID, batchID: UUID?) -> Bool {
        if cancelledJobIDs.contains(jobID) {
            return true
        }
        guard let batchID else { return false }
        return cancelledBatchIDs.contains(batchID)
    }

    private func isCancellationError(_ error: Error, jobID: UUID) -> Bool {
        if let pendingError = error as? PendingSaveError, pendingError == .cancelled {
            return true
        }
        return cancelledJobIDs.contains(jobID)
    }

    private func deleteEntryByPersistentModelID(_ id: PersistentIdentifier) throws {
        guard let modelContainer else {
            throw PendingSaveError.modelContainerNotConfigured
        }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        if let model = context.model(for: id) as? PhotoEntry {
            context.delete(model)
            try context.save()
        }
    }

    private func persist(record: PendingPhotoSpoolRecord, sourceData: Data, thumbnailData: Data) throws {
        let jsonData = try JSONEncoder().encode(record)
        try fileManager.createDirectory(at: try spoolDirectoryURL(), withIntermediateDirectories: true)
        try sourceData.write(to: sourceURL(for: record.id), options: .atomic)
        try thumbnailData.write(to: thumbnailURL(for: record.id), options: .atomic)
        try jsonData.write(to: recordURL(for: record.id), options: .atomic)
    }

    private func loadRecord(for id: UUID) throws -> PendingPhotoSpoolRecord? {
        let url = try recordURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PendingPhotoSpoolRecord.self, from: data)
    }

    private func cleanupSpoolFiles(for id: UUID) throws {
        let urls = [try recordURL(for: id), try sourceURL(for: id), try thumbnailURL(for: id)]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func rebuildProcessingOrder(from items: [PendingPhotoSaveItem]) {
        let sorted = items.sorted { lhs, rhs in
            compareQueuePriority(
                lhsID: lhs.id,
                lhsCreatedAt: lhs.createdAt,
                rhsID: rhs.id,
                rhsCreatedAt: rhs.createdAt
            )
        }
        processingOrder = sorted.map(\.id)
        processingOrderSet = Set(processingOrder)
    }

    private func insertIntoProcessingOrder(id: UUID, createdAt: Date) {
        guard !processingOrderSet.contains(id) else { return }
        var insertionIndex = processingOrder.endIndex
        for (index, existingID) in processingOrder.enumerated() {
            guard let existingCreatedAt = pendingItems.first(where: { $0.id == existingID })?.createdAt else {
                continue
            }
            if compareQueuePriority(
                lhsID: id,
                lhsCreatedAt: createdAt,
                rhsID: existingID,
                rhsCreatedAt: existingCreatedAt
            ) {
                insertionIndex = index
                break
            }
        }
        processingOrder.insert(id, at: insertionIndex)
        processingOrderSet.insert(id)
    }

    private func removeFromProcessingOrder(id: UUID) {
        guard processingOrderSet.contains(id) else { return }
        processingOrderSet.remove(id)
        if let index = processingOrder.firstIndex(of: id) {
            processingOrder.remove(at: index)
        }
    }

    private func nextPendingProcessingID() -> UUID? {
        while let firstID = processingOrder.first {
            if pendingItems.contains(where: { $0.id == firstID }) {
                return firstID
            }
            processingOrder.removeFirst()
            processingOrderSet.remove(firstID)
        }
        return nil
    }

    private func compareQueuePriority(lhsID: UUID, lhsCreatedAt: Date, rhsID: UUID, rhsCreatedAt: Date) -> Bool {
        if lhsCreatedAt == rhsCreatedAt {
            return lhsID.uuidString < rhsID.uuidString
        }
        return lhsCreatedAt < rhsCreatedAt
    }

    private func insertPendingItemSorted(_ item: PendingPhotoSaveItem) {
        if let existingIndex = pendingItems.firstIndex(where: { $0.id == item.id }) {
            pendingItems.remove(at: existingIndex)
            removeFromProcessingOrder(id: item.id)
        }
        var insertionIndex = pendingItems.endIndex
        for (index, existing) in pendingItems.enumerated() {
            if compareQueuePriority(
                lhsID: item.id,
                lhsCreatedAt: item.createdAt,
                rhsID: existing.id,
                rhsCreatedAt: existing.createdAt
            ) {
                insertionIndex = index
                break
            }
        }
        pendingItems.insert(item, at: insertionIndex)
    }

    private func removePendingItem(id: UUID) {
        pendingItems.removeAll { $0.id == id }
        removeFromProcessingOrder(id: id)
    }

    private func spoolDirectoryURL() throws -> URL {
        if let baseDirectoryURL {
            return baseDirectoryURL.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("PendingPhotoSaves", isDirectory: true)
    }

    private func recordURL(for id: UUID) throws -> URL {
        try spoolDirectoryURL().appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func sourceURL(for id: UUID) throws -> URL {
        try spoolDirectoryURL().appendingPathComponent("\(id.uuidString).source.jpg", isDirectory: false)
    }

    private func thumbnailURL(for id: UUID) throws -> URL {
        try spoolDirectoryURL().appendingPathComponent("\(id.uuidString).thumb.jpg", isDirectory: false)
    }

    private func pendingID(from jsonURL: URL) -> UUID? {
        let basename = jsonURL.deletingPathExtension().lastPathComponent
        return UUID(uuidString: basename)
    }

    private var shouldInjectUITestDelay: Bool {
        #if DEBUG
        UITestArgument.isPresent(.pendingSlow)
        #else
        false
        #endif
    }

    private var shouldInjectUITestFailure: Bool {
        #if DEBUG
        if UITestArgument.isPresent(.pendingForceFailure) && !didInjectUITestFailure {
            didInjectUITestFailure = true
            return true
        }
        #endif
        return false
    }

    private func sleepForUITestIfNeeded(milliseconds: Int) async {
        guard shouldInjectUITestDelay else { return }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
