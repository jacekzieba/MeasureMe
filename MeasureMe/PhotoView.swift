import SwiftUI
import SwiftData

/// Główny widok Photos w Tab Bar
/// Pokazuje zdjęcia w formie siatki (grid) z trybem selekcji i porównywania
/// Alternatywny widok listy znajduje się w PhotosListView (PhotosView.swift)
struct PhotoView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    
    @StateObject private var filters = PhotoFilters()
    @State private var showFilters = false
    @State private var showAddPhoto = false
    @State private var showCompare = false
    @State private var refreshToken = UUID()

    @State private var isSelecting = false
    @State private var selectedPhotos: Set<PhotoEntry> = []
    @State private var selectedPhotoForDetail: PhotoEntry?
    @State private var showDeleteConfirmation = false
    
    @AppStorage("photos_filter_tag") private var photosFilterTag: String = ""
    private var uiTestModeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestMode")
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(
                    topHeight: 380,
                    tint: Color.cyan.opacity(0.22)
                )
                
                VStack(spacing: 0) {
                    ScreenTitleHeader(title: AppLocalization.string("Photos"), topPadding: 6, bottomPadding: 2)

                    // Active filters bar
                    if filters.isActive {
                        ActiveFiltersView(filters: filters) {
                            filters.reset()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    }
                    
                    // Main content
                    ZStack(alignment: .bottom) {
                        PhotoContentView(
                            filters: filters,
                            isSelecting: isSelecting,
                            selectedPhotos: $selectedPhotos,
                            onPhotoTap: handlePhotoTap,
                            onPhotoLongPress: handlePhotoLongPress,
                            onAddPhoto: {
                                Haptics.light()
                                showAddPhoto = true
                            },
                            refreshToken: refreshToken
                        )
                        .refreshable {
                            refreshToken = UUID()
                        }
                        .id(refreshToken)
                        .overlay(alignment: .topLeading) {
                            if uiTestModeEnabled && isSelecting {
                                Button("Select 2") {
                                    selectFirstTwoPhotosForUITest()
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 8)
                                .padding(.leading, 12)
                                .accessibilityIdentifier("photos.compare.selectTwoHook")
                            }
                        }

                        // Pasek akcji na dole (usuwanie + porownywanie)
                        if isSelecting && !selectedPhotos.isEmpty {
                            selectionActionBar
                                .padding(.bottom, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { toolbarContent }
            .onAppear {
                applyExternalFilterIfNeeded()
            }
            .onChange(of: photosFilterTag) { _, _ in
                applyExternalFilterIfNeeded()
            }
            .sheet(isPresented: $showAddPhoto) {
                AddPhotoView(onSaved: { refreshToken = UUID() })
                    .environmentObject(metricsStore)
            }
            .sheet(isPresented: $showFilters) {
                PhotoFilterView(filters: filters)
            }
            .sheet(isPresented: $showCompare) {
                let selectedArray = Array(selectedPhotos).sorted(by: { $0.date < $1.date })
                if selectedArray.count == 2 {
                    ComparePhotosView(
                        olderPhoto: selectedArray[0],
                        newerPhoto: selectedArray[1]
                    )
                }
            }
            .sheet(item: $selectedPhotoForDetail, onDismiss: {
                refreshToken = UUID()
            }) { photo in
                PhotoDetailView(photo: photo) {
                    selectedPhotos.remove(photo)
                    selectedPhotoForDetail = nil
                    refreshToken = UUID()
                }
                    .environmentObject(metricsStore)
            }
            .alert(
                AppLocalization.string("Delete Photos"),
                isPresented: $showDeleteConfirmation
            ) {
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Delete"), role: .destructive) {
                    performBatchDelete()
                }
            } message: {
                Text(AppLocalization.plural("photos.delete.confirmation", selectedPhotos.count))
            }
        }
        .preferredColorScheme(.dark)
    }
    
    func handlePhotoTap(_ photo: PhotoEntry) {
        guard isSelecting else {
            selectedPhotoForDetail = photo
            return
        }

        Haptics.selection()
        if selectedPhotos.contains(photo) {
            selectedPhotos.remove(photo)
        } else {
            selectedPhotos.insert(photo)
        }
    }

    func handlePhotoLongPress(_ photo: PhotoEntry) {
        guard !isSelecting else { return }
        Haptics.medium()
        withAnimation(.easeInOut(duration: 0.25)) {
            isSelecting = true
            selectedPhotos = [photo]
        }
    }
    
}

private extension PhotoView {

    var selectionActionBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(AppLocalization.string("Delete"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppDestructiveButtonStyle(size: .regular, cornerRadius: AppRadius.md))
            .accessibilityIdentifier("photos.batch.delete")
            .accessibilityLabel(AppLocalization.plural("photos.delete.count.a11y", selectedPhotos.count))

            if selectedPhotos.count == 2 {
                let canCompare = premiumStore.isPremium || uiTestModeEnabled

                Button {
                    if canCompare {
                        showCompare = true
                    } else {
                        Haptics.selection()
                        premiumStore.presentPaywall(reason: .feature("Photo Comparison Tool"))
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Label(AppLocalization.string("Compare"), systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)

                        if !canCompare {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(hex: "#FCA311"))
                                .padding(4)
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                .opacity(canCompare ? 1.0 : 0.55)
                .accessibilityIdentifier("photos.compare.open")
                .accessibilityLabel(canCompare
                    ? AppLocalization.string("Compare selected photos")
                    : AppLocalization.string("Compare selected photos — Premium required"))
                .accessibilityHint(canCompare
                    ? AppLocalization.string("accessibility.compare.opens")
                    : AppLocalization.string("Tap to unlock Photo Comparison with Premium"))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .appElevation(AppElevation.card)
    }

    private func performBatchDelete() {
        let photosToDelete = selectedPhotos
        do {
            try PhotoDeletionService.deletePhotos(photosToDelete, context: context)
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedPhotos.removeAll()
                isSelecting = false
            }
            refreshToken = UUID()
        } catch {
            Haptics.error()
            AppLog.debug("⚠️ Batch delete failed: \(error.localizedDescription)")
        }
    }

    private func applyExternalFilterIfNeeded() {
        guard !photosFilterTag.isEmpty,
              let tag = PhotoTag(rawValue: photosFilterTag) else {
            return
        }
        
        filters.dateRange = .all
        
        filters.selectedTags = [tag]
        showFilters = false
        photosFilterTag = ""
    }

    private func selectFirstTwoPhotosForUITest() {
        var descriptor = FetchDescriptor<PhotoEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        guard let latestTwo = try? context.fetch(descriptor), latestTwo.count == 2 else {
            return
        }
        selectedPhotos = Set(latestTwo)
    }
}

// MARK: - Widok zawartosci zdjec z Query
private struct PhotoContentView: View {
    @Environment(\.modelContext) private var context

    let filters: PhotoFilters
    let isSelecting: Bool
    @Binding var selectedPhotos: Set<PhotoEntry>
    let onPhotoTap: (PhotoEntry) -> Void
    let onPhotoLongPress: (PhotoEntry) -> Void
    let onAddPhoto: () -> Void
    let refreshToken: UUID

    @State private var photos: [PhotoEntry] = []
    @State private var isLoadingInitial: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var hasMore: Bool = true
    @State private var fetchOffset: Int = 0
    @State private var usesInMemoryTagFiltering: Bool = false
    
    private let pageSize: Int = 60
    
    private var filtersKey: String {
        let tags = filters.selectedTags
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return "\(filters.dateRange.rawValue)|\(filters.customStartDate.timeIntervalSince1970)|\(filters.customEndDate.timeIntervalSince1970)|\(tags)|\(refreshToken.uuidString)"
    }
    
    var body: some View {
        PhotoGridView(
            photos: photos,
            isSelecting: isSelecting,
            selectedPhotos: $selectedPhotos,
            onPhotoTap: onPhotoTap,
            onPhotoLongPress: onPhotoLongPress,
            onAddPhoto: onAddPhoto,
            isLoadingInitial: isLoadingInitial,
            isLoadingMore: isLoadingMore,
            hasMore: hasMore,
            loadMoreToken: fetchOffset,
            onLoadMore: loadMoreIfNeeded
        )
        .task(id: filtersKey) {
            await reload()
        }
    }
    
    @MainActor
    private func reload() async {
        isLoadingInitial = true
        isLoadingMore = false
        hasMore = true
        fetchOffset = 0
        photos = []
        
        await loadMoreUntilVisibleOrExhausted()
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
    }

    @MainActor
    private func loadMoreUntilVisibleOrExhausted() async {
        await loadMore()
        // Jesli filtrowanie tagow nie moze byc przeniesione do predykatu store (albo nie jest wspierane),
        // pierwsze strony moga miec 0 widocznych wynikow. Kontynuuj stronicowanie, az znajdziesz wynik albo dane sie skoncza.
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
            // Zapasowo: pobieranie tylko po dacie i filtrowanie w pamieci.
            if !usesInMemoryTagFiltering {
                usesInMemoryTagFiltering = true
                return await fetchNextBatch()
            }
            AppLog.debug("❌ Photo fetch failed: \(error)")
            return []
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
}

// MARK: - Photo Grid View (Reusable)
private struct PhotoGridView: View {
    let photos: [PhotoEntry]
    let isSelecting: Bool
    @Binding var selectedPhotos: Set<PhotoEntry>
    let onPhotoTap: (PhotoEntry) -> Void
    let onPhotoLongPress: (PhotoEntry) -> Void
    let onAddPhoto: () -> Void
    let isLoadingInitial: Bool
    let isLoadingMore: Bool
    let hasMore: Bool
    let loadMoreToken: Int
    let onLoadMore: () -> Void
    
    var body: some View {
        Group {
            if photos.isEmpty, !isLoadingInitial {
                emptyState
            } else {
                ScrollView {
                    photoGrid
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    if hasMore || isLoadingMore || isLoadingInitial {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .id(loadMoreToken)
                            .onAppear {
                                onLoadMore()
                            }
                    }
                }
            }
        }
    }
    
    var emptyState: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 20,
            tint: Color.cyan.opacity(0.12),
            contentPadding: 16
        ) {
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text(AppLocalization.string("No Photos Found"))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(AppLocalization.string("Try adjusting your filters or add a new photo"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                
                Button {
                    onAddPhoto()
                } label: {
                    Label(AppLocalization.string("Add Photo"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppAccentButtonStyle())
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
    }
    
    var photoGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
            spacing: 8
        ) {
            ForEach(Array(photos.enumerated()), id: \.element.persistentModelID) { index, photo in
                Button {
                    onPhotoTap(photo)
                } label: {
                    PhotoGridCell(
                        photo: photo,
                        isSelected: selectedPhotos.contains(photo),
                        isSelecting: isSelecting,
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
            }
        }
        .padding(.bottom, isSelecting && !selectedPhotos.isEmpty ? 80 : 0)
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


private extension PhotoView {

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSelecting = false
                        selectedPhotos.removeAll()
                    }
                } label: {
                    Text(AppLocalization.string("Done"))
                }
                .foregroundStyle(Color.appAccent)
                .accessibilityIdentifier("photos.selection.done")
            } else {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSelecting = true
                        selectedPhotos.removeAll()
                    }
                    if uiTestModeEnabled {
                        selectFirstTwoPhotosForUITest()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text(AppLocalization.string("Select"))
                    }
                }
                .foregroundStyle(Color.appAccent)
                .accessibilityIdentifier("photos.select.mode.toggle")
            }
        }

        if isSelecting {
            ToolbarItem(placement: .principal) {
                Text(AppLocalization.plural("photos.selected.count", selectedPhotos.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityLabel(AppLocalization.plural("photos.selected.count", selectedPhotos.count))
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                // Przycisk filtra z odznaka
                Button {
                    Haptics.selection()
                    showFilters = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(filters.isActive ? Color.appAccent : .primary)

                        if filters.isActive {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .accessibilityLabel(AppLocalization.string("Open photo filters"))

                if !isSelecting {
                    Button {
                        Haptics.light()
                        showAddPhoto = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("photos.add.button")
                    .accessibilityLabel(AppLocalization.string("Add photo"))
                }
            }
        }
    }

}
