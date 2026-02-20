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
            if let imageURL = info[.imageURL] as? URL,
               let image = PhotoUtilities.downsampledImage(from: imageURL, maxDimension: 2048) {
                parent.selectedImage = PhotoUtilities.prepareImportedImage(image, maxDimension: 2048)
            } else if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = PhotoUtilities.prepareImportedImage(image, maxDimension: 2048)
            }
            parent.dismiss()
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
            if let imageURL = info[.imageURL] as? URL,
               let image = PhotoUtilities.downsampledImage(from: imageURL, maxDimension: 2048) {
                parent.selectedImage = PhotoUtilities.prepareImportedImage(image, maxDimension: 2048)
            } else if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = PhotoUtilities.prepareImportedImage(image, maxDimension: 2048)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
