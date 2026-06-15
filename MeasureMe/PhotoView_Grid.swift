import SwiftUI
import SwiftData
import UIKit

// MARK: - Grid render item

enum PhotoGridRenderItem: Identifiable {
    case persisted(PhotoEntry)
    case pending(PendingPhotoSaveItem)

    var id: String {
        switch self {
        case .persisted(let photo):
            return "persisted_\(singlePhotoSaveID(for: photo))"
        case .pending(let item):
            return "pending_\(item.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .persisted(let photo):
            return photo.date
        case .pending(let item):
            return item.date
        }
    }
}

// MARK: - Grid layout mode

enum PhotoGridLayoutMode: String {
    case review
    case compact

    var columnCount: Int {
        switch self {
        case .review: return 2
        case .compact: return 3
        }
    }

    var toggleTitle: String {
        switch self {
        case .review: return AppLocalization.string("Compact")
        case .compact: return AppLocalization.string("Review")
        }
    }

    var toggleIcon: String {
        switch self {
        case .review: return "square.grid.3x2"
        case .compact: return "rectangle.grid.2x2"
        }
    }

    var next: PhotoGridLayoutMode {
        switch self {
        case .review: return .compact
        case .compact: return .review
        }
    }
}

// MARK: - Month section

struct PhotoMonthSection: Identifiable {
    let id: String
    let title: String
    let items: [PhotoGridRenderItem]
}

// MARK: - Photo content view with Query

struct PhotoContentView: View {
    @Environment(\.modelContext) private var context

    let filters: PhotoFilters
    let isPremium: Bool
    let isSelecting: Bool
    @Binding var selectedPhotos: Set<PhotoEntry>
    let onPhotoTap: (PhotoEntry) -> Void
    let onPhotoLongPress: (PhotoEntry) -> Void
    let onAddPhoto: () -> Void
    let onOpenCompareChooser: () -> Void
    let onChooseHeroSlot: (PhotoComparePairSuggestion, CompareChooserSlot) -> Void
    let onOpenSuggestedCompare: (PhotoComparePairSuggestion) -> Void
    let heroCompareOverride: TemporaryHeroPairOverride?
    let refreshToken: UUID
    let recentlySavedPhoto: PhotoEntry?
    let recentlySavedPhotoEventID: UUID
    let pendingItems: [PendingPhotoSaveItem]

    @State private var photos: [PhotoEntry] = []
    @State private var isLoadingInitial: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var hasMore: Bool = true
    @State private var fetchOffset: Int = 0
    @State private var usesInMemoryTagFiltering: Bool = false
    @State private var hasAnySavedPhotos: Bool = false
    @State private var cachedRenderItems: [PhotoGridRenderItem] = []

    private let pageSize: Int = 60

    private var visiblePendingItems: [PendingPhotoSaveItem] {
        pendingItems.filter { filters.matches(date: $0.date, tags: $0.tags) }
    }

    private var renderItems: [PhotoGridRenderItem] {
        cachedRenderItems
    }

    private var archiveItems: [PhotoGridRenderItem] {
        renderItems
    }

    private var suggestedPair: PhotoComparePairSuggestion? {
        suggestedPhotoComparePair(from: photos)
    }

    private var activeHeroCompareOverride: TemporaryHeroPairOverride? {
        guard let heroCompareOverride, heroCompareOverride.isActive else { return nil }
        guard photos.contains(where: { $0.persistentModelID == heroCompareOverride.pair.olderPhoto.persistentModelID }),
              photos.contains(where: { $0.persistentModelID == heroCompareOverride.pair.newerPhoto.persistentModelID }) else {
            return nil
        }
        return heroCompareOverride
    }

    private var heroPairSuggestion: PhotoComparePairSuggestion? {
        if let activeHeroCompareOverride {
            return PhotoComparePairSuggestion(
                older: activeHeroCompareOverride.pair.olderPhoto,
                newer: activeHeroCompareOverride.pair.newerPhoto
            )
        }
        return suggestedPair
    }

    private var heroState: PhotoCompareHeroState {
        if photos.isEmpty && visiblePendingItems.isEmpty {
            return .onboarding
        }
        if let heroPairSuggestion {
            return .pair(heroPairSuggestion)
        }
        return .manualOnly
    }

    private var filtersKey: String {
        let tags = filters.selectedTags
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return "\(filters.dateRange.rawValue)|\(filters.customStartDate.timeIntervalSince1970)|\(filters.customEndDate.timeIntervalSince1970)|\(tags)|\(refreshToken.uuidString)"
    }

