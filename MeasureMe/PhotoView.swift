import SwiftUI
import SwiftData

/// Main Photos view in the Tab Bar
/// Displays photos in a grid with selection and comparison modes
/// An alternative list view is located in PhotosListView (PhotosView.swift)
struct PhotoView: View {
    private let photosTheme = FeatureTheme.photos

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore
    @EnvironmentObject private var router: AppRouter
    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)]) private var allPhotos: [PhotoEntry]
    
    @StateObject private var filters = PhotoFilters()
    @State private var showFilters = false
    @State private var showAddPhoto = false        // deep link / empty state
    @State private var showSourceChooserSheet = false
    @State private var showPendingLaunchSourceChooser = false
    @State private var didDismissPendingLaunchSourceChooser = false
    @State private var showCamera = false
    @State private var cameraPickerImage: UIImage? = nil
    @State private var showLibraryPicker = false   // PHPicker (1 and multiple)
    @State private var pendingLibrarySelection: MultiPhotoLibrarySelectionPayload? = nil
    @State private var singlePickerImage: UIImage? = nil
    @State private var singlePickerSource: PhotoLibraryImageSource? = nil
    @State private var multiPhotoImportPayload: MultiPhotoImportPayload? = nil
    @State private var showSingleImportFlow = false
    @State private var showMultiImportFlow = false
    @State private var compareChooserContext: CompareChooserContext?
    @State private var refreshToken = UUID()
    @State private var recentlySavedPhoto: PhotoEntry?
    @State private var recentlySavedPhotoEventID = UUID()

    @State private var isSelecting = false
    @State private var selectedPhotos: Set<PhotoEntry> = []
    @State private var selectedPhotoForDetail: PhotoEntry?
    @State private var selectedComparePair: PhotoComparePair?
    @State private var heroCompareOverride: TemporaryHeroPairOverride?
    @State private var showDeleteConfirmation = false
    @State private var didRunUITestAutoOpen = false
    @State private var failureToastMessage: String?
    @State private var showsFailureToast = false
    @State private var pickerDismissedAt: ContinuousClock.Instant?
    @State private var photoBatchByPersistentID: [String: UUID] = [:]
    
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.experience.photosFilterTag) private var photosFilterTag: String = ""
    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var uiTestModeEnabled: Bool {
        UITestArgument.isPresent(.mode)
    }

    private var shouldShowPendingLaunchSourceChooser: Bool {
        #if DEBUG
        if uiTestShouldOpenPendingAddPhotoChooser && !didDismissPendingLaunchSourceChooser {
            return true
        }
        #endif
        return showPendingLaunchSourceChooser
    }

    private var canUsePremiumCompare: Bool {
        premiumStore.isPremium || uiTestModeEnabled
    }

    private let heroCompareOverrideLifetime: TimeInterval = 30 * 60

    #if DEBUG
    /// Number of photos to open in MultiPhotoImportView during a UI test.
    /// Activated by launch argument: -uiTestOpenMultiImport {count}
    private var uiTestMultiImportCount: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let raw = UITestArgument.value(for: .openMultiImport, in: args),
              let count = Int(raw),
              count > 0 else { return nil }
        return count
    }

    /// Opens AddPhotoView with a generated test image.
    /// Activated by launch argument: -uiTestOpenSingleAdd
    private var uiTestShouldOpenSingleAdd: Bool {
        UITestArgument.isPresent(.openSingleAdd)
    }

    private var uiTestShouldOpenPendingAddPhotoChooser: Bool {
        UITestArgument.value(for: .pendingAppEntryAction) == AppEntryAction.openAddPhoto.rawValue
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(
                    topHeight: 380,
                    tint: photosTheme.softTint
                )
                
                ZStack(alignment: .bottom) {
                    PhotoContentView(
                        filters: filters,
                        isPremium: premiumStore.isPremium || uiTestModeEnabled,
                        isSelecting: isSelecting,
                        selectedPhotos: $selectedPhotos,
                        onPhotoTap: handlePhotoTap,
                        onPhotoLongPress: handlePhotoLongPress,
                        onAddPhoto: handleAddPhotoTap,
                        onOpenCompareChooser: handleOpenCompareChooserTap,
                        onChooseHeroSlot: handleChooseHeroSlot,
                        onOpenSuggestedCompare: handleOpenSuggestedCompare,
                        heroCompareOverride: heroCompareOverride,
                        refreshToken: refreshToken,
                        recentlySavedPhoto: recentlySavedPhoto,
                        recentlySavedPhotoEventID: recentlySavedPhotoEventID,
                        pendingItems: pendingPhotoSaveStore.pendingItems
                    )
                    .refreshable {
                        refreshPhotoContent()
                    }
                    .overlay(alignment: .top) {
                        if showsFailureToast, let failureToastMessage {
                            InlineErrorBanner(
                                message: failureToastMessage,
                                accessibilityIdentifier: "photos.pending.failureToast"
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if uiTestModeEnabled && isSelecting {
                            Button("Select 2", action: selectFirstTwoPhotosForUITest)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(photosTheme.pillFill, in: Capsule())
                            .padding(.top, 8)
                            .padding(.leading, 12)
                            .accessibilityIdentifier("photos.compare.selectTwoHook")
                        }
                    }
                    .overlay {
                        if shouldShowPendingLaunchSourceChooser {
                            ZStack(alignment: .bottom) {
                                Color.black.opacity(0.18)
                                    .ignoresSafeArea()

                                sourceChooserSheet
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 240)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 12)
                            }
                            .transition(.opacity)
                        }
                    }

                    // Action bar at the bottom (delete + compare)
                    if isSelecting && !selectedPhotos.isEmpty {
                        selectionActionBar
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .onAppear {
                handlePhotoViewAppear()
            }
            .onChange(of: router.photoComposerRequestID) { _, _ in
                handlePhotoComposerRequestChange()
            }
            .task(id: heroCompareOverride?.id) {
                await scheduleHeroCompareOverrideReset()
            }
            .onChange(of: photosFilterTag) { _, _ in
                handlePhotosFilterTagChange()
            }
            .onChange(of: pendingPhotoSaveStore.completedEvent?.eventID) { _, _ in
                handlePendingPhotoCompletedEventChange()
            }
            .onChange(of: pendingPhotoSaveStore.lastFailureMessage) { _, newValue in
                handlePendingPhotoFailure(newValue)
            }
            // Deep link / empty state — opens AddPhotoView without a photo
            .sheet(isPresented: $showAddPhoto) {
                NavigationStack {
                    AddPhotoView()
                        .environmentObject(metricsStore)
                }
            }
            // Camera → AddPhotoView with preview (onDismiss after dismiss, which follows onSelect)
            .sheet(isPresented: $showCamera, onDismiss: {
                if let img = cameraPickerImage {
                    presentSingleImport(images: [img])
                    cameraPickerImage = nil
                }
            }) {
                CameraPickerView(selectedImage: $cameraPickerImage)
            }
            // PHPicker (1 and multiple) — routing based on the number of selected photos.
            .sheet(isPresented: $showLibraryPicker, onDismiss: {
                pickerDismissedAt = ContinuousClock.now
                routePendingLibrarySelection()
            }) {
                MultiPhotoLibraryPicker { selection in
                    pendingLibrarySelection = selection
                }
            }
            // Import flow after selecting photos from the library is launched as a push in NavigationStack,
            // which eliminates "sheet-on-sheet" and provides a smoother transition after PHPicker dismiss.
            .navigationDestination(isPresented: $showSingleImportFlow) {
                if singlePickerImage != nil || singlePickerSource != nil {
                    AddPhotoView(previewImage: singlePickerImage, previewSource: singlePickerSource)
                        .environmentObject(metricsStore)
                } else {
                    EmptyView()
                }
            }
            .navigationDestination(isPresented: $showMultiImportFlow) {
                if let payload = multiPhotoImportPayload {
                    MultiPhotoImportView(payload: payload)
                        .environmentObject(metricsStore)
                } else {
                    EmptyView()
                }
            }
            .sheet(isPresented: $showSourceChooserSheet) {
                sourceChooserSheet
                    .presentationDetents([.height(240)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showFilters) {
                PhotoFilterView(filters: filters)
            }
            .sheet(item: $compareChooserContext) { context in
                HomeCompareChooserSheet(
                    photos: allPhotos,
                    initialOlderPhoto: context.olderPhoto,
                    initialNewerPhoto: context.newerPhoto,
                    preferredSlot: context.preferredSlot,
                    onSelectionChanged: handleCompareChooserSelectionChange
                ) { olderPhoto, newerPhoto in
                    openCompare(using: olderPhoto, newerPhoto)
                }
            }
            .sheet(item: $selectedComparePair) { pair in
                ComparePhotosView(
                    olderPhoto: pair.olderPhoto,
                    newerPhoto: pair.newerPhoto
                )
            }
            .sheet(item: $selectedPhotoForDetail, onDismiss: {
                refreshPhotoContent()
            }) { photo in
                PhotoDetailView(photo: photo, onCompareRequested: handlePhotoDetailCompareRequest) {
                    handlePhotoDeletedFromDetail(photo)
                }
                    .environmentObject(metricsStore)
            }
            .alert(
                AppLocalization.string("Delete Photos"),
                isPresented: $showDeleteConfirmation
            ) {
                Button(AppLocalization.string("Cancel"), role: .cancel) { }
                Button(AppLocalization.string("Delete"), role: .destructive, action: performBatchDelete)
            } message: {
                Text(AppLocalization.plural("photos.delete.confirmation", selectedPhotos.count))
            }
        }
    }

    private func consumePendingPhotoComposerRequestIfNeeded() {
        guard let requestID = router.photoComposerRequestID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard router.photoComposerRequestID == requestID else { return }
            presentPendingPhotoComposerChooser()
            router.consumePhotoComposerRequest(requestID)
        }
    }

    @MainActor
    private func presentPendingPhotoComposerChooser() {
        if uiTestModeEnabled && UITestArgument.value(for: .pendingAppEntryAction) == AppEntryAction.openAddPhoto.rawValue {
            showPendingLaunchSourceChooser = true
            showSourceChooserSheet = false
            return
        }

        showPendingLaunchSourceChooser = false
        showSourceChooserSheet = true
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
        Haptics.trigger(.confirmSoft)
        withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
            isSelecting = true
            selectedPhotos = [photo]
        }
    }

    func openCompare(using olderPhoto: PhotoEntry, _ newerPhoto: PhotoEntry) {
        let sorted = [olderPhoto, newerPhoto].sorted { $0.date < $1.date }
        guard sorted.count == 2 else { return }
        selectedComparePair = PhotoComparePair(olderPhoto: sorted[0], newerPhoto: sorted[1])
    }

    private func refreshPhotoContent() {
        refreshToken = UUID()
    }

    private func handlePhotoViewAppear() {
        applyExternalFilterIfNeeded()
        consumePendingPhotoComposerRequestIfNeeded()
        #if DEBUG
        openUITestImportHookIfNeeded()
        #endif
    }

    private func handlePhotoComposerRequestChange() {
        consumePendingPhotoComposerRequestIfNeeded()
    }

    private func handlePhotosFilterTagChange() {
        applyExternalFilterIfNeeded()
    }

    private func handlePendingPhotoCompletedEventChange() {
        handlePendingPhotoCompletedEvent()
    }

    private func handleAddPhotoTap() {
        Haptics.light()
        showSourceChooserSheet = true
    }

    private func handleOpenCompareChooserTap() {
        Haptics.light()
        guard canUsePremiumCompare else {
            premiumStore.presentPaywall(reason: .feature("Photo Comparison Tool"))
            return
        }
        compareChooserContext = CompareChooserContext(
            olderPhoto: nil,
            newerPhoto: nil,
            preferredSlot: .newer
        )
    }

    private func handleChooseHeroSlot(_ pair: PhotoComparePairSuggestion, _ slot: CompareChooserSlot) {
        Haptics.light()
        guard canUsePremiumCompare else {
            premiumStore.presentPaywall(reason: .feature("Photo Comparison Tool"))
            return
        }
        compareChooserContext = CompareChooserContext(
            olderPhoto: pair.older,
            newerPhoto: pair.newer,
            preferredSlot: slot
        )
    }

    private func handleOpenSuggestedCompare(_ pair: PhotoComparePairSuggestion) {
        guard canUsePremiumCompare else {
            premiumStore.presentPaywall(reason: .feature("Photo Comparison Tool"))
            return
        }
        openCompare(using: pair.older, pair.newer)
    }

    private func handleCompareChooserSelectionChange(_ olderPhoto: PhotoEntry, _ newerPhoto: PhotoEntry) {
        heroCompareOverride = TemporaryHeroPairOverride(
            pair: PhotoComparePair(olderPhoto: olderPhoto, newerPhoto: newerPhoto),
            expiresAt: AppClock.now.addingTimeInterval(heroCompareOverrideLifetime)
        )
    }

    private func handlePhotoDetailCompareRequest(_ olderPhoto: PhotoEntry, _ newerPhoto: PhotoEntry) {
        selectedPhotoForDetail = nil
        openCompare(using: olderPhoto, newerPhoto)
    }

    private func handlePhotoDeletedFromDetail(_ photo: PhotoEntry) {
        selectedPhotos.remove(photo)
        selectedPhotoForDetail = nil
        refreshPhotoContent()
    }
    
}

