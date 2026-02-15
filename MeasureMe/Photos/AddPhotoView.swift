import SwiftUI
import SwiftData

/// Widok do dodawania nowego zdjęcia z tagami i opcjonalnymi pomiarami
struct AddPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var activeMetrics: ActiveMetricsStore

    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var date: Date = .now
    @State private var selectedTags: Set<PhotoTag> = [.wholeBody]
    @State private var metricValues: [MetricKind: Double] = [:]
    @State private var saveErrorMessage: String?
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    private let onSaved: (() -> Void)?
    
    init(previewImage: UIImage? = nil, onSaved: (() -> Void)? = nil) {
        self._selectedImage = State(initialValue: previewImage)
        self.onSaved = onSaved
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
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
                        Haptics.medium()
                        savePhoto()
                    }
                    .disabled(!canSave)
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

    var photoSelectionCard: some View {
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
    
    func savePhoto() {
        guard let image = selectedImage else {
            AppLog.debug("❌ AddPhotoView: No image selected")
            return
        }

        guard !hasInvalidMetricInputs else {
            saveErrorMessage = AppLocalization.string("Fix highlighted values before saving.")
            Haptics.error()
            return
        }
        
        // Optymalizacja: zmniejsz rozmiar obrazu przed kompresją
        let optimizedImage = image.resized(maxDimension: 1920).fixedOrientation()
        
        // Kompresuj z targetowym rozmiarem max 2MB
        guard let imageData = optimizedImage.compressed(toMaxSize: 2_000_000) else {
            AppLog.debug("❌ AddPhotoView: Failed to compress image")
            return
        }
        
        AppLog.debug("✅ AddPhotoView: Image compressed, size: \(PhotoUtilities.formatFileSize(imageData.count))")
        
        let snapshots = createMetricSnapshots()
        
        // Also create MetricSample entries for Measurements with the same date
        for (kind, displayValue) in metricValues {
            guard displayValue > 0 else { continue }
            let metric = kind.valueToMetric(fromDisplay: displayValue, unitsSystem: unitsSystem)
            let sample = MetricSample(kind: kind, value: metric, date: date)
            context.insert(sample)
        }
        
        let entry = PhotoEntry(
            imageData: imageData,
            date: date,
            tags: Array(selectedTags),
            linkedMetrics: snapshots
        )

        AppLog.debug("✅ AddPhotoView: Creating PhotoEntry with \(selectedTags.count) tags and \(snapshots.count) metrics")
        
        // Wstaw do kontekstu
        context.insert(entry)
        
        do {
            // Zapisz kontekst
            try context.save()
            AppLog.debug("✅ AddPhotoView: Context saved successfully")
            
            // Wymuś odświeżenie kontekstu aby @Query w PhotosView się zaktualizował
            context.processPendingChanges()

            NotificationManager.shared.recordPhotoAdded(date: date)
            
            onSaved?()
            
            // Zamknij widok
            dismiss()
        } catch {
            AppLog.debug("❌ AddPhotoView: Failed to save context: \(error)")
            saveErrorMessage = AppLocalization.string("Could not save photo. Please try again.")
            Haptics.error()
        }
    }
    
    func createMetricSnapshots() -> [MetricValueSnapshot] {
        metricValues.compactMap { kind, value in
            guard value > 0 else { return nil }
            let metricValue = kind.valueToMetric(fromDisplay: value, unitsSystem: unitsSystem)
            
            return MetricValueSnapshot(
                kind: kind,
                value: metricValue,
                unit: kind.unitSymbol(unitsSystem: "metric")
            )
        }
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
}

#Preview("With Image") {
    AddPhotoView(previewImage: UIImage(systemName: "photo.fill"))
        .modelContainer(makePreviewContainer())
        .environmentObject(ActiveMetricsStore())
}

