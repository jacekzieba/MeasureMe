import SwiftUI
import PhotosUI

/// Wrapper dla PHPickerViewController umożliwiający wybór wielu zdjęć z biblioteki
struct MultiPhotoLibraryPicker: UIViewControllerRepresentable {

    @Environment(\.dismiss) private var dismiss
    /// Callback wywoływany po zakończeniu wyboru z listą obrazów (może być pusta przy anulowaniu)
    var onSelect: ([UIImage]) -> Void

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
            // Anulowanie — dismiss natychmiast, nic do ładowania
            guard !results.isEmpty else {
                parent.dismiss()
                parent.onSelect([])
                return
            }

            // Załaduj obrazy asynchronicznie, zachowując kolejność wyboru.
            // WAŻNE: dismiss wywoływany PO onSelect — gwarantuje że callback z danymi
            // odpala się zanim SwiftUI uruchomi onDismiss i otworzy kolejny sheet.
            let group = DispatchGroup()
            var orderedImages: [Int: UIImage] = [:]
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage else { return }
                    let prepared = PhotoUtilities.prepareImportedImage(image, maxDimension: 2048)
                    lock.lock()
                    orderedImages[index] = prepared
                    lock.unlock()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                let sorted = orderedImages.sorted { $0.key < $1.key }.map(\.value)
                self.parent.onSelect(sorted)  // najpierw dane do rodzica
                self.parent.dismiss()          // potem dismiss → onDismiss widzi już payload
            }
        }
    }
}
