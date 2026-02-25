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
    let date: Date
    let tags: [PhotoTag]
    let thumbnailData: Data
    var progress: Double
    var status: PendingPhotoSaveStatus
}

struct PendingPhotoSaveCompletedEvent {
    let id: UUID
    let entry: PhotoEntry
    let eventID: UUID
}

private struct PendingPhotoSaveMetricRecord: Codable {
    let kindRaw: String
    let displayValue: Double
}

private struct PendingPhotoSpoolRecord: Codable {
    let id: UUID
    let createdAt: Date
    let date: Date
    let tags: [String]
    let metricValues: [PendingPhotoSaveMetricRecord]
    let unitsSystem: String
}

@MainActor
final class PendingPhotoSaveStore: ObservableObject {
    enum PendingSaveError: LocalizedError {
        case modelContainerNotConfigured
        case sourceEncodingFailed
        case spoolWriteFailed

        var errorDescription: String? {
            switch self {
            case .modelContainerNotConfigured:
                return "PendingPhotoSaveStore is not configured"
            case .sourceEncodingFailed:
                return "Could not encode source image"
            case .spoolWriteFailed:
                return "Could not persist queued image"
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
            guard fileManager.fileExists(atPath: directory.path) else {
                pendingItems = []
                processQueueIfNeeded()
                return
            }
            let jsonURLs = try fileManager
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            var restored: [PendingPhotoSaveItem] = []
            for jsonURL in jsonURLs {
                guard let id = pendingID(from: jsonURL) else { continue }
                let jsonData = try Data(contentsOf: jsonURL)
                let record = try JSONDecoder().decode(PendingPhotoSpoolRecord.self, from: jsonData)
                let thumbURL = thumbnailURL(for: id)
                guard fileManager.fileExists(atPath: thumbURL.path) else {
                    try? cleanupSpoolFiles(for: id)
                    continue
                }
                let thumbData = try Data(contentsOf: thumbURL)
                let tags = record.tags.compactMap { PhotoTag(rawValue: $0) }
                restored.append(
                    PendingPhotoSaveItem(
                        id: record.id,
                        createdAt: record.createdAt,
                        date: record.date,
                        tags: tags,
                        thumbnailData: thumbData,
                        progress: 0.10,
                        status: .queued
                    )
                )
            }
            pendingItems = dedupAndSort(restored)
            processQueueIfNeeded()
        } catch {
            AppLog.debug("⚠️ PendingPhotoSaveStore restore failed: \(error)")
        }
    }

    func enqueueSingle(
        sourceImage: UIImage,
        date: Date,
        tags: Set<PhotoTag>,
        metricValues: [MetricKind: Double],
        unitsSystem: String
    ) async throws -> UUID {
        guard modelContainer != nil else {
            throw PendingSaveError.modelContainerNotConfigured
        }

        let id = UUID()
        let createdAt = AppClock.now

        guard let sourceData = sourceImage.jpegData(compressionQuality: 0.95) ?? sourceImage.pngData() else {
            throw PendingSaveError.sourceEncodingFailed
        }
        let thumbImage = PhotoUtilities.thumbnail(from: sourceImage, size: CGSize(width: 220, height: 240))
        guard let thumbData = thumbImage.jpegData(compressionQuality: 0.85) ?? thumbImage.pngData() else {
            throw PendingSaveError.sourceEncodingFailed
        }

        let metricRecords = metricValues
            .filter { $0.value > 0 }
            .map { PendingPhotoSaveMetricRecord(kindRaw: $0.key.rawValue, displayValue: $0.value) }

        let record = PendingPhotoSpoolRecord(
            id: id,
            createdAt: createdAt,
            date: date,
            tags: tags.map(\.rawValue),
            metricValues: metricRecords,
            unitsSystem: unitsSystem
        )

        do {
            try persist(record: record, sourceData: sourceData, thumbnailData: thumbData)
        } catch {
            throw PendingSaveError.spoolWriteFailed
        }

        let pendingItem = PendingPhotoSaveItem(
            id: id,
            createdAt: createdAt,
            date: date,
            tags: Array(tags),
            thumbnailData: thumbData,
            progress: 0.10,
            status: .queued
        )

        pendingItems = dedupAndSort(pendingItems + [pendingItem])
        processQueueIfNeeded()
        return id
    }

    func enqueueMany(
        sourceImages: [UIImage],
        date: Date,
        tags: Set<PhotoTag>,
        metricValues: [MetricKind: Double],
        unitsSystem: String,
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
                    unitsSystem: unitsSystem
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

        return queuedIDs
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

        while let nextID = pendingItems.sorted(by: { $0.createdAt < $1.createdAt }).first?.id {
            await processJob(id: nextID)
        }
    }