    var body: some View {
        PhotoGridView(
            filters: filters,
            archiveItems: archiveItems,
            heroState: heroState,
            hasAnySavedPhotos: hasAnySavedPhotos || !pendingItems.isEmpty,
            filtersActive: filters.isActive,
            isPremium: isPremium,
            isSelecting: isSelecting,
            selectedPhotos: $selectedPhotos,
            onPhotoTap: onPhotoTap,
            onPhotoLongPress: onPhotoLongPress,
            onAddPhoto: onAddPhoto,
            onOpenCompareChooser: onOpenCompareChooser,
            onChooseHeroSlot: onChooseHeroSlot,
            onOpenSuggestedCompare: onOpenSuggestedCompare,
            isLoadingInitial: isLoadingInitial,
            isLoadingMore: isLoadingMore,
            hasMore: hasMore,
            loadMoreToken: fetchOffset,
            onLoadMore: loadMoreIfNeeded
        )
        .task(id: filtersKey) {
            await reload()
        }
        .onChange(of: pendingItemsSignature) { _, _ in
            rebuildRenderItems()
        }
        .onChange(of: recentlySavedPhotoEventID) { _, _ in
            applyRecentlySavedPhoto()
        }
    }

    @MainActor
    private func reload() async {
        PhotoThumbnailTelemetry.beginPhotosReload()
        isLoadingInitial = true
        isLoadingMore = false
        hasMore = true
        fetchOffset = 0
        photos = []
        hasAnySavedPhotos = ((try? context.fetchCount(FetchDescriptor<PhotoEntry>())) ?? 0) > 0

        await loadMoreUntilVisibleOrExhausted()
        rebuildRenderItems()
        isLoadingInitial = false
    }

    private func loadMoreIfNeeded() {
        guard !isLoadingInitial, !isLoadingMore, hasMore else { return }
        Task { @MainActor in
            await loadMore()
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true

        let rawBatch = await fetchNextBatch()
        let batch = usesInMemoryTagFiltering ? rawBatch.filter { filters.matches($0) } : rawBatch

        photos.append(contentsOf: batch)
        fetchOffset += rawBatch.count
        hasMore = rawBatch.count == pageSize
        isLoadingMore = false
        rebuildRenderItems()
    }

    @MainActor
    private func loadMoreUntilVisibleOrExhausted() async {
        await loadMore()
        // If tag filtering cannot be pushed down to the store predicate (or is not supported),
        // the first pages may have 0 visible results. Continue paging until a result is found or data is exhausted.
        let needsMore = usesInMemoryTagFiltering && !filters.selectedTags.isEmpty
        while needsMore, photos.isEmpty, hasMore {
            await loadMore()
        }
    }

    @MainActor
    private func fetchNextBatch() async -> [PhotoEntry] {
        let predicate: Predicate<PhotoEntry>? = {
            if usesInMemoryTagFiltering {
                return dateOnlyPredicate()
            }
            return filters.buildPredicate()
        }()

        var descriptor = FetchDescriptor<PhotoEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = fetchOffset

        do {
            return try context.fetch(descriptor)
        } catch {
            // Some SwiftData backends cannot translate complex tag predicates.
            // Fallback: fetch by date only and filter in memory.
            if !usesInMemoryTagFiltering {
                usesInMemoryTagFiltering = true
                return await fetchNextBatch()
            }
            AppLog.debug("❌ Photo fetch failed: \(error)")
            return []
        }
    }

    private var pendingItemsSignature: String {
        pendingItems.map {
            "\($0.id.uuidString)|\($0.date.timeIntervalSince1970)|\($0.progress)|\($0.status.rawValue)"
        }
        .joined(separator: ",")
    }

    @MainActor
    private func rebuildRenderItems() {
        let visiblePendingItems = pendingItems.filter { filters.matches(date: $0.date, tags: $0.tags) }
        let persistedByID = Dictionary(
            uniqueKeysWithValues: photos.map { photo in
                let key = "persisted_\(singlePhotoSaveID(for: photo))"
                return (key, PhotoGridRenderItem.persisted(photo))
            }
        )
        let pendingByID = Dictionary(
            uniqueKeysWithValues: visiblePendingItems.map { item in
                let key = "pending_\(item.id.uuidString)"
                return (key, PhotoGridRenderItem.pending(item))
            }
        )
        let orderedIDs = PhotoFeedMergePlanner.orderedIDs(
            persisted: photos.map { photo in
                PhotoFeedMergeItem(
                    id: "persisted_\(singlePhotoSaveID(for: photo))",
                    date: photo.date
                )
            },
            pending: visiblePendingItems.map { item in
                PhotoFeedMergeItem(
                    id: "pending_\(item.id.uuidString)",
                    date: item.date
                )
            }
        )
        cachedRenderItems = orderedIDs.compactMap { id in
            pendingByID[id] ?? persistedByID[id]
        }
    }

    private func dateOnlyPredicate() -> Predicate<PhotoEntry>? {
        guard let start = filters.dateRange.startDate(customStart: filters.customStartDate),
              let end = filters.dateRange.endDate(customEnd: filters.customEndDate) else {
            return nil
        }
        return #Predicate<PhotoEntry> { photo in
            photo.date >= start && photo.date <= end
        }
    }

