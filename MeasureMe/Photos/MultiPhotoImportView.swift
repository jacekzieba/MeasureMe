import SwiftUI
import SwiftData

private struct MultiPhotoItemDraft {
    let date: Date
    let tags: Set<PhotoTag>
    let metricValues: [MetricKind: Double]
}

private struct ResolvedMultiPhotoImportItem {
    let item: MultiPhotoImportPayload.Item
    let image: UIImage
}

/// Widok Quick Import dla wielu zdjęć jednocześnie.
/// Pozwala wybrać wspólną datę i tagi, a następnie zapisać wszystkie zdjęcia jednym tapem.
struct MultiPhotoImportView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeMetrics: ActiveMetricsStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore

    let payload: MultiPhotoImportPayload

    @State private var date: Date = AppClock.now
    @State private var selectedTags: Set<PhotoTag> = [.front]
    @State private var isSaving = false
    @State private var loadedImages: [UUID: UIImage] = [:]
    @State private var loadedThumbnails: [UUID: UIImage] = [:]
    @State private var loadingThumbnailIDs: Set<UUID> = []
    @State private var sourcePhotoDates: [UUID: Date] = [:]
    @State private var itemDrafts: [UUID: MultiPhotoItemDraft] = [:]
    @State private var singlePhotoPayload: MultiPhotoImportPayload.Item? = nil
    @AppStorage("multiImport.editHintDismissed") private var editHintDismissed: Bool = false
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    init(images: [UIImage]) {
        self.payload = MultiPhotoImportPayload(images: images)
    }

    init(payload: MultiPhotoImportPayload) {
        self.payload = payload
    }

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 200, tint: Color.cyan.opacity(0.18))

            ScrollView {
                VStack(spacing: 16) {
                    thumbnailStrip
                    if payload.items.count > 1 && !editHintDismissed {
                        editHintBanner
                    }
                    dateCard
                    tagsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle(importTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(importTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalization.string("Cancel")) {
                    dismiss()
                }
                .disabled(isSaving)
                .accessibilityIdentifier("multiImport.cancelButton")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.string("Save")) {
                    Haptics.medium()
                    Task { await saveAll() }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("multiImport.saveButton")
            }
        }
        .sheet(item: $singlePhotoPayload) { item in
            let draft = draft(for: item)
            NavigationStack {
                AddPhotoView(
                    previewImage: item.image ?? loadedImages[item.id],
                    previewSource: item.librarySource,
                    initialDate: draft.date,
                    initialTags: draft.tags,
                    initialMetricValues: draft.metricValues,
                    telemetrySource: .multiImport,
                    onPreparedForBatch: { prepared in
                        itemDrafts[item.id] = MultiPhotoItemDraft(
                            date: prepared.date,
                            tags: prepared.tags,
                            metricValues: prepared.metricValues
                        )
                        loadedImages[item.id] = prepared.image
                        loadedThumbnails[item.id] = PhotoUtilities.prepareImportedImage(prepared.image, maxDimension: 320)
                    }
                )
            }
        }
        .task(id: payload.id) {
            await preloadContent()
        }
    }
}

// MARK: - Subviews

private extension MultiPhotoImportView {

    var importTitle: String {
        let count = payload.items.count
        if count == 1 {
            return AppLocalization.string("Import 1 Photo")
        }
        let photosCount = AppLocalization.plural("import.photos.count", count)
        return AppLocalization.string("import.photos.title", photosCount)
    }

