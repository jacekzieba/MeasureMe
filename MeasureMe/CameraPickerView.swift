import SwiftUI
import UIKit

/// Wrapper dla UIImagePickerController z kamerą
struct CameraPickerView: UIViewControllerRepresentable {
    
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        
        // Sprawdź czy kamera jest dostępna (symulator nie ma kamery!)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.allowsEditing = false
        } else {
            // Zapasowo przejdz do biblioteki na symulatorze
            picker.sourceType = .photoLibrary
        }
        
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Nic nie trzeba aktualizować
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        
        let parent: CameraPickerView
        
        init(_ parent: CameraPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let imageURL = info[.imageURL] as? URL
            let originalImage = info[.originalImage] as? UIImage

            DispatchQueue.global(qos: .userInitiated).async {
                let preparedImage: UIImage? = {
                    if let imageURL,
                       let downsampled = PhotoUtilities.downsampledImage(from: imageURL, maxDimension: 2048) {
                        if PhotoUtilities.isPreparedForImport(downsampled, maxDimension: 2048) {
                            return downsampled
                        }
                        return PhotoUtilities.prepareImportedImage(downsampled, maxDimension: 2048)
                    }

                    if let originalImage {
                        if PhotoUtilities.isPreparedForImport(originalImage, maxDimension: 2048) {
                            return originalImage
                        }
                        return PhotoUtilities.prepareImportedImage(originalImage, maxDimension: 2048)
                    }

                    return nil
                }()

                DispatchQueue.main.async {
                    self.parent.selectedImage = preparedImage
                    self.parent.dismiss()
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Wrapper dla UIImagePickerController z galerią
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Nic nie trzeba aktualizować
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        
        let parent: PhotoLibraryPicker
        
        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let imageURL = info[.imageURL] as? URL
            let originalImage = info[.originalImage] as? UIImage

            DispatchQueue.global(qos: .userInitiated).async {
                let preparedImage: UIImage? = {
                    if let imageURL,
                       let downsampled = PhotoUtilities.downsampledImage(from: imageURL, maxDimension: 2048) {
                        if PhotoUtilities.isPreparedForImport(downsampled, maxDimension: 2048) {
                            return downsampled
                        }
                        return PhotoUtilities.prepareImportedImage(downsampled, maxDimension: 2048)
                    }

                    if let originalImage {
                        if PhotoUtilities.isPreparedForImport(originalImage, maxDimension: 2048) {
                            return originalImage
                        }
                        return PhotoUtilities.prepareImportedImage(originalImage, maxDimension: 2048)
                    }

                    return nil
                }()

                DispatchQueue.main.async {
                    self.parent.selectedImage = preparedImage
                    self.parent.dismiss()
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
