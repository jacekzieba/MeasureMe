import SwiftUI
import SwiftData
import UIKit

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
    @ObservedObject private var photoPrivacyGate = PhotoPrivacyGate.shared
    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)]) private var allPhotos: [PhotoEntry]

    @StateObject private var filters = PhotoFilters()
    @StateObject private var viewModel = PhotoViewModel()

    // Bindings kept in View (used directly as modifier bindings)
    @State private var showFilters = false
    @State private var showAddPhoto = false        // deep link / empty state
    @State private var showSourceChooserSheet = false
    @State private var showCamera = false
    @State private var cameraPickerImage: UIImage? = nil
    @State private var capturedImportImage: UIImage? = nil
    @State private var showCapturedImportSheet = false
    @State private var showLibraryPicker = false   // PHPicker (1 and multiple)
    @State private var showSingleImportFlow = false
    @State private var showMultiImportFlow = false
    @State private var compareChooserContext: CompareChooserContext?
    @State private var selectedPhotos: Set<PhotoEntry> = []
    @State private var selectedPhotoForDetail: PhotoEntry?
    @State private var selectedComparePair: PhotoComparePair?
    @State private var showDeleteConfirmation = false

    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.experience.photosFilterTag) private var photosFilterTag: String = ""
    @AppSetting(\.privacy.requireBiometricForPhotos) private var requireBiometricForPhotos: Bool = false
    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var uiTestModeEnabled: Bool {
        UITestArgument.isPresent(.mode)
    }

    private var canDisplayPhotos: Bool {
        photoPrivacyGate.canDisplayPhotos(requireBiometric: requireBiometricForPhotos)
    }

    private var shouldShowPendingLaunchSourceChooser: Bool {
        #if DEBUG
        if uiTestShouldOpenPendingAddPhotoChooser && !viewModel.didDismissPendingLaunchSourceChooser {
            return true
        }
        #endif
        return viewModel.showPendingLaunchSourceChooser
    }

    private var shouldShowInlineSourceChooser: Bool {
        shouldShowPendingLaunchSourceChooser || viewModel.showUITestSourceChooserOverlay
    }

    private var sourceChooserSheetBinding: Binding<Bool> {
        Binding(
            get: { showSourceChooserSheet && !uiTestModeEnabled },
            set: { showSourceChooserSheet = $0 }
        )
    }

    private var canUsePremiumCompare: Bool {
        true
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
                        isSelecting: viewModel.isSelecting,
                        selectedPhotos: $selectedPhotos,
                        onPhotoTap: handlePhotoTap,
                        onPhotoLongPress: handlePhotoLongPress,
                        onAddPhoto: handleAddPhotoTap,
                        onOpenCompareChooser: handleOpenCompareChooserTap,
                        onChooseHeroSlot: handleChooseHeroSlot,
                        onOpenSuggestedCompare: handleOpenSuggestedCompare,
                        heroCompareOverride: viewModel.heroCompareOverride,
                        refreshToken: viewModel.refreshToken,
                        recentlySavedPhoto: viewModel.recentlySavedPhoto,
                        recentlySavedPhotoEventID: viewModel.recentlySavedPhotoEventID,
                        pendingItems: pendingPhotoSaveStore.pendingItems
                    )
                    .blur(radius: canDisplayPhotos ? 0 : 18)
                    .allowsHitTesting(canDisplayPhotos)
                    .overlay {
                        if !canDisplayPhotos {
                            PhotoPrivacyLockedView {
                                Task { await photoPrivacyGate.unlock() }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .refreshable {
                        refreshPhotoContent()
                    }
                    .overlay(alignment: .top) {
                        if viewModel.showsFailureToast, let failureToastMessage = viewModel.failureToastMessage {
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
                        if uiTestModeEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                if viewModel.isSelecting {
                                    Button("Select 2", action: selectFirstTwoPhotosForUITest)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(photosTheme.pillFill, in: Capsule())
                                        .accessibilityIdentifier("photos.compare.selectTwoHook")
                                }

                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .accessibilityIdentifier("photos.sourceChooser.visible")

                                Button("Take Photo") {}
                                    .buttonStyle(.plain)
                                    .frame(width: 1, height: 1)
                                    .clipped()
                                    .accessibilityIdentifier("photos.add.menu.camera")

                                Button("Choose from Library") {}
                                    .buttonStyle(.plain)
                                    .frame(width: 1, height: 1)
                                    .clipped()
                                    .accessibilityIdentifier("photos.add.menu.library")
                            }
                            .padding(.top, 8)
                            .padding(.leading, 12)
                        }
                    }
                    .overlay {
                        if shouldShowInlineSourceChooser {
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
                    if viewModel.isSelecting && !selectedPhotos.isEmpty {
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
            .task(id: viewModel.heroCompareOverride?.id) {
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                photoPrivacyGate.lock()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                photoPrivacyGate.lock()
            }
            // Deep link / empty state — opens AddPhotoView without a photo
            .sheet(isPresented: $showAddPhoto) {
                NavigationStack {
                    AddPhotoView(telemetrySource: .photos)
                        .environmentObject(metricsStore)
                }
            }
            // Camera → AddPhotoView with preview (onDismiss after dismiss, which follows onSelect)
            .sheet(isPresented: $showCamera, onDismiss: {
                if let img = cameraPickerImage {
                    capturedImportImage = img
                    showCapturedImportSheet = true
                    cameraPickerImage = nil
                }
            }) {
                if UIImagePickerController.isSourceTypeAvailable(.camera), !uiTestModeEnabled {
                    GuidedCameraView(
                        selectedImage: $cameraPickerImage,
                        overlayImageData: allPhotos.first?.thumbnailOrImageData
                    )
                } else {
                    CameraPickerView(selectedImage: $cameraPickerImage)
                }
            }
            .sheet(isPresented: $showCapturedImportSheet, onDismiss: {
                capturedImportImage = nil
            }) {
                NavigationStack {
                    AddPhotoView(previewImage: capturedImportImage, telemetrySource: .photos)
                        .environmentObject(metricsStore)
                }
            }
            // PHPicker (1 and multiple) — routing based on the number of selected photos.
            .sheet(isPresented: $showLibraryPicker, onDismiss: {
                viewModel.pickerDismissedAt = ContinuousClock.now
                routePendingLibrarySelection()
            }) {
                MultiPhotoLibraryPicker { selection in
                    viewModel.pendingLibrarySelection = selection
                }
            }
            // Import flow after selecting photos from the library is launched as a push in NavigationStack,
            // which eliminates "sheet-on-sheet" and provides a smoother transition after PHPicker dismiss.
            .navigationDestination(isPresented: $showSingleImportFlow) {
                if viewModel.singlePickerImage != nil || viewModel.singlePickerSource != nil {
                    AddPhotoView(
                        previewImage: viewModel.singlePickerImage,
                        previewSource: viewModel.singlePickerSource,
                        telemetrySource: .photos
                    )
                        .environmentObject(metricsStore)
                } else {
                    EmptyView()
                }
            }
            .navigationDestination(isPresented: $showMultiImportFlow) {
                if let payload = viewModel.multiPhotoImportPayload {
                    MultiPhotoImportView(payload: payload)
                        .environmentObject(metricsStore)
                } else {
                    EmptyView()
                }
            }
            .sheet(isPresented: sourceChooserSheetBinding) {
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
                .onDisappear {
                    selectedComparePair = nil
                }
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
            viewModel.showPendingLaunchSourceChooser = true
            showSourceChooserSheet = false
            return
        }

        viewModel.showPendingLaunchSourceChooser = false
        showSourceChooserSheet = true
    }

    func handlePhotoTap(_ photo: PhotoEntry) {
        guard viewModel.isSelecting else {
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
        guard !viewModel.isSelecting else { return }
        Haptics.trigger(.confirmSoft)
        withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
            viewModel.isSelecting = true
            selectedPhotos = [photo]
        }
    }

    func openCompare(using olderPhoto: PhotoEntry, _ newerPhoto: PhotoEntry) {
        guard premiumStore.isPremium else {
            premiumStore.presentPaywall(reason: .photoComparison)
            return
        }
        let sorted = [olderPhoto, newerPhoto].sorted { $0.date < $1.date }
        guard sorted.count == 2 else { return }
        selectedComparePair = nil
        Task { @MainActor in
            await Task.yield()
            selectedComparePair = PhotoComparePair(olderPhoto: sorted[0], newerPhoto: sorted[1])
        }
    }

    private func refreshPhotoContent() {
        viewModel.refreshToken = UUID()
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
        if uiTestModeEnabled {
            viewModel.showUITestSourceChooserOverlay = true
            return
        }
        showSourceChooserSheet = true
    }

    private func handleOpenCompareChooserTap() {
        Haptics.light()
        compareChooserContext = CompareChooserContext(
            olderPhoto: nil,
            newerPhoto: nil,
            preferredSlot: .newer
        )
    }

    private func handleChooseHeroSlot(_ pair: PhotoComparePairSuggestion, _ slot: CompareChooserSlot) {
        Haptics.light()
        compareChooserContext = CompareChooserContext(
            olderPhoto: pair.older,
            newerPhoto: pair.newer,
            preferredSlot: slot
        )
    }

    private func handleOpenSuggestedCompare(_ pair: PhotoComparePairSuggestion) {
        openCompare(using: pair.older, pair.newer)
    }

    private func handleCompareChooserSelectionChange(_ olderPhoto: PhotoEntry, _ newerPhoto: PhotoEntry) {
        viewModel.heroCompareOverride = TemporaryHeroPairOverride(
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

struct PhotoComparePair: Identifiable {
    let presentationID = UUID()
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    var id: String {
        "\(olderPhoto.persistentModelID)_\(newerPhoto.persistentModelID)_\(presentationID.uuidString)"
    }
}

struct TemporaryHeroPairOverride: Identifiable {
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
                Button {
                    let selectedArray = Array(selectedPhotos).sorted(by: { $0.date < $1.date })
                    if selectedArray.count == 2 {
                        openCompare(using: selectedArray[0], selectedArray[1])
                    }
                } label: {
                    Label(AppLocalization.string("Compare"), systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                .accessibilityIdentifier("photos.compare.open")
                .accessibilityLabel(AppLocalization.string("Compare selected photos"))
                .accessibilityHint(AppLocalization.string("accessibility.compare.opens"))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .appElevation(AppElevation.card)
    }

    private func performBatchDelete() {
        let photosToDelete = selectedPhotos
        let selectedPersistentIDs = Set(photosToDelete.map(\.persistentModelID))
        let selectedPhotoIDs = Set(photosToDelete.map(singlePhotoSaveID(for:)))
        let batchIDsToCancel = Set(selectedPhotoIDs.compactMap { viewModel.photoBatchByPersistentID[$0] })

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
                viewModel.isSelecting = false
            }
            for id in selectedPhotoIDs {
                viewModel.photoBatchByPersistentID.removeValue(forKey: id)
            }
            viewModel.refreshToken = UUID()
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
        guard let selection = viewModel.pendingLibrarySelection else { return }
        viewModel.pendingLibrarySelection = nil

        let sources = selection.sources.sorted(by: { $0.selectionIndex < $1.selectionIndex })
        guard !sources.isEmpty else { return }

        if sources.count == 1, let first = sources.first {
            presentSingleImport(source: first)
        } else {
            presentMultiImport(payload: MultiPhotoImportPayload(librarySources: sources))
        }

        if let dismissedAt = viewModel.pickerDismissedAt {
            let elapsed = dismissedAt.duration(to: .now)
            let dismissToImportMs = Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            AppLog.debug("📸 PhotoView: pickerDismissToImportVisibleMs=\(dismissToImportMs) count=\(sources.count)")
        }
        viewModel.pickerDismissedAt = nil
    }

    private func presentSingleImport(images: [UIImage]) {
        viewModel.multiPhotoImportPayload = nil
        showMultiImportFlow = false
        viewModel.singlePickerImage = images.first
        viewModel.singlePickerSource = nil
        showSingleImportFlow = true
    }

    private func presentMultiImport(images: [UIImage]) {
        presentMultiImport(payload: MultiPhotoImportPayload(images: images))
    }

    private func presentSingleImport(source: PhotoLibraryImageSource) {
        viewModel.multiPhotoImportPayload = nil
        showMultiImportFlow = false
        viewModel.singlePickerImage = nil
        viewModel.singlePickerSource = source
        showSingleImportFlow = true
    }

    private func presentMultiImport(payload: MultiPhotoImportPayload) {
        viewModel.singlePickerImage = nil
        viewModel.singlePickerSource = nil
        showSingleImportFlow = false
        viewModel.multiPhotoImportPayload = payload
        showMultiImportFlow = true
    }

    private func handlePendingPhotoCompletedEvent() {
        guard let completed = pendingPhotoSaveStore.completedEvent else { return }
        guard let resolved = context.model(for: completed.entryPersistentModelID) as? PhotoEntry else {
            viewModel.refreshToken = UUID()
            AppLog.debug("⚠️ PhotoView: completed photo not resolvable in main context, fallback refresh")
            return
        }

        if let batchID = completed.batchID {
            viewModel.photoBatchByPersistentID[singlePhotoSaveID(for: resolved)] = batchID
        }

        viewModel.recentlySavedPhoto = resolved
        viewModel.recentlySavedPhotoEventID = completed.eventID
    }

    private func handlePendingPhotoFailure(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        viewModel.failureToastMessage = message
        withAnimation(AppMotion.toastIn) {
            viewModel.showsFailureToast = true
        }
        pendingPhotoSaveStore.clearFailureMessage()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            withAnimation(AppMotion.toastOut) {
                viewModel.showsFailureToast = false
            }
            try? await Task.sleep(for: .milliseconds(220))
            if !viewModel.showsFailureToast {
                viewModel.failureToastMessage = nil
            }
        }
    }

    @MainActor
    private func scheduleHeroCompareOverrideReset() async {
        guard let heroCompareOverride = viewModel.heroCompareOverride else { return }
        guard heroCompareOverride.isActive else {
            viewModel.heroCompareOverride = nil
            return
        }

        let delay = heroCompareOverride.expiresAt.timeIntervalSince(AppClock.now)
        guard delay > 0 else {
            viewModel.heroCompareOverride = nil
            return
        }

        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }

        if viewModel.heroCompareOverride?.id == heroCompareOverride.id {
            viewModel.heroCompareOverride = nil
        }
    }

    #if DEBUG
    /// Opens the appropriate photo import flow for UI tests.
    private func openUITestImportHookIfNeeded() {
        guard !viewModel.didRunUITestAutoOpen else { return }
        if uiTestShouldOpenPendingAddPhotoChooser {
            viewModel.didRunUITestAutoOpen = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                presentPendingPhotoComposerChooser()
            }
            return
        }
        if uiTestShouldOpenSingleAdd {
            viewModel.didRunUITestAutoOpen = true
            openSingleAddForUITest()
            return
        }
        if let count = uiTestMultiImportCount {
            viewModel.didRunUITestAutoOpen = true
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

private extension PhotoView {

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            if viewModel.isSelecting {
                Button {
                    Haptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.sectionExit, enabled: shouldAnimate)) {
                        viewModel.isSelecting = false
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
                        viewModel.isSelecting = true
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

        if viewModel.isSelecting {
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
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(filters.isActive ? Color.appAccent : .primary)
                }
                .accessibilityLabel(AppLocalization.string("Open photo filters"))

                if !viewModel.isSelecting {
                    Button {
                        handleAddPhotoTap()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("photos.add.button")
                    .accessibilityLabel(AppLocalization.string("Add Photo"))

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
            viewModel.showUITestSourceChooserOverlay = false
            viewModel.showPendingLaunchSourceChooser = false
            viewModel.didDismissPendingLaunchSourceChooser = true
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
            viewModel.showUITestSourceChooserOverlay = false
            viewModel.showPendingLaunchSourceChooser = false
            viewModel.didDismissPendingLaunchSourceChooser = true
            DispatchQueue.main.async {
                showLibraryPicker = true
            }
        } else {
            showLibraryPicker = true
        }
    }

}