    var editHintBanner: some View {
        Button {
            editHintDismissed = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.cyan)
                Text(AppLocalization.string("multiImport.editHint"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(12)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var thumbnailStrip: some View {
        AppGlassCard(depth: .elevated, tint: Color.cyan.opacity(0.08), contentPadding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Photos"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(payload.items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                singlePhotoPayload = item
                                editHintDismissed = true
                            } label: {
                                ZStack {
                                    if let image = thumbnailImage(for: item) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay {
                                                ProgressView()
                                                    .tint(.white)
                                            }
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if payload.items.count > 1 {
                                        Text("\(index + 1)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(Color.black.opacity(0.55))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .padding(4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingThumbnailIDs.contains(item.id))
                        }
                    }
                    .padding(.bottom, 2)
                }
                .accessibilityIdentifier("multiImport.thumbnailStrip")
            }
        }
    }

    var dateCard: some View {
        PhotoFormDateSection(
            title: AppLocalization.string("Date"),
            date: $date
        )
    }

    var tagsCard: some View {
        PhotoFormTagsSection(
            title: AppLocalization.string("Tags"),
            tags: availableTags,
            accessibilityPrefix: "multiImport",
            tagBinding: tagBinding(for:)
        )
    }
}

// MARK: - Bindings & Actions

private extension MultiPhotoImportView {

    var availableTags: [PhotoTag] {
        var tags: [PhotoTag] = PhotoTag.primaryPoseTags
        tags.append(.wholeBody)
        let activeTags = activeMetrics.activeKinds
            .filter { $0 != .weight && $0 != .bodyFat && $0 != .leanBodyMass }
            .compactMap { PhotoTag(metricKind: $0) }
        tags.append(contentsOf: activeTags)
        return tags
    }

    func tagBinding(for tag: PhotoTag) -> Binding<Bool> {
        Binding(
            get: { selectedTags.contains(tag) },
            set: { isOn in
                if tag.isPrimaryPose {
                    selectedTags.subtract(Set(PhotoTag.primaryPoseTags))
                    selectedTags.insert(isOn ? tag : .front)
                    return
                }
                if isOn { selectedTags.insert(tag) } else { selectedTags.remove(tag) }
            }
        )
    }

    func thumbnailImage(for item: MultiPhotoImportPayload.Item) -> UIImage? {
        if let thumbnail = loadedThumbnails[item.id] {
            return thumbnail
        }
        if let image = item.image {
            return image
        }
        return loadedImages[item.id]
    }

    func draft(for item: MultiPhotoImportPayload.Item) -> MultiPhotoItemDraft {
        itemDrafts[item.id]
            ?? MultiPhotoItemDraft(
                date: sourcePhotoDates[item.id] ?? date,
                tags: selectedTags,
                metricValues: [:]
            )
    }

    @MainActor
    func preloadContent() async {
        var firstResolvedDate: Date?

        for item in payload.items {
            if let image = item.image {
                loadedImages[item.id] = image
                loadedThumbnails[item.id] = image
            }
            if let source = item.librarySource,
               let exifDate = await PhotoLibraryImageLoader.fetchCreationDate(from: source) {
                sourcePhotoDates[item.id] = exifDate
                if firstResolvedDate == nil {
                    firstResolvedDate = exifDate
                }
            }
        }

        if let firstResolvedDate {
            date = firstResolvedDate
        }

        let sourcesToLoad = payload.items.compactMap { item -> MultiPhotoImportPayload.Item? in
            guard item.image == nil else { return nil }
            return item
        }

        guard !sourcesToLoad.isEmpty else { return }
        loadingThumbnailIDs.formUnion(sourcesToLoad.map(\.id))

        // Kontrolowana równoległość = 1; priorytetem jest płynność przejścia i brak skoków pamięci.
        for item in sourcesToLoad {
            if Task.isCancelled { break }
            guard let source = item.librarySource else {
                loadingThumbnailIDs.remove(item.id)
                continue
            }
            do {
                let thumbnail = try await PhotoLibraryImageLoader.loadThumbnailImage(from: source)
                loadedThumbnails[item.id] = thumbnail
                loadingThumbnailIDs.remove(item.id)
            } catch {
                loadingThumbnailIDs.remove(item.id)
                AppLog.debug("⚠️ MultiPhotoImportView: thumbnail load failed for \(item.id): \(error)")
            }
        }
    }

    @MainActor
    func saveAll() async {
        guard !isSaving else { return }
        isSaving = true

        let itemsToQueue = payload.items
        let dateToQueue = date
        let tagsToQueue = selectedTags
        let unitsToQueue = unitsSystem
        let loadedSnapshot = loadedImages
        let sourceDatesToQueue = sourcePhotoDates
        let draftsToQueue = itemDrafts
        let batchID = UUID()
        let dismissStart = ContinuousClock.now

        dismiss()
        let dismissMs = milliseconds(from: dismissStart.duration(to: .now))

        Task { @MainActor in
            let imageResolveStart = ContinuousClock.now
            let resolvedItems = await resolveImagesForQueue(
                items: itemsToQueue,
                loadedImageCache: loadedSnapshot
            )
            let imageResolveMs = milliseconds(from: imageResolveStart.duration(to: .now))
            let enqueueStart = ContinuousClock.now

            do {
                let requests = resolvedItems.map { resolved in
                    let draft = draftForQueue(
                        item: resolved.item,
                        fallbackDate: dateToQueue,
                        fallbackTags: tagsToQueue,
                        sourceDates: sourceDatesToQueue,
                        drafts: draftsToQueue
                    )
                    return PendingPhotoSaveRequest(
                        sourceImage: resolved.image,
                        date: draft.date,
                        tags: draft.tags,
                        metricValues: draft.metricValues
                    )
                }
                let queuedIDs = try await pendingPhotoSaveStore.enqueueMany(
                    requests: requests,
                    unitsSystem: unitsToQueue,
                    telemetrySource: .multiImport,
                    batchID: batchID
                )
                let enqueueMs = milliseconds(from: enqueueStart.duration(to: .now))
                AppLog.debug(
                    "✅ MultiPhotoImportView: queued=\(queuedIDs.count)/\(itemsToQueue.count) resolveMs=\(imageResolveMs) enqueueManyMainThreadMs=\(enqueueMs) dismissMs=\(dismissMs) batchID=\(batchID.uuidString)"
                )
            } catch {
                pendingPhotoSaveStore.lastFailureMessage = AppLocalization.string("Could not save photos. Please try again.")
                AppLog.debug("❌ MultiPhotoImportView: enqueue failed: \(error)")
                Haptics.error()
            }
        }
    }

    @MainActor
    func resolveImagesForQueue(
        items: [MultiPhotoImportPayload.Item],
        loadedImageCache: [UUID: UIImage]
    ) async -> [ResolvedMultiPhotoImportItem] {
        var resolved: [ResolvedMultiPhotoImportItem] = []
        resolved.reserveCapacity(items.count)

        for item in items {
            if let preloaded = item.image ?? loadedImageCache[item.id] {
                resolved.append(ResolvedMultiPhotoImportItem(item: item, image: preloaded))
                continue
            }
            guard let source = item.librarySource else { continue }
            do {
                let loaded = try await PhotoLibraryImageLoader.loadPreparedImage(from: source)
                resolved.append(ResolvedMultiPhotoImportItem(item: item, image: loaded))
            } catch {
                AppLog.debug("⚠️ MultiPhotoImportView: source load failed for \(item.id): \(error)")
            }
        }
        return resolved
    }

    func draftForQueue(
        item: MultiPhotoImportPayload.Item,
        fallbackDate: Date,
        fallbackTags: Set<PhotoTag>,
        sourceDates: [UUID: Date],
        drafts: [UUID: MultiPhotoItemDraft]
    ) -> MultiPhotoItemDraft {
        drafts[item.id]
            ?? MultiPhotoItemDraft(
                date: sourceDates[item.id] ?? fallbackDate,
                tags: fallbackTags,
                metricValues: [:]
            )
    }

    func milliseconds(from duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

// MARK: - Preview

#if DEBUG
private func makePreviewContainer() -> ModelContainer {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PhotoEntry.self, configurations: config)
    } catch {
        fatalError("Preview ModelContainer failed: \(error)")
    }
}

#Preview {
    let images = (1...3).map { _ in UIImage(systemName: "photo.fill")! }
    NavigationStack {
        MultiPhotoImportView(images: images)
    }
    .modelContainer(makePreviewContainer())
    .environmentObject(ActiveMetricsStore())
    .environmentObject(PendingPhotoSaveStore(autoStartProcessing: false))
}
#endif