    @MainActor
    private func applyRecentlySavedPhoto() {
        let result = SinglePhotoSaveMergeEngine.apply(
            recentlySavedPhoto: recentlySavedPhoto,
            filters: filters,
            photos: photos,
            hasMore: hasMore,
            pageSize: pageSize,
            fetchOffset: fetchOffset
        )

        guard result.didUpdateList else { return }
        photos = result.photos
        fetchOffset = result.fetchOffset
        rebuildRenderItems()
    }
}

// MARK: - Photo Grid View (Reusable)

struct PhotoGridView: View {
    private let photosTheme = FeatureTheme.photos

    let filters: PhotoFilters
    let archiveItems: [PhotoGridRenderItem]
    let heroState: PhotoCompareHeroState
    let hasAnySavedPhotos: Bool
    let filtersActive: Bool
    let isPremium: Bool
    let isSelecting: Bool
    @Binding var selectedPhotos: Set<PhotoEntry>
    let onPhotoTap: (PhotoEntry) -> Void
    let onPhotoLongPress: (PhotoEntry) -> Void
    let onAddPhoto: () -> Void
    let onOpenCompareChooser: () -> Void
    let onChooseHeroSlot: (PhotoComparePairSuggestion, CompareChooserSlot) -> Void
    let onOpenSuggestedCompare: (PhotoComparePairSuggestion) -> Void
    let isLoadingInitial: Bool
    let isLoadingMore: Bool
    let hasMore: Bool
    let loadMoreToken: Int
    let onLoadMore: () -> Void
    @AppStorage("photos.gridLayoutMode") private var gridLayoutModeRaw: String = PhotoGridLayoutMode.review.rawValue

    private var gridLayoutMode: PhotoGridLayoutMode {
        PhotoGridLayoutMode(rawValue: gridLayoutModeRaw) ?? .review
    }

    private var monthSections: [PhotoMonthSection] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"

        var sections: [PhotoMonthSection] = []
        var currentKey: String?
        var currentTitle = ""
        var currentItems: [PhotoGridRenderItem] = []

