import SwiftUI
import Photos

struct TransformationCardPreviewSheet: View {
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry
    let unitsSystem: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRatio: CardAspectRatio = .story
    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var showShareSheet = false
    @State private var showSaveAlert = false
    @State private var saveMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Aspect ratio picker
                    Picker("", selection: $selectedRatio) {
                        ForEach(CardAspectRatio.allCases, id: \.self) { ratio in
                            Label(ratio.label, systemImage: ratio.iconName)
                                .tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Preview
                    if isRendering {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    } else if let image = renderedImage {
                        GeometryReader { geo in
                            let aspect = CGFloat(selectedRatio.width) / CGFloat(selectedRatio.height)
                            let maxW = geo.size.width - 32
                            let maxH = geo.size.height
                            let fitW = min(maxW, maxH * aspect)
                            let fitH = fitW / aspect

                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: fitW, height: fitH)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .white.opacity(0.08), radius: 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        Spacer()
                        Text(AppLocalization.string("transformation.card.preview.error"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            guard let image = renderedImage else { return }
                            saveToPhotos(image)
                        } label: {
                            Label(AppLocalization.string("transformation.card.save"), systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .disabled(renderedImage == nil || isRendering)

                        Button {
                            guard renderedImage != nil else { return }
                            showShareSheet = true
                        } label: {
                            Label(AppLocalization.string("transformation.card.shareAction"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 252/255, green: 163/255, blue: 17/255))
                        .disabled(renderedImage == nil || isRendering)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(AppLocalization.string("transformation.card.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) { dismiss() }
                }
            }
            .alert(AppLocalization.string("Export"), isPresented: $showSaveAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(saveMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = renderedImage {
                    ShareSheet(items: [image])
                }
            }
            .task(id: selectedRatio) {
                await renderCard()
            }
        }
    }

    // MARK: - Rendering

    private func renderCard() async {
        isRendering = true
        renderedImage = nil

        let weightOld = olderPhoto.linkedMetrics.first { $0.kind == .weight }?.value
        let weightNew = newerPhoto.linkedMetrics.first { $0.kind == .weight }?.value
        let ratio = selectedRatio

        let input = TransformationCardInput(
            olderImageData: olderPhoto.imageData,
            newerImageData: newerPhoto.imageData,
            olderDate: olderPhoto.date,
            newerDate: newerPhoto.date,
            weightOld: weightOld,
            weightNew: weightNew,
            unitsSystem: unitsSystem,
            aspectRatio: ratio
        )

        let jpegData = await Task.detached(priority: .userInitiated) {
            TransformationCardRenderer.render(input)
        }.value

        if let jpegData, let image = UIImage(data: jpegData) {
            renderedImage = image
        }
        isRendering = false
    }

    // MARK: - Save

    private func saveToPhotos(_ image: UIImage) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        performSave(image)
                    } else {
                        saveMessage = AppLocalization.string("Photo access denied. Enable Photos access in Settings to save.")
                        showSaveAlert = true
                    }
                }
            }
            return
        }

        guard status == .authorized || status == .limited else {
            saveMessage = AppLocalization.string("Photo access denied. Enable Photos access in Settings to save.")
            showSaveAlert = true
            return
        }

        performSave(image)
    }

    private func performSave(_ image: UIImage) {
        ImageSaver.save(image) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    saveMessage = AppLocalization.string("Saved to Photos.")
                case .failure(let message):
                    saveMessage = message
                }
                showSaveAlert = true
            }
        }
    }
}
