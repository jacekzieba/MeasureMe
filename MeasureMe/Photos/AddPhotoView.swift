import SwiftUI
import SwiftData

/// View for adding a new photo with tags and optional measurements
struct AddPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeMetrics: ActiveMetricsStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore

    private let initialPreviewSource: PhotoLibraryImageSource?
    private let onSaved: (() -> Void)?
    @State private var selectedImage: UIImage?
    @State private var didLoadInitialSource = false
    @State private var isLoadingPreview = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var date: Date = AppClock.now
    @State private var selectedTags: Set<PhotoTag> = [.wholeBody]
    @State private var metricValues: [MetricKind: Double] = [:]
    @State private var isMeasurementsExpanded = false
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    private var shouldStartExpandedForUITests: Bool {
        #if DEBUG
        UITestArgument.isPresent(.expandMeasurements)
        #else
        false
        #endif
    }
    
    init(
        previewImage: UIImage? = nil,
        previewSource: PhotoLibraryImageSource? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.initialPreviewSource = previewSource
        self.onSaved = onSaved
        self._selectedImage = State(initialValue: previewImage)
        self._isLoadingPreview = State(initialValue: previewImage == nil && previewSource != nil)
    }

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 220, tint: Color.cyan.opacity(0.18))

            ScrollView {
                VStack(spacing: 16) {
                    photoSelectionCard
                    photoPreviewCard
                    tagsCard
                    dateCard
                    measurementsCard
                    #if DEBUG
                    if UITestArgument.isPresent(.mode) {
                        // 1×1 pt fixer view: on appear it traverses the full UIKit window
                        // tree and sets delaysContentTouches = false on every UIScrollView,
                        // letting XCTest synthesised taps reach SwiftUI buttons immediately.
                        ScrollViewTouchDelayFixer()
                            .frame(width: 1, height: 1)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .accessibilityIdentifier("addPhoto.scrollView")
        }
        .navigationTitle(AppLocalization.string("Add Photo"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalization.string("Cancel")) {
                    dismiss()
                }
                .accessibilityIdentifier("addPhoto.cancelButton")
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.string("Save")) {
                    Haptics.medium()
                    Task { await savePhoto() }
                }
                .disabled(!canSave || isSaving || isLoadingPreview)
                .accessibilityIdentifier("addPhoto.saveButton")
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker(selectedImage: $selectedImage)
        }
        .alert(AppLocalization.string("Save Failed"), isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button(AppLocalization.string("OK"), role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .task(id: initialPreviewSource?.id) {
            guard !didLoadInitialSource else { return }
            guard selectedImage == nil else { return }
            guard let initialPreviewSource else { return }
            didLoadInitialSource = true
            if let exifDate = await PhotoLibraryImageLoader.fetchCreationDate(from: initialPreviewSource) {
                date = exifDate
            }
            do {
                isLoadingPreview = true
                let loadedImage = try await PhotoLibraryImageLoader.loadPreparedImage(from: initialPreviewSource)
                selectedImage = loadedImage
            } catch {
                AppLog.debug("⚠️ AddPhotoView: failed loading initial picker image: \(error)")
                saveErrorMessage = AppLocalization.string("Could not load photo. Please try again.")
            }
            isLoadingPreview = false
        }
        .onChange(of: selectedImage) { _, newValue in
            if newValue != nil {
                isLoadingPreview = false
            }
        }
        .onAppear {
            if shouldStartExpandedForUITests && !activeMetrics.activeKinds.isEmpty {
                isMeasurementsExpanded = true
            }
        }
    }
}

// MARK: - Glass Cards
private extension AddPhotoView {

    @ViewBuilder
    var photoSelectionCard: some View {
        // Photo selection card disappears when an image is already selected.
        // Camera and library remain available via photoPreviewCard (swap photo).
        if selectedImage == nil && !isLoadingPreview {
            AppGlassCard(
                depth: .elevated,
                tint: Color.cyan.opacity(0.08),
                contentPadding: 16
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Haptics.light()
                        showCamera = true
                    } label: {
                        HStack(spacing: 12) {
                            GlassPillIcon(systemName: "camera.fill")
                            Text(AppLocalization.string("Take Photo"))
                                .font(AppTypography.bodyEmphasis)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider().overlay(Color.white.opacity(0.12))

                    Button {
                        Haptics.light()
                        showPhotoLibrary = true
                    } label: {
                        HStack(spacing: 12) {
                            GlassPillIcon(systemName: "photo.on.rectangle")
                            Text(AppLocalization.string("Choose from Library"))
                                .font(AppTypography.bodyEmphasis)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var photoPreviewCard: some View {
        if isLoadingPreview {
            AppGlassCard(depth: .elevated, tint: Color.cyan.opacity(0.08), contentPadding: 20) {
                HStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(AppLocalization.string("Preparing"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("addPhoto.preview.loading")
        } else if let image = selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
    }

    var tagsCard: some View {
        PhotoFormTagsSection(
            title: AppLocalization.string("Tags"),
            tags: availableTags,
            accessibilityPrefix: "addPhoto",
            tagBinding: tagBinding(for:)
        )
    }

    var dateCard: some View {
        PhotoFormDateSection(
            title: AppLocalization.string("Date"),
            date: $date
        )
    }

    @ViewBuilder
    var measurementsCard: some View {
        if !activeMetrics.activeKinds.isEmpty {
            CollapsibleMeasurementsSection(
                title: AppLocalization.string("Measurements (Optional)"),
                filledCount: filledMetricCount,
                isExpanded: $isMeasurementsExpanded,
                toggleAccessibilityIdentifier: "addPhoto.measurements.toggle",
                contentAccessibilityIdentifier: "addPhoto.measurements.content",
                filledCountAccessibilityIdentifier: "addPhoto.measurements.filledCount"
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(activeMetrics.activeKinds, id: \.self) { kind in
                        MetricValueField(
                            kind: kind,
                            value: metricBinding(for: kind),
                            unitsSystem: unitsSystem,
                            validationMessage: metricValidationMessage(for: kind)
                        )
                    }

                    if hasInvalidMetricInputs {
                        Text(AppLocalization.string("Fix highlighted values before saving."))
                            .font(AppTypography.micro)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Computed Properties
private extension AddPhotoView {
    
    /// Tags available for selection (whole body + active metrics except weight, body fat, lean mass)
    var availableTags: [PhotoTag] {
        var tags: [PhotoTag] = [.wholeBody]
        
        let activeTags = activeMetrics.activeKinds
            .filter { $0 != .weight && $0 != .bodyFat && $0 != .leanBodyMass }
            .compactMap { PhotoTag(metricKind: $0) }
        
        tags.append(contentsOf: activeTags)
        return tags
    }
    
    var canSave: Bool {
        selectedImage != nil && !hasInvalidMetricInputs
    }

    var filledMetricCount: Int {
        activeMetrics.activeKinds.reduce(0) { result, kind in
            guard let value = metricValues[kind], value != 0 else { return result }
            return result + 1
        }
    }

    var sanitizedMetricValues: [MetricKind: Double] {
        metricValues.filter { _, value in value != 0 }
    }

    var hasInvalidMetricInputs: Bool {
        activeMetrics.activeKinds.contains { kind in
            guard let value = metricValues[kind], value != 0 else { return false }
            return !MetricInputValidator
                .validateMetricDisplayValue(value, kind: kind, unitsSystem: unitsSystem)
                .isValid
        }
    }

    func metricValidationMessage(for kind: MetricKind) -> String? {
        guard let value = metricValues[kind], value != 0 else { return nil }
        let result = MetricInputValidator.validateMetricDisplayValue(value, kind: kind, unitsSystem: unitsSystem)
        if result.isValid {
            return nil
        }
        return result.message
    }
}

// MARK: - Bindings
private extension AddPhotoView {
    
    func tagBinding(for tag: PhotoTag) -> Binding<Bool> {
        Binding(
            get: { selectedTags.contains(tag) },
            set: { isSelected in
                if isSelected {
                    selectedTags.insert(tag)
                } else {
                    selectedTags.remove(tag)
                }
            }
        )
    }
    
    func metricBinding(for kind: MetricKind) -> Binding<Double?> {
        Binding(
            get: { metricValues[kind] },
            set: { newValue in
                if let newValue {
                    metricValues[kind] = newValue
                } else {
                    metricValues.removeValue(forKey: kind)
                }
            }
        )
    }
}

// MARK: - Actions
private extension AddPhotoView {
    
    @MainActor
    func savePhoto() async {
        guard let image = selectedImage else {
            AppLog.debug("❌ AddPhotoView: No image selected")
            return
        }

        guard !hasInvalidMetricInputs else {
            saveErrorMessage = AppLocalization.string("Fix highlighted values before saving.")
            Haptics.error()
            return
        }

        isSaving = true
        let enqueueStart = ContinuousClock.now
        do {
            let jobID = try await pendingPhotoSaveStore.enqueueSingle(
                sourceImage: image,
                date: date,
                tags: selectedTags,
                metricValues: sanitizedMetricValues,
                unitsSystem: unitsSystem
            )
            let enqueueMs = milliseconds(from: enqueueStart.duration(to: .now))
            let dismissStart = ContinuousClock.now

            isSaving = false
            onSaved?()
            dismiss()
            let enqueueToDismissMs = milliseconds(from: dismissStart.duration(to: .now))
            AppLog.debug(
                "✅ AddPhotoView: enqueue=\(enqueueMs)ms enqueueToDismiss=\(enqueueToDismissMs)ms jobID=\(jobID.uuidString)"
            )
        } catch {
            isSaving = false
            AppLog.debug("❌ AddPhotoView: Failed to enqueue single save: \(error)")
            saveErrorMessage = AppLocalization.string("Could not save photo. Please try again.")
            Haptics.error()
        }
    }

    func milliseconds(from duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

// MARK: - Supporting Views

/// Field for entering a metric value
private struct MetricValueField: View {
    let kind: MetricKind
    @Binding var value: Double?
    let unitsSystem: String
    let validationMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AppSpacing.xs) {
                kind.iconView(font: AppTypography.iconSmall, size: 16, tint: Color.appAccent)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                Text(kind.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Spacer(minLength: 0)

                TextField(
                    AppLocalization.string("Value"),
                    value: $value,
                    format: .number.precision(.fractionLength(2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(AppTypography.bodyEmphasis.monospacedDigit())
                .frame(minWidth: 64)
                .accessibilityIdentifier("addPhoto.metricField.\(kind.rawValue)")

                Text(kind.unitSymbol(unitsSystem: unitsSystem))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
            .appInputContainer()

            if let validationMessage {
                Text(validationMessage)
                    .font(AppTypography.micro)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Multi-photo payload

/// Identifiable wrapper for passing images to sheet(item:).
/// Ensures SwiftUI reads data at the moment the sheet is presented.
struct MultiPhotoImportPayload: Identifiable {
    let id = UUID()
    let items: [Item]

    struct Item: Identifiable {
        let id: UUID
        let image: UIImage?
        let librarySource: PhotoLibraryImageSource?

        init(image: UIImage) {
            self.id = UUID()
            self.image = image
            self.librarySource = nil
        }

        init(librarySource: PhotoLibraryImageSource) {
            self.id = librarySource.id
            self.image = nil
            self.librarySource = librarySource
        }
    }

    init(images: [UIImage]) {
        self.items = images.map { Item(image: $0) }
    }

    init(librarySources: [PhotoLibraryImageSource]) {
        self.items = librarySources
            .sorted(by: { $0.selectionIndex < $1.selectionIndex })
            .map { Item(librarySource: $0) }
    }

    var images: [UIImage] {
        items.compactMap(\.image)
    }

    var librarySources: [PhotoLibraryImageSource] {
        items.compactMap(\.librarySource)
    }
}

// MARK: - UI-Test Helpers

#if DEBUG
/// Walks the **entire UIKit window tree** and sets `delaysContentTouches = false` on
/// every `UIScrollView` (and subclass) it finds.  This makes XCTest synthesised taps
/// reach SwiftUI `.buttonStyle(.plain)` buttons without the 150 ms hold that
/// `UIScrollView` normally uses to distinguish a tap from a scroll gesture.
///
/// The window-level scan is necessary because SwiftUI may use a private UIScrollView
/// subclass whose `setDelaysContentTouches:` overrides the base-class implementation,
/// bypassing appearance-proxy or class-level swizzling.
///
/// Only rendered when the `-uiTestMode` launch argument is present (see AddPhotoView body).
private struct ScrollViewTouchDelayFixer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        // Run immediately (after layout) and again after a short pause in case
        // SwiftUI re-configures the scroll view after its initial setup.
        DispatchQueue.main.async { Self.disableTouchDelay() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Self.disableTouchDelay() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private static func disableTouchDelay() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                fix(window)
            }
        }
    }

    private static func fix(_ view: UIView) {
        if let sv = view as? UIScrollView {
            sv.delaysContentTouches = false
        }
        for sub in view.subviews { fix(sub) }
    }
}
#endif

// MARK: - Preview
private func makePreviewContainer() -> ModelContainer {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PhotoEntry.self, configurations: config)
    } catch {
        fatalError("Preview ModelContainer failed: \(error)")
    }
}

#Preview("Empty State") {
    AddPhotoView()
        .modelContainer(makePreviewContainer())
        .environmentObject(ActiveMetricsStore())
        .environmentObject(PendingPhotoSaveStore(autoStartProcessing: false))
}

#Preview("With Image") {
    AddPhotoView(previewImage: UIImage(systemName: "photo.fill"))
        .modelContainer(makePreviewContainer())
        .environmentObject(ActiveMetricsStore())
        .environmentObject(PendingPhotoSaveStore(autoStartProcessing: false))
}
