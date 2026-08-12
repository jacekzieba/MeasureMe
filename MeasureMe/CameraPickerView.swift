import SwiftUI
import UIKit
import AVFoundation
import Combine

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

struct GuidedCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImage: UIImage?
    @Binding var selectedPose: PhotoTag?
    let overlayCandidates: [PhotoTag: Data]

    @AppStorage("photos.overlayPose") private var storedOverlayPose: String = ""
    @AppStorage("photos.overlayOpacity") private var storedOverlayOpacity: Double = CameraOverlayOpacity.defaultValue

    @StateObject private var camera = GuidedCameraController()

    private var activePose: PhotoTag? {
        CameraOverlayPose.resolve(storedValue: storedOverlayPose)
    }

    private var overlayOpacity: Double {
        CameraOverlayOpacity.clamped(storedOverlayOpacity)
    }

    private var overlayImage: UIImage? {
        guard let activePose, let data = overlayCandidates[activePose] else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        ZStack {
            GuidedCameraPreview(session: camera.session)
                .ignoresSafeArea()

            if let overlayImage {
                Image(uiImage: overlayImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(overlayOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            GuidedCameraGrid()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.45))

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 14) {
                    if let hintText {
                        Text(hintText)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.smmd)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }

                    if activePose != nil {
                        opacitySlider
                    }

                    poseBar

                    Button {
                        selectedPose = activePose
                        camera.capture()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 62, height: 62)
                        }
                    }
                    .disabled(camera.isCapturing)
                    .accessibilityIdentifier("photos.guidedCamera.capture")
                    .accessibilityLabel(AppLocalization.string("Take Photo"))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 32)
            }
        }
        .background(Color.black)
        .task {
            await camera.requestAndStart()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            selectedImage = image
            dismiss()
        }
        .overlay {
            if let errorMessage = camera.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button(AppLocalization.string("Close")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(AppSpacing.lg)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
    }

    private var hintText: String? {
        guard let activePose else { return nil }
        if overlayCandidates[activePose] != nil {
            return AppLocalization.string("Match your last pose")
        }
        return AppLocalization.string("camera.overlay.noPhotoForPose")
    }

    private var opacitySlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Slider(
                value: Binding(
                    get: { overlayOpacity },
                    set: { storedOverlayOpacity = CameraOverlayOpacity.clamped($0) }
                ),
                in: CameraOverlayOpacity.range
            )
            .tint(.white)
            .accessibilityIdentifier("photos.guidedCamera.opacity")
            .accessibilityLabel(AppLocalization.string("camera.overlay.opacity"))

            Text(CameraOverlayOpacity.percentLabel(for: overlayOpacity))
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.45), in: Capsule())
        .padding(.horizontal, 24)
    }

    private var poseBar: some View {
        HStack(spacing: 6) {
            poseButton(title: AppLocalization.string("camera.overlay.off"), pose: nil)
            ForEach(CameraOverlayPose.selectable) { pose in
                poseButton(title: pose.title, pose: pose)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.45), in: Capsule())
    }

    private func poseButton(title: String, pose: PhotoTag?) -> some View {
        let isSelected = activePose == pose
        return Button {
            storedOverlayPose = pose?.rawValue ?? ""
        } label: {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photos.guidedCamera.pose.\(pose?.rawValue ?? "off")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct GuidedCameraGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let thirdWidth = rect.width / 3
        let thirdHeight = rect.height / 3

        for index in 1...2 {
            let x = CGFloat(index) * thirdWidth
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

            let y = CGFloat(index) * thirdHeight
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        return path
    }
}

private struct GuidedCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }
}

private final class GuidedCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?
    @Published var isCapturing = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "measureme.guided-camera")
    private var isConfigured = false

    func requestAndStart() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = AppLocalization.string("Camera is unavailable on this device.")
            return
        }

        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }

        guard granted else {
            errorMessage = AppLocalization.string("Camera permission is required to take a photo.")
            return
        }

        queue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.errorMessage = error.localizedDescription
                self.isCapturing = false
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.errorMessage = AppLocalization.string("Could not prepare photo. Please try again.")
                self.isCapturing = false
            }
            return
        }

        Task { @MainActor in
            self.capturedImage = PhotoUtilities.prepareImportedImage(image, maxDimension: 2048)
            self.isCapturing = false
        }
    }

    private func configureAndStart() {
        guard !session.isRunning else { return }
        if !isConfigured {
            session.beginConfiguration()
            session.sessionPreset = .photo

            defer {
                session.commitConfiguration()
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input),
                  session.canAddOutput(output) else {
                Task { @MainActor in
                    self.errorMessage = AppLocalization.string("Camera could not be started.")
                }
                return
            }

            session.addInput(input)
            session.addOutput(output)
            isConfigured = true
        }

        session.startRunning()
    }
}