private struct PhotoComparePair: Identifiable {
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    var id: String {
        "\(olderPhoto.persistentModelID)_\(newerPhoto.persistentModelID)"
    }
}

private struct TemporaryHeroPairOverride: Identifiable {
    let pair: PhotoComparePair
    let expiresAt: Date

    var id: String {
        "\(pair.id)_\(expiresAt.timeIntervalSince1970)"
    }

    var isActive: Bool {
        expiresAt > AppClock.now
    }
}

private struct CompareChooserContext: Identifiable {
    let olderPhoto: PhotoEntry?
    let newerPhoto: PhotoEntry?
    let preferredSlot: CompareChooserSlot

    var id: String {
        let olderID = olderPhoto.map { String(describing: $0.persistentModelID) } ?? "nil"
        let newerID = newerPhoto.map { String(describing: $0.persistentModelID) } ?? "nil"
        return "\(preferredSlot)_\(olderID)_\(newerID)"
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
                        let selectedArray = Array(selectedPhotos).sorted(by: { $0.date < $1.date })
                        if selectedArray.count == 2 {
                            openCompare(using: selectedArray[0], selectedArray[1])
                        }
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
        let selectedPersistentIDs = Set(photosToDelete.map(\.persistentModelID))
        let selectedPhotoIDs = Set(photosToDelete.map(singlePhotoSaveID(for:)))
        let batchIDsToCancel = Set(selectedPhotoIDs.compactMap { photoBatchByPersistentID[$0] })

        do {
            if !batchIDsToCancel.isEmpty {
                pendingPhotoSaveStore.cancelPending(batchIDs: batchIDsToCancel)
            }
            try PhotoDeletionService.deletePhotos(
                withPersistentModelIDs: selectedPersistentIDs,
                context: context
            )
            Haptics.success()
            withAnimation(AppMotion.animation(AppMotion.sectionExit, enabled: shouldAnimate)) {
                selectedPhotos.removeAll()
                isSelecting = false
            }
            for id in selectedPhotoIDs {
                photoBatchByPersistentID.removeValue(forKey: id)
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

    private func routePendingLibrarySelection() {
        guard let selection = pendingLibrarySelection else { return }
        pendingLibrarySelection = nil

        let sources = selection.sources.sorted(by: { $0.selectionIndex < $1.selectionIndex })
        guard !sources.isEmpty else { return }

        if sources.count == 1, let first = sources.first {
            presentSingleImport(source: first)
        } else {
            presentMultiImport(payload: MultiPhotoImportPayload(librarySources: sources))
        }

        if let dismissedAt = pickerDismissedAt {
            let elapsed = dismissedAt.duration(to: .now)
            let dismissToImportMs = Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            AppLog.debug("📸 PhotoView: pickerDismissToImportVisibleMs=\(dismissToImportMs) count=\(sources.count)")
        }
        pickerDismissedAt = nil
    }

    private func presentSingleImport(images: [UIImage]) {
        multiPhotoImportPayload = nil
        showMultiImportFlow = false
        singlePickerImage = images.first
        singlePickerSource = nil
        showSingleImportFlow = true
    }

    private func presentMultiImport(images: [UIImage]) {
        presentMultiImport(payload: MultiPhotoImportPayload(images: images))
    }

    private func presentSingleImport(source: PhotoLibraryImageSource) {
        multiPhotoImportPayload = nil
        showMultiImportFlow = false
        singlePickerImage = nil
        singlePickerSource = source
        showSingleImportFlow = true
    }

    private func presentMultiImport(payload: MultiPhotoImportPayload) {
        singlePickerImage = nil
        singlePickerSource = nil
        showSingleImportFlow = false
        multiPhotoImportPayload = payload
        showMultiImportFlow = true
    }

    private func handlePendingPhotoCompletedEvent() {
        guard let completed = pendingPhotoSaveStore.completedEvent else { return }
        guard let resolved = context.model(for: completed.entryPersistentModelID) as? PhotoEntry else {
            refreshToken = UUID()
            AppLog.debug("⚠️ PhotoView: completed photo not resolvable in main context, fallback refresh")
            return
        }

        if let batchID = completed.batchID {
            photoBatchByPersistentID[singlePhotoSaveID(for: resolved)] = batchID
        }

        recentlySavedPhoto = resolved
        recentlySavedPhotoEventID = completed.eventID
    }

    private func handlePendingPhotoFailure(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        failureToastMessage = message
        withAnimation(AppMotion.toastIn) {
            showsFailureToast = true
        }
        pendingPhotoSaveStore.clearFailureMessage()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            withAnimation(AppMotion.toastOut) {
                showsFailureToast = false
            }
            try? await Task.sleep(for: .milliseconds(220))
            if !showsFailureToast {
                failureToastMessage = nil
            }
        }
    }

    @MainActor
    private func scheduleHeroCompareOverrideReset() async {
        guard let heroCompareOverride else { return }
        guard heroCompareOverride.isActive else {
            self.heroCompareOverride = nil
            return
        }

        let delay = heroCompareOverride.expiresAt.timeIntervalSince(AppClock.now)
        guard delay > 0 else {
            self.heroCompareOverride = nil
            return
        }

        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }

        if self.heroCompareOverride?.id == heroCompareOverride.id {
            self.heroCompareOverride = nil
        }
    }

    #if DEBUG
    /// Opens the appropriate photo import flow for UI tests.
    private func openUITestImportHookIfNeeded() {
        guard !didRunUITestAutoOpen else { return }
        if uiTestShouldOpenPendingAddPhotoChooser {
            didRunUITestAutoOpen = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                presentPendingPhotoComposerChooser()
            }
            return
        }
        if uiTestShouldOpenSingleAdd {
            didRunUITestAutoOpen = true
            openSingleAddForUITest()
            return
        }
        if let count = uiTestMultiImportCount {
            didRunUITestAutoOpen = true
            openMultiImportForUITest(count: count)
        }
    }

