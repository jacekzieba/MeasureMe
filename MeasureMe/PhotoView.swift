import SwiftUI
import SwiftData

/// Główny widok Photos w Tab Bar
/// Pokazuje zdjęcia w formie siatki (grid) z trybem selekcji i porównywania
/// Alternatywny widok listy znajduje się w PhotosListView (PhotosView.swift)
struct PhotoView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    
    @State private var filters = PhotoFilters()
    @State private var showFilters = false
    @State private var showAddPhoto = false
    @State private var showCompare = false
    @State private var refreshToken = UUID()

    @State private var isSelecting = false
    @State private var selectedPhotos: Set<PhotoEntry> = []
    @State private var selectedPhotoForDetail: PhotoEntry?
    @State private var showMaxPhotosAlert = false
    
    @AppStorage("photos_filter_tag") private var photosFilterTag: String = ""

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
                            onAddPhoto: {
                                Haptics.light()
                                showAddPhoto = true
                            },
                            refreshToken: refreshToken
                        )
                        
                        // Przycisk Compare jako overlay na dole
                        if isSelecting && selectedPhotos.count == 2 {
                            compareButton
                                .padding(.bottom, 20)
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
            .sheet(item: $selectedPhotoForDetail) { photo in
                PhotoDetailView(photo: photo)
                    .environmentObject(metricsStore)
            }
            .alert(AppLocalization.string("Maximum Photos Selected"), isPresented: $showMaxPhotosAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(AppLocalization.string("You can only compare two photos at a time. Please deselect one photo before selecting another."))
            }
        }
        .preferredColorScheme(.dark)
    }
    
    func handlePhotoTap(_ photo: PhotoEntry) {
        guard isSelecting else { 
            // Otwórz szczegółowy widok zdjęcia - delikatny feedback
            selectedPhotoForDetail = photo
            return 
        }

        if selectedPhotos.contains(photo) {
            selectedPhotos.remove(photo)
        } else if selectedPhotos.count < 2 {
            selectedPhotos.insert(photo)
        } else {
            showMaxPhotosAlert = true
        }
    }
    
}

private extension PhotoView {

    var compareButton: some View {
        Button {
            showCompare = true
        } label: {
            Label(AppLocalization.string("Compare"), systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppAccentButtonStyle(cornerRadius: 14))
        .accessibilityLabel(AppLocalization.string("Compare selected photos"))
        .accessibilityHint(AppLocalization.string("accessibility.compare.opens"))
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
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
}

// MARK: - Photo Content View with Query
private struct PhotoContentView: View {
    @Environment(\.modelContext) private var context

    let filters: PhotoFilters
    let isSelecting: Bool
    @Binding var selectedPhotos: Set<PhotoEntry>
    let onPhotoTap: (PhotoEntry) -> Void
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
        // If tag filtering can't be pushed into the store predicate (or is unsupported),
        // the first few pages may contain 0 visible results. Keep paging until we find something or exhaust.
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
            // Fallback to date-only fetch + in-memory filtering.
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
            ForEach(photos) { photo in
                Button {
                    onPhotoTap(photo)
                } label: {
                    PhotoGridCell(
                        photo: photo,
                        isSelected: selectedPhotos.contains(photo),
                        isSelecting: isSelecting
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("Photo"))
                .accessibilityValue(photo.date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding(.bottom, isSelecting && selectedPhotos.count == 2 ? 80 : 0)
    }
}


private extension PhotoView {

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            Button {
                if premiumStore.isPremium {
                    Haptics.selection()
                    isSelecting.toggle()
                    selectedPhotos.removeAll()
                } else {
                    premiumStore.presentPaywall(reason: .feature("Photo comparison"))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSelecting ? "xmark" : "checkmark.circle")
                    Text(AppLocalization.string("Compare"))
                }
            }
            .foregroundStyle(Color.appAccent)
            .accessibilityLabel(isSelecting
                ? AppLocalization.string("accessibility.compare.exit")
                : AppLocalization.string("accessibility.compare.enter"))
            .accessibilityHint(AppLocalization.string("accessibility.compare.select.two"))
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                // Filter button with badge
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
                
                Button {
                    Haptics.light()
                    showAddPhoto = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppLocalization.string("Add photo"))
            }
        }
    }

}