        for item in archiveItems {
            let components = calendar.dateComponents([.year, .month], from: item.date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if currentKey != key {
                if let currentKey {
                    sections.append(PhotoMonthSection(id: currentKey, title: currentTitle, items: currentItems))
                }
                currentKey = key
                currentTitle = formatter.string(from: item.date)
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }

        if let currentKey {
            sections.append(PhotoMonthSection(id: currentKey, title: currentTitle, items: currentItems))
        }

        return sections
    }

    var body: some View {
        Group {
            if archiveItems.isEmpty {
                if isLoadingInitial {
                    ScrollView {
                        VStack(spacing: 18) {
                            headerSection
                            PhotoGridHeroSkeleton()
                            PhotoGridSkeletonView(itemCount: 6)
                        }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                    }
                } else {
                    emptyState
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection
                        PhotoCompareHeroCard(
                            state: heroState,
                            isPremium: isPremium,
                            onOpenChooser: onOpenCompareChooser,
                            onChooseOlderPhoto: chooseOlderHeroPhoto,
                            onChooseNewerPhoto: chooseNewerHeroPhoto,
                            onCompare: openHeroSuggestedCompare,
                            onAddPhoto: onAddPhoto
                        )

                        if case .onboarding = heroState { } else {
                            Button {
                                onAddPhoto()
                            } label: {
                                Label(AppLocalization.string("Add Photo"), systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                        }

                        archiveSection
                    }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    if hasMore || isLoadingMore {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .id(loadMoreToken)
                            .onAppear {
                                handleLoadMoreIndicatorAppear()
                            }
                    }
                }
            }
        }
    }

    var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerSection

                MiaraEmptyCard(
                    pose: .thumbs,
                    title: filtersActive && hasAnySavedPhotos
                        ? AppLocalization.string("No Photos Found")
                        : "„\(FlowLocalization.app("Your first photo is the start of your story.", "Pierwsze zdjęcie to start Twojej historii.", "Tu primera foto es el inicio de tu historia.", "Dein erstes Foto ist der Anfang deiner Geschichte.", "Ta première photo, c'est le début de ton histoire.", "Sua primeira foto é o começo da sua história."))”",
                    subtitle: filtersActive && hasAnySavedPhotos
                        ? AppLocalization.string("Try adjusting your filters or add a new photo")
                        : FlowLocalization.app(
                            "Take it today, and in a month you'll have something to compare. No need to change clothes — just the same angle.",
                            "Zrób je dziś, a za miesiąc będzie czego porównywać. Przebierać się nie trzeba — wystarczy ten sam kąt.",
                            "Hazla hoy y en un mes tendrás algo que comparar. No hace falta cambiarse — basta el mismo ángulo.",
                            "Mach es heute, in einem Monat hast du etwas zum Vergleichen. Kein Umziehen nötig — gleicher Winkel reicht.",
                            "Prends-la aujourd'hui et dans un mois tu auras de quoi comparer. Pas besoin de te changer — juste le même angle.",
                            "Tire hoje e em um mês terá o que comparar. Sem precisar trocar de roupa — basta o mesmo ângulo."
                        ),
                    ctaTitle: filtersActive && hasAnySavedPhotos
                        ? AppLocalization.string("Add Photo")
                        : AppLocalization.string("Take your first photo"),
                    onTap: { onAddPhoto() }
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScreenTitleHeader(title: AppLocalization.string("Photos"), topPadding: 6, bottomPadding: 0, horizontalPadding: 8)

            if filters.isActive {
                ActiveFiltersView(filters: filters) {
                    filters.reset()
                }
            }
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string("Photos"))
                    .font(AppTypography.headlineEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Spacer()
                Button {
                    gridLayoutModeRaw = gridLayoutMode.next.rawValue
                } label: {
                    Label(gridLayoutMode.toggleTitle, systemImage: gridLayoutMode.toggleIcon)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .foregroundStyle(photosTheme.accent)
                .accessibilityLabel(gridLayoutMode.toggleTitle)
            }

            photoGrid
        }
    }

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(monthSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .padding(.horizontal, 2)
                        .accessibilityIdentifier("photos.grid.monthHeader")

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: gridLayoutMode.columnCount
                        ),
                        spacing: 8
                    ) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            let globalIndex = archiveItems.firstIndex(where: { $0.id == item.id }) ?? index
                            renderGridItem(item, index: globalIndex)
                        }
                    }
                }
            }
        }
        .padding(.bottom, isSelecting && !selectedPhotos.isEmpty ? 80 : 0)
    }

    @ViewBuilder
    private func renderGridItem(_ item: PhotoGridRenderItem, index: Int) -> some View {
        let availableWidth = max(UIScreen.main.bounds.width - 24, 1)
        let spacing = CGFloat(gridLayoutMode.columnCount - 1) * 8
        let cellSize = floor((availableWidth - spacing) / CGFloat(gridLayoutMode.columnCount))

        switch item {
        case .persisted(let photo):
            Button {
                onPhotoTap(photo)
            } label: {
                PhotoGridCell(
                    photo: photo,
                    isSelected: selectedPhotos.contains(photo),
                    isSelecting: isSelecting,
                    size: cellSize,
                    revealIndex: index
                )
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0.5) {
                onPhotoLongPress(photo)
            }
            .accessibilityIdentifier("photos.grid.item")
            .accessibilityLabel(AppLocalization.string("Photo"))
            .accessibilityValue(photoAccessibilityValue(for: photo))
            .accessibilityHint(
                isSelecting
                ? AppLocalization.string("Double tap to select or deselect this photo")
                : AppLocalization.string("Double tap to open photo details")
            )
        case .pending(let pending):
            PendingPhotoGridCell(
                thumbnailData: pending.thumbnailData,
                progress: pending.progress,
                status: pending.status,
                targetSize: CGSize(width: cellSize, height: cellSize),
                cornerRadius: 12,
                cacheID: pending.id.uuidString,
                accessibilityIdentifier: "photos.grid.pending.item"
            )
            .frame(width: cellSize, height: cellSize)
        }
    }

    private func chooseOlderHeroPhoto() {
        guard case .pair(let suggestedPair) = heroState else { return }
        onChooseHeroSlot(suggestedPair, .older)
    }

    private func chooseNewerHeroPhoto() {
        guard case .pair(let suggestedPair) = heroState else { return }
        onChooseHeroSlot(suggestedPair, .newer)
    }

    private func openHeroSuggestedCompare() {
        guard case .pair(let suggestedPair) = heroState else { return }
        onOpenSuggestedCompare(suggestedPair)
    }

    private func handleLoadMoreIndicatorAppear() {
        onLoadMore()
    }

    private func photoAccessibilityValue(for photo: PhotoEntry) -> String {
        let dateText = photo.date.formatted(date: .abbreviated, time: .omitted)
        guard isSelecting else { return dateText }
        let selectedText = selectedPhotos.contains(photo)
            ? AppLocalization.string("Selected")
            : AppLocalization.string("Not selected")
        return "\(dateText), \(selectedText)"
    }
}

// MARK: - Hero skeleton

struct PhotoGridHeroSkeleton: View {
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldShimmer: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        SkeletonBlock(cornerRadius: 24, opacity: 0.18)
            .frame(height: 280)
            .skeletonShimmer(enabled: shouldShimmer)
    }
}