    /// Opens AddPhotoView with a generated test image.
    private func openSingleAddForUITest() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 533))
        let image = renderer.image { ctx in
            UIColor(red: 0.12, green: 0.72, blue: 0.78, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 533))
            let label = "UI TEST SINGLE" as NSString
            label.draw(at: CGPoint(x: 16, y: 16), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: UIColor.white
            ])
        }
        presentSingleImport(images: [image])
    }

    /// Opens MultiPhotoImportView with generated test images.
    /// Activated by launch argument: -uiTestOpenMultiImport {count}
    private func openMultiImportForUITest(count: Int) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 533))
        let images = (0..<count).map { i -> UIImage in
            renderer.image { ctx in
                UIColor(hue: CGFloat(i) / CGFloat(max(count, 1)), saturation: 0.6, brightness: 0.85, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 533))
                let label = "UI TEST \(i + 1)" as NSString
                label.draw(at: CGPoint(x: 16, y: 16), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 28),
                    .foregroundColor: UIColor.white
                ])
            }
        }
        presentMultiImport(images: images)
    }
    #endif

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

struct SinglePhotoSaveMergeResult {
    let photos: [PhotoEntry]
    let fetchOffset: Int
    let didUpdateList: Bool
}

struct SinglePhotoSaveMergeItem {
    let id: String
    let date: Date
}

