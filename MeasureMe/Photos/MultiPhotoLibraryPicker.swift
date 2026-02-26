import SwiftUI
import Photos
import PhotosUI

struct PhotoLibraryImageSource: Identifiable {
    let id: UUID
    let assetIdentifier: String?
    let itemProvider: NSItemProvider
    let selectionIndex: Int
}

struct MultiPhotoLibrarySelectionPayload: Identifiable {
    let id = UUID()
    let sources: [PhotoLibraryImageSource]
}

enum PhotoLibraryImageLoadError: LocalizedError {
    case unsupportedProvider
    case failedToLoadObject

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "Selected photo cannot be loaded"
        case .failedToLoadObject:
            return "Could not load selected photo"
        }
    }
}

private struct PhotoLibraryUncheckedImageBox: @unchecked Sendable {
    let image: UIImage
}

enum PhotoLibraryImageLoader {
    static func loadPreparedImage(
        from source: PhotoLibraryImageSource,
        maxDimension: CGFloat = 2048
    ) async throws -> UIImage {
        let image = try await loadUIImage(from: source)
        let box = PhotoLibraryUncheckedImageBox(image: image)
        return await Task.detached(priority: .userInitiated) {
            if PhotoUtilities.isPreparedForImport(box.image, maxDimension: maxDimension) {
                return box.image
            }
            return PhotoUtilities.prepareImportedImage(box.image, maxDimension: maxDimension)
        }.value
    }

    static func loadThumbnailImage(
        from source: PhotoLibraryImageSource,
        maxDimension: CGFloat = 320
    ) async throws -> UIImage {
        let image = try await loadUIImage(from: source)
        let box = PhotoLibraryUncheckedImageBox(image: image)
        return await Task.detached(priority: .utility) {
            PhotoUtilities.prepareImportedImage(box.image, maxDimension: maxDimension)
        }.value
    }

    static func fetchCreationDate(from source: PhotoLibraryImageSource) -> Date? {
        guard let identifier = source.assetIdentifier else { return nil }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return result.firstObject?.creationDate
    }

    private static func loadUIImage(from source: PhotoLibraryImageSource) async throws -> UIImage {
        guard source.itemProvider.canLoadObject(ofClass: UIImage.self) else {
            throw PhotoLibraryImageLoadError.unsupportedProvider
        }
        return try await withCheckedThrowingContinuation { continuation in
            source.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = object as? UIImage else {
                    continuation.resume(throwing: PhotoLibraryImageLoadError.failedToLoadObject)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
}

/// Wrapper dla PHPickerViewController umożliwiający wybór wielu zdjęć z biblioteki
struct MultiPhotoLibraryPicker: UIViewControllerRepresentable {

    @Environment(\.dismiss) private var dismiss
    /// Callback wywoływany po zakończeniu wyboru.
    /// Payload zawiera lekkie źródła obrazów (bez pre-decode), nil oznacza anulowanie.
    var onSelect: (MultiPhotoLibrarySelectionPayload?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0          // 0 = bez limitu
        config.filter = .images
        config.preferredAssetRepresentationMode = .compatible

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, PHPickerViewControllerDelegate {

        let parent: MultiPhotoLibraryPicker

        init(_ parent: MultiPhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let start = ContinuousClock.now

            // Anulowanie — dismiss natychmiast, nic do ładowania
            guard !results.isEmpty else {
                parent.dismiss()
                parent.onSelect(nil)
                return
            }

            let sources = results.enumerated().map { index, result in
                PhotoLibraryImageSource(
                    id: UUID(),
                    assetIdentifier: result.assetIdentifier,
                    itemProvider: result.itemProvider,
                    selectionIndex: index
                )
            }

            parent.onSelect(MultiPhotoLibrarySelectionPayload(sources: sources))
            parent.dismiss()

            let elapsed = start.duration(to: .now)
            let confirmToDismissMs = Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            AppLog.debug(
                "📸 MultiPhotoLibraryPicker: picked=\(results.count) pickerConfirmToDismissMs=\(confirmToDismissMs)"
            )
        }
    }
}