    private func processJob(id: UUID) async {
        do {
            guard modelContainer != nil else {
                throw PendingSaveError.modelContainerNotConfigured
            }
            guard let record = try loadRecord(for: id) else {
                throw PendingSaveError.spoolWriteFailed
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

            let saveResult = try saveRecord(record, encoded: encoded)
            completeProgressAnimation(id: id, to: 0.97)

            updateItem(id: id, status: .finalizing)
            startProgressAnimation(id: id, to: 1.0, duration: 0.18)
            await sleepForUITestIfNeeded(milliseconds: 1_500)
            completeProgressAnimation(id: id, to: 1.0)

            progressAnimationTasks[id]?.cancel()
            progressAnimationTasks[id] = nil
            pendingItems.removeAll { $0.id == id }
            try? cleanupSpoolFiles(for: id)

            completedEvent = PendingPhotoSaveCompletedEvent(
                id: id,
                entry: saveResult.entry,
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
        } catch {
            progressAnimationTasks[id]?.cancel()
            progressAnimationTasks[id] = nil
            pendingItems.removeAll { $0.id == id }
            try? cleanupSpoolFiles(for: id)
            lastFailureMessage = AppLocalization.string("Could not save photo. Please try again.")
            AppLog.debug("❌ PendingPhotoSaveStore: job=\(id.uuidString) failed: \(error)")
        }
    }

    private func saveRecord(
        _ record: PendingPhotoSpoolRecord,
        encoded: PhotoUtilities.EncodedPhoto
    ) throws -> (entry: PhotoEntry, prewarmData: Data, prewarmCacheID: String) {
        guard let modelContainer else {
            throw PendingSaveError.modelContainerNotConfigured
        }

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

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

        let resolvedTags = record.tags.compactMap { PhotoTag(rawValue: $0) }
        let entry = PhotoEntry(
            imageData: encoded.data,
            date: record.date,
            tags: resolvedTags.isEmpty ? [.wholeBody] : resolvedTags,
            linkedMetrics: snapshots
        )
        context.insert(entry)
        try context.save()

        return (entry: entry, prewarmData: encoded.data, prewarmCacheID: String(describing: entry.id))
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

    private func persist(record: PendingPhotoSpoolRecord, sourceData: Data, thumbnailData: Data) throws {
        let jsonData = try JSONEncoder().encode(record)
        try fileManager.createDirectory(at: try spoolDirectoryURL(), withIntermediateDirectories: true)
        try sourceData.write(to: sourceURL(for: record.id), options: .atomic)
        try thumbnailData.write(to: thumbnailURL(for: record.id), options: .atomic)
        try jsonData.write(to: recordURL(for: record.id), options: .atomic)
    }

    private func loadRecord(for id: UUID) throws -> PendingPhotoSpoolRecord? {
        let url = recordURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PendingPhotoSpoolRecord.self, from: data)
    }

    private func cleanupSpoolFiles(for id: UUID) throws {
        let urls = [recordURL(for: id), sourceURL(for: id), thumbnailURL(for: id)]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func dedupAndSort(_ items: [PendingPhotoSaveItem]) -> [PendingPhotoSaveItem] {
        var map: [UUID: PendingPhotoSaveItem] = [:]
        for item in items {
            map[item.id] = item
        }
        return map.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
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

    private func recordURL(for id: UUID) -> URL {
        (try? spoolDirectoryURL())?.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
            ?? URL(fileURLWithPath: "/tmp/\(id.uuidString).json")
    }

    private func sourceURL(for id: UUID) -> URL {
        (try? spoolDirectoryURL())?.appendingPathComponent("\(id.uuidString).source.jpg", isDirectory: false)
            ?? URL(fileURLWithPath: "/tmp/\(id.uuidString).source.jpg")
    }

    private func thumbnailURL(for id: UUID) -> URL {
        (try? spoolDirectoryURL())?.appendingPathComponent("\(id.uuidString).thumb.jpg", isDirectory: false)
            ?? URL(fileURLWithPath: "/tmp/\(id.uuidString).thumb.jpg")
    }

    private func pendingID(from jsonURL: URL) -> UUID? {
        let basename = jsonURL.deletingPathExtension().lastPathComponent
        return UUID(uuidString: basename)
    }

    private var shouldInjectUITestDelay: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestPendingSlow")
        #else
        false
        #endif
    }

    private var shouldInjectUITestFailure: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestPendingForceFailure") && !didInjectUITestFailure {
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