struct SinglePhotoSaveMergePlan {
    let orderedIDs: [String]
    let fetchOffset: Int
    let didUpdateList: Bool
}

struct PhotoFeedMergeItem {
    let id: String
    let date: Date
}

enum PhotoFeedMergePlanner {
    static func orderedIDs(
        persisted: [PhotoFeedMergeItem],
        pending: [PhotoFeedMergeItem],
        limit: Int? = nil
    ) -> [String] {
        var combined = pending + persisted
        combined.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id < rhs.id }
            return lhs.date > rhs.date
        }

        var seen: Set<String> = []
        var ordered: [String] = []
        for item in combined where seen.insert(item.id).inserted {
            ordered.append(item.id)
        }

        if let limit {
            return Array(ordered.prefix(limit))
        }
        return ordered
    }
}

enum SinglePhotoSaveMergePlanner {

    static func apply(
        recentlySavedItem: SinglePhotoSaveMergeItem?,
        matchesFilter: Bool,
        items: [SinglePhotoSaveMergeItem],
        hasMore: Bool,
        pageSize: Int,
        fetchOffset: Int
    ) -> SinglePhotoSaveMergePlan {
        guard let recentlySavedItem, matchesFilter else {
            return SinglePhotoSaveMergePlan(
                orderedIDs: items.map(\.id),
                fetchOffset: fetchOffset,
                didUpdateList: false
            )
        }

        let originalItems = items
        var updatedItems = items
        let removedExisting = updatedItems.removeAllAndReturnCount { $0.id == recentlySavedItem.id } > 0
        let insertIndex = updatedItems.firstIndex(where: { $0.date < recentlySavedItem.date }) ?? updatedItems.count

        if !removedExisting,
           hasMore,
           originalItems.count >= pageSize,
           insertIndex >= pageSize {
            return SinglePhotoSaveMergePlan(
                orderedIDs: originalItems.map(\.id),
                fetchOffset: fetchOffset,
                didUpdateList: false
            )
        }

        updatedItems.insert(recentlySavedItem, at: insertIndex)

        if !removedExisting, hasMore, updatedItems.count > pageSize {
            updatedItems.removeLast()
        }

        var updatedOffset = fetchOffset
        if !removedExisting, hasMore {
            updatedOffset += 1
        }

        return SinglePhotoSaveMergePlan(
            orderedIDs: updatedItems.map(\.id),
            fetchOffset: updatedOffset,
            didUpdateList: true
        )
    }
}

