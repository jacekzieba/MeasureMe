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
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    private let onSaved: (() -> Void)?
    
    init(previewImage: UIImage? = nil, onSaved: (() -> Void)? = nil) {
        self._selectedImage = State(initialValue: previewImage)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSelectionSection
                
                if selectedImage != nil {
                    photoPreviewSection
                }

                tagsSection
                dateSection
                measurementsSection
            }
            .navigationTitle(AppLocalization.string("Add Photo"))
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }
}

// MARK: - Sections
private extension AddPhotoView {
    
    var photoSelectionSection: some View {
        Section {
            Button {
                Haptics.light()
                showCamera = true
            } label: {
                Label(AppLocalization.string("Take Photo"), systemImage: "camera.fill")
            }
            
            Button {
                Haptics.light()
                showPhotoLibrary = true
            } label: {
                Label(AppLocalization.string("Choose from Library"), systemImage: "photo.on.rectangle")
            }
        }
    }
    
    @ViewBuilder
    var photoPreviewSection: some View {
        if let image = selectedImage {
            Section {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    var tagsSection: some View {
        Section(AppLocalization.string("Tags")) {
            ForEach(availableTags) { tag in
                Toggle(tag.title, isOn: tagBinding(for: tag))
            }
        }
    }
    
    var dateSection: some View {
        Section {
            DatePicker(
                "Date",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }
    
    @ViewBuilder
    var measurementsSection: some View {
        if !activeMetrics.activeKinds.isEmpty {
            Section(AppLocalization.string("Measurements (Optional)")) {
                ForEach(activeMetrics.activeKinds, id: \.self) { kind in
                    MetricValueField(
                        kind: kind,
                        value: metricBinding(for: kind),
                        unitsSystem: unitsSystem
                    )
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
        selectedImage != nil
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
        
        // Optymalizacja: zmniejsz rozmiar obrazu przed kompresją
        let optimizedImage = image.resized(maxDimension: 1920).fixedOrientation()
        
        // Kompresuj z targetowym rozmiarem max 2MB
        guard let imageData = optimizedImage.compressed(toMaxSize: 2_000_000) else {
            AppLog.debug("❌ AddPhotoView: Failed to compress image")
            return
        }
        
        AppLog.debug("✅ AddPhotoView: Image compressed, size: \(PhotoUtilities.formatFileSize(imageData.count))")
        
        let snapshots = createMetricSnapshots()
        
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
    
    var body: some View {
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
    }
}

// MARK: - Preview
#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: PhotoEntry.self, configurations: config)
    let metricsStore = ActiveMetricsStore()
    
    return AddPhotoView()
        .modelContainer(container)
        .environmentObject(metricsStore)
}

#Preview("With Image") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: PhotoEntry.self, configurations: config)
    let metricsStore = ActiveMetricsStore()
    
    return AddPhotoView(previewImage: UIImage(systemName: "photo.fill"))
        .modelContainer(container)
        .environmentObject(metricsStore)
}
