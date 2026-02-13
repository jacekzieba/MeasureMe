import SwiftUI
import SwiftData
import Photos

/// Szczegółowy widok pojedynczego zdjęcia z możliwością edycji i pełnoekranowego wyświetlania
struct PhotoDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    
    @Bindable var photo: PhotoEntry
    
    @State private var showFullScreen = false
    @State private var isEditing = false
    @State private var showSaveAlert = false
    @State private var saveAlertTitle = AppLocalization.string("Photo Saved")
    @State private var saveAlertMessage = ""
    @State private var isSavingToPhotos = false
    
    // Edit mode state
    @State private var editedDate: Date
    @State private var editedTags: Set<PhotoTag>
    @State private var editedMetrics: [MetricValueSnapshot]
    let onDeleted: (() -> Void)?
    
    init(photo: PhotoEntry, onDeleted: (() -> Void)? = nil) {
        self.photo = photo
        self.onDeleted = onDeleted
        _editedDate = State(initialValue: photo.date)
        _editedTags = State(initialValue: Set(photo.tags))
        _editedMetrics = State(initialValue: photo.linkedMetrics)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoSection
                    dateSection
                    tagsSection
                    metricsSection
                    
                    if !isEditing {
                        deleteButton
                    }
                }
                .padding()
            }
            .navigationTitle(isEditing ? AppLocalization.string("Edit Photo") : AppLocalization.string("Photo Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Close")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button(AppLocalization.string("Save")) {
                            saveChanges()
                        }
                    } else {
                        Button(AppLocalization.string("Edit")) {
                            startEditing()
                        }
                    }
                }

                if !isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            saveToPhotos()
                        } label: {
                            Label(AppLocalization.string("Save to Photos"), systemImage: "square.and.arrow.down")
                        }
                        .disabled(isSavingToPhotos)
                        .accessibilityLabel(AppLocalization.string("Save photo to gallery"))
                        .accessibilityHint(AppLocalization.string("accessibility.save.photo.to.gallery.hint"))
                    }
                }
                
                if isEditing {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(AppLocalization.string("Cancel"), role: .cancel) {
                            cancelEditing()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                FullScreenPhotoView(
                    imageData: photo.imageData,
                    cacheID: String(describing: photo.id)
                )
            }
            .alert(saveAlertTitle, isPresented: $showSaveAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(saveAlertMessage)
            }
        }
    }
}

// MARK: - Sections
private extension PhotoDetailView {
    
    var photoSection: some View {
        PhotoPreviewSection(
            imageData: photo.imageData,
            cacheID: String(describing: photo.id),
            onTapFullScreen: { showFullScreen = true }
        )
    }
    
    var dateSection: some View {
        PhotoDateSection(
            date: photo.date,
            editedDate: $editedDate,
            isEditing: isEditing
        )
    }
    
    var tagsSection: some View {
        PhotoTagsSection(
            tags: photo.tags,
            editedTags: $editedTags,
            isEditing: isEditing
        )
    }
    
    var metricsSection: some View {
        PhotoMetricsSection(
            metrics: photo.linkedMetrics,
            editedMetrics: $editedMetrics,
            metricsStore: metricsStore,
            isEditing: isEditing
        )
    }
    
    var deleteButton: some View {
        Button(role: .destructive) {
            deletePhoto()
        } label: {
            Label(AppLocalization.string("Delete Photo"), systemImage: "trash")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 20)
    }
}

// MARK: - Actions
private extension PhotoDetailView {
    
    func startEditing() {
        editedDate = photo.date
        editedTags = Set(photo.tags)
        editedMetrics = photo.linkedMetrics
        isEditing = true
    }
    
    func cancelEditing() {
        editedDate = photo.date
        editedTags = Set(photo.tags)
        editedMetrics = photo.linkedMetrics
        isEditing = false
    }
    
    func saveChanges() {
        photo.date = editedDate
        photo.tags = Array(editedTags)
        photo.linkedMetrics = editedMetrics

        do {
            try context.save()
            isEditing = false
        } catch {
            presentSaveFailure(message: AppLocalization.string("Could not save photo changes. Please try again."))
            AppLog.debug("⚠️ Failed saving photo changes: \(error.localizedDescription)")
        }
    }
    
    func deletePhoto() {
        context.delete(photo)
        do {
            try context.save()
            context.processPendingChanges()
            onDeleted?()
            dismiss()
        } catch {
            presentSaveFailure(message: AppLocalization.string("Could not delete photo. Please try again."))
            AppLog.debug("⚠️ Failed deleting photo: \(error.localizedDescription)")
        }
    }

    func saveToPhotos() {
        Task { @MainActor in
            guard !isSavingToPhotos else { return }
            isSavingToPhotos = true
            defer { isSavingToPhotos = false }

            guard let image = UIImage(data: photo.imageData) else {
                presentSaveFailure(message: AppLocalization.string("Unable to save this image."))
                return
            }

            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                presentSaveFailure(message: AppLocalization.string("Permission denied. Enable Photos access in Settings."))
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                saveAlertTitle = AppLocalization.string("Photo Saved")
                saveAlertMessage = AppLocalization.string("Saved to Photos.")
                showSaveAlert = true
                Haptics.success()
            } catch {
                presentSaveFailure(message: error.localizedDescription)
            }
        }
    }

    func presentSaveFailure(message: String) {
        saveAlertTitle = AppLocalization.string("Save Failed")
        saveAlertMessage = message
        showSaveAlert = true
        Haptics.error()
    }
}

// MARK: - Preview
private func makePhotoDetailPreviewContainer() -> (ModelContainer, PhotoEntry) {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PhotoEntry.self, configurations: config)
        let context = container.mainContext

        let sampleImage = UIImage(systemName: "photo")!
        let imageData = sampleImage.pngData()!

        let samplePhoto = PhotoEntry(
            imageData: imageData,
            date: Date(),
            tags: [.wholeBody, .waist],
            linkedMetrics: [
                MetricValueSnapshot(kind: .weight, value: 75.5, unit: "kg"),
                MetricValueSnapshot(kind: .waist, value: 85.0, unit: "cm")
            ]
        )
        context.insert(samplePhoto)
        return (container, samplePhoto)
    } catch {
        fatalError("Preview ModelContainer failed: \(error)")
    }
}

#Preview {
    let (container, photo) = makePhotoDetailPreviewContainer()
    PhotoDetailView(photo: photo)
        .modelContainer(container)
        .environmentObject(ActiveMetricsStore())
}
