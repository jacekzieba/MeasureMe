import SwiftUI
import Photos
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

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
    private static var canReadPhotoLibraryMetadata: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

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

    static func fetchCreationDate(from source: PhotoLibraryImageSource) async -> Date? {
        if let metadataDate = await loadCreationDateFromProvider(source.itemProvider) {
            return metadataDate
        }

        guard let identifier = source.assetIdentifier else { return nil }
        guard canReadPhotoLibraryMetadata else { return nil }
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

    private static func loadCreationDateFromProvider(_ provider: NSItemProvider) async -> Date? {
        let typeIdentifier = UTType.image.identifier
        if let date = await loadCreationDateFromFileRepresentation(provider, typeIdentifier: typeIdentifier) {
            return date
        }
        if let date = await loadCreationDateFromDataRepresentation(provider, typeIdentifier: typeIdentifier) {
            return date
        }
        return nil
    }

    private static func loadCreationDateFromFileRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Date? {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: metadataCreationDate(fromFileURL: url))
            }
        }
    }

    private static func loadCreationDateFromDataRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Date? {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: metadataCreationDate(fromImageData: data))
            }
        }
    }

    private static func metadataCreationDate(fromFileURL fileURL: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return metadataCreationDate(from: source)
    }

    private static func metadataCreationDate(fromImageData imageData: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return metadataCreationDate(from: source)
    }

    private static func metadataCreationDate(from imageSource: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return metadataCreationDate(fromProperties: properties)
    }

    private static func metadataCreationDate(fromProperties properties: [CFString: Any]) -> Date? {
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               let parsed = parseExifDate(original) {
                return parsed
            }
            if let digitized = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
               let parsed = parseExifDate(digitized) {
                return parsed
            }
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let tiffDate = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let parsed = parseExifDate(tiffDate) {
            return parsed
        }

        return nil
    }

    private static func parseExifDate(_ rawValue: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let formats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: rawValue) {
                return parsed
            }
        }
        return nil
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