enum SinglePhotoSaveMergeEngine {

    static func apply(
        recentlySavedPhoto: PhotoEntry?,
        filters: PhotoFilters,
        photos: [PhotoEntry],
        hasMore: Bool,
        pageSize: Int,
        fetchOffset: Int
    ) -> SinglePhotoSaveMergeResult {
        guard let recentlySavedPhoto else {
            return SinglePhotoSaveMergeResult(
                photos: photos,
                fetchOffset: fetchOffset,
                didUpdateList: false
            )
        }

        let recentlySavedID = singlePhotoSaveID(for: recentlySavedPhoto)
        let items = photos.map { photo in
            SinglePhotoSaveMergeItem(id: singlePhotoSaveID(for: photo), date: photo.date)
        }
        let plan = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: SinglePhotoSaveMergeItem(id: recentlySavedID, date: recentlySavedPhoto.date),
            matchesFilter: filters.matches(recentlySavedPhoto),
            items: items,
            hasMore: hasMore,
            pageSize: pageSize,
            fetchOffset: fetchOffset
        )

        guard plan.didUpdateList else {
            return SinglePhotoSaveMergeResult(
                photos: photos,
                fetchOffset: plan.fetchOffset,
                didUpdateList: false
            )
        }

        var photosByID: [String: PhotoEntry] = [:]
        for photo in photos {
            let id = singlePhotoSaveID(for: photo)
            if photosByID[id] == nil {
                photosByID[id] = photo
            }
        }
        photosByID[recentlySavedID] = recentlySavedPhoto
        let rebuiltPhotos = plan.orderedIDs.compactMap { photosByID[$0] }

