import SwiftUI
import SwiftData

/// Widok do dodawania nowego zdjęcia z tagami i opcjonalnymi pomiarami
struct AddPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeMetrics: ActiveMetricsStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore

    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var date: Date = AppClock.now
    @State private var selectedTags: Set<PhotoTag> = [.wholeBody]
    @State private var metricValues: [MetricKind: Double] = [:]
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    
    init(previewImage: UIImage? = nil) {
        self._selectedImage = State(initialValue: previewImage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 220, tint: Color.cyan.opacity(0.18))

                ScrollView {
                    VStack(spacing: 16) {
                        photoSelectionCard
                        photoPreviewCard
                        tagsCard
                        dateCard
                        measurementsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
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
                    .disabled(!canSave || isSaving)
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
        }
    }
}

// MARK: - Glass Cards
private extension AddPhotoView {

    @ViewBuilder
    var photoSelectionCard: some View {
        // Karta wyboru zdjęcia znika gdy obraz jest już wybrany.
        // Kamera i biblioteka nadal dostępne przez photoPreviewCard (zamiana zdjęcia).
        if selectedImage == nil {
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
        if let image = selectedImage {
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
        AppGlassCard(depth: .base) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("Tags"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                ForEach(availableTags) { tag in
                    Toggle(tag.title, isOn: tagBinding(for: tag))
                        .toggleStyle(LiquidSwitchToggleStyle())
                }
            }
        }
    }

    var dateCard: some View {
        AppGlassCard(depth: .base) {
            DatePicker(
                AppLocalization.string("Date"),
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    @ViewBuilder
    var measurementsCard: some View {
        if !activeMetrics.activeKinds.isEmpty {
            AppGlassCard(depth: .base) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppLocalization.string("Measurements (Optional)"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)

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
    
    /// Tagi dostępne do wyboru (whole body + aktywne metryki z wyjątkiem weight, body fat, lean mass)
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

    var hasInvalidMetricInputs: Bool {
        activeMetrics.activeKinds.contains { kind in
            let value = metricValues[kind] ?? 0
            if value == 0 { return false }
            return !MetricInputValidator
                .validateMetricDisplayValue(value, kind: kind, unitsSystem: unitsSystem)
                .isValid
        }
    }

    func metricValidationMessage(for kind: MetricKind) -> String? {
        let value = metricValues[kind] ?? 0
        if value == 0 { return nil }
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
    
    func metricBinding(for kind: MetricKind) -> Binding<Double> {
        Binding(
            get: { metricValues[kind] ?? 0 },
            set: { metricValues[kind] = $0 }
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
                metricValues: metricValues,
                unitsSystem: unitsSystem
            )
            let enqueueMs = milliseconds(from: enqueueStart.duration(to: .now))
            let dismissStart = ContinuousClock.now

            isSaving = false
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

/// Pole do wprowadzania wartości metryki
private struct MetricValueField: View {
    let kind: MetricKind
    @Binding var value: Double
    let unitsSystem: String
    let validationMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.title)

                Spacer()

                TextField(AppLocalization.string("Value"), value: $value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)

                Text(kind.unitSymbol(unitsSystem: unitsSystem))
                    .foregroundStyle(.secondary)
            }

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

/// Wrapper Identifiable przekazujący obrazy do sheet(item:).
/// Gwarantuje że SwiftUI czyta dane w momencie prezentacji sheetu.
struct MultiPhotoImportPayload: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

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
