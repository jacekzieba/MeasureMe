import SwiftUI
import SwiftData

/// Widok Quick Import dla wielu zdjęć jednocześnie.
/// Pozwala wybrać wspólną datę i tagi, a następnie zapisać wszystkie zdjęcia jednym tapem.
struct MultiPhotoImportView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeMetrics: ActiveMetricsStore
    @EnvironmentObject private var pendingPhotoSaveStore: PendingPhotoSaveStore

    let images: [UIImage]

    @State private var date: Date = AppClock.now
    @State private var selectedTags: Set<PhotoTag> = [.wholeBody]
    @State private var isSaving = false
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"

    /// Jeśli nie nil, otwiera AddPhotoView dla konkretnego zdjęcia
    @State private var singlePhotoPayload: MultiPhotoImportPayload? = nil

    init(images: [UIImage]) {
        self.images = images
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 200, tint: Color.cyan.opacity(0.18))

                ScrollView {
                    VStack(spacing: 16) {
                        thumbnailStrip
                        dateCard
                        tagsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(importTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("multiImport.cancelButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
                        Haptics.medium()
                        Task { await saveAll() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("multiImport.saveButton")
                }
            }
            // Otwiera single-photo flow po tapnięciu miniaturki
            .sheet(item: $singlePhotoPayload) { payload in
                AddPhotoView(previewImage: payload.images.first)
            }
        }
    }
}

// MARK: - Subviews

private extension MultiPhotoImportView {

    var importTitle: String {
        let count = images.count
        if count == 1 {
            return AppLocalization.string("Import 1 Photo")
        }
        return String(format: AppLocalization.string("Import %d Photos"), count)
    }

    var thumbnailStrip: some View {
        AppGlassCard(depth: .elevated, tint: Color.cyan.opacity(0.08), contentPadding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.string("Photos"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Button {
                                // Otwórz single-photo flow dla tego zdjęcia
                                singlePhotoPayload = MultiPhotoImportPayload(images: [image])
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        // Numeracja dla czytelności przy wielu zdjęciach
                                        if images.count > 1 {
                                            Text("\(index + 1)")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .padding(3)
                                                .background(Color.black.opacity(0.55))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 2) // zapobiegnie ucięciu cienia
                }
                .accessibilityIdentifier("multiImport.thumbnailStrip")
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

    var tagsCard: some View {
        AppGlassCard(depth: .base) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("Tags"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                ForEach(availableTags) { tag in
                    Toggle(tag.title, isOn: tagBinding(for: tag))
                        .toggleStyle(LiquidSwitchToggleStyle())
                        .accessibilityIdentifier("multiImport.tagToggle.\(tag.rawValue)")
                }
            }
        }
    }

}

// MARK: - Bindings & Actions

private extension MultiPhotoImportView {

    /// Tagi dostępne do wyboru — whole body + aktywne metryki (bez weight, bodyFat, leanBodyMass)
    var availableTags: [PhotoTag] {
        var tags: [PhotoTag] = [.wholeBody]
        let activeTags = activeMetrics.activeKinds
            .filter { $0 != .weight && $0 != .bodyFat && $0 != .leanBodyMass }
            .compactMap { PhotoTag(metricKind: $0) }
        tags.append(contentsOf: activeTags)
        return tags
    }

    func tagBinding(for tag: PhotoTag) -> Binding<Bool> {
        Binding(
            get: { selectedTags.contains(tag) },
            set: { isOn in
                if isOn { selectedTags.insert(tag) } else { selectedTags.remove(tag) }
            }
        )
    }

    @MainActor
    func saveAll() async {
        guard !isSaving else { return }
        isSaving = true

        let imagesToQueue = images
        let dateToQueue = date
        let tagsToQueue = selectedTags
        let unitsToQueue = unitsSystem
        let dismissStart = ContinuousClock.now

        dismiss()
        let dismissMs = milliseconds(from: dismissStart.duration(to: .now))

        Task { @MainActor in
            let enqueueStart = ContinuousClock.now
            do {
                let queuedIDs = try await pendingPhotoSaveStore.enqueueMany(
                    sourceImages: imagesToQueue,
                    date: dateToQueue,
                    tags: tagsToQueue,
                    metricValues: [:],
                    unitsSystem: unitsToQueue
                )
                let enqueueMs = milliseconds(from: enqueueStart.duration(to: .now))
                AppLog.debug(
                    "✅ MultiPhotoImportView: enqueued \(queuedIDs.count)/\(imagesToQueue.count) photos enqueue=\(enqueueMs)ms dismiss=\(dismissMs)ms"
                )
            } catch {
                pendingPhotoSaveStore.lastFailureMessage = AppLocalization.string("Could not save photos. Please try again.")
                AppLog.debug("❌ MultiPhotoImportView: enqueue failed: \(error)")
                Haptics.error()
            }
        }
    }

    func milliseconds(from duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}

// MARK: - Preview

#if DEBUG
private func makePreviewContainer() -> ModelContainer {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PhotoEntry.self, configurations: config)
    } catch {
        fatalError("Preview ModelContainer failed: \(error)")
    }
}

#Preview {
    let images = (1...3).map { _ in UIImage(systemName: "photo.fill")! }
    MultiPhotoImportView(images: images)
        .modelContainer(makePreviewContainer())
        .environmentObject(ActiveMetricsStore())
        .environmentObject(PendingPhotoSaveStore(autoStartProcessing: false))
}
#endif