        return SinglePhotoSaveMergeResult(photos: rebuiltPhotos, fetchOffset: plan.fetchOffset, didUpdateList: true)
    }
}

private extension Array {
    mutating func removeAllAndReturnCount(where shouldBeRemoved: (Element) throws -> Bool) rethrows -> Int {
        let before = count
        try removeAll(where: shouldBeRemoved)
        return before - count
    }
}

private func singlePhotoSaveID(for photo: PhotoEntry) -> String {
    String(describing: photo.persistentModelID)
}

// MARK: - Photo content view with Query
private struct PhotoContentView: View {
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
    }
}

private enum PhotoGridRenderItem: Identifiable {
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

// MARK: - Photo Grid View (Reusable)
private struct PhotoGridView: View {
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

                AppGlassCard(
                    depth: .elevated,
                    cornerRadius: 20,
                    tint: photosTheme.softTint,
                    contentPadding: 16
                ) {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text(filtersActive && hasAnySavedPhotos ? AppLocalization.string("No Photos Found") : AppLocalization.string("Photo Progress"))
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(filtersActive && hasAnySavedPhotos
                             ? AppLocalization.string("Try adjusting your filters or add a new photo")
                             : AppLocalization.string("Photos make progress easier to notice."))
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
            }

            photoGrid
        }
    }

    private var photoGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
            spacing: 8
        ) {
            ForEach(Array(archiveItems.enumerated()), id: \.element.id) { index, item in
                switch item {
                case .persisted(let photo):
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
                case .pending(let pending):
                    PendingPhotoGridCell(
                        thumbnailData: pending.thumbnailData,
                        progress: pending.progress,
                        status: pending.status,
                        targetSize: CGSize(width: 110, height: 120),
                        cornerRadius: 12,
                        cacheID: pending.id.uuidString,
                        accessibilityIdentifier: "photos.grid.pending.item"
                    )
                    .frame(width: 110, height: 120)
                }
            }
        }
        .padding(.bottom, isSelecting && !selectedPhotos.isEmpty ? 80 : 0)
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

private struct PhotoGridHeroSkeleton: View {
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


private extension PhotoView {

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button {
                    Haptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.sectionExit, enabled: shouldAnimate)) {
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
                    withAnimation(AppMotion.animation(AppMotion.sectionEnter, enabled: shouldAnimate)) {
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

                if !isSelecting {
                    Menu {
                        Button {
                            openCameraFlow(fromSourceChooserSheet: false)
                        } label: {
                            Label(AppLocalization.string("Take Photo"), systemImage: "camera.fill")
                        }
                        .accessibilityIdentifier("photos.add.menu.camera")

                        Button {
                            openLibraryFlow(fromSourceChooserSheet: false)
                        } label: {
                            Label(AppLocalization.string("Choose from Library"), systemImage: "photo.on.rectangle")
                        }
                        .accessibilityIdentifier("photos.add.menu.library")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("photos.add.button")
                    .accessibilityLabel(AppLocalization.string("Add photo"))
                }
            }
        }
    }

    private var sourceChooserSheet: some View {
        VStack(spacing: 0) {
            // Handle indicator space
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Text(AppLocalization.string("Add Photo"))
                .font(AppTypography.displaySection)
                .foregroundStyle(AppColorRoles.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Button {
                openCameraFlow(fromSourceChooserSheet: true)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(photosTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(photosTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.string("Take Photo"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(AppLocalization.string("photos.add.camera.subtitle"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photos.add.menu.camera")

            Divider().padding(.leading, 78)

            Button {
                openLibraryFlow(fromSourceChooserSheet: true)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                        .foregroundStyle(photosTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(photosTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.string("Choose from Library"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(AppLocalization.string("photos.add.library.subtitle"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photos.add.menu.library")

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("photos.sourceChooser.visible")
    }

    private func openCameraFlow(fromSourceChooserSheet: Bool) {
        Haptics.light()
        if fromSourceChooserSheet {
            showSourceChooserSheet = false
            showPendingLaunchSourceChooser = false
            didDismissPendingLaunchSourceChooser = true
            DispatchQueue.main.async {
                showCamera = true
            }
        } else {
            showCamera = true
        }
    }

    private func openLibraryFlow(fromSourceChooserSheet: Bool) {
        Haptics.light()
        if fromSourceChooserSheet {
            showSourceChooserSheet = false
            showPendingLaunchSourceChooser = false
            didDismissPendingLaunchSourceChooser = true
            DispatchQueue.main.async {
                showLibraryPicker = true
            }
        } else {
            showLibraryPicker = true
        }
    }

}
