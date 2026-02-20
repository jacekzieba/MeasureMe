import SwiftUI

/// Lekki widok, ktory zmniejsza duze dane obrazu przed dekodowaniem, aby ograniczyc zuzycie pamieci.
struct DownsampledImageView: View {
    let imageData: Data
    let targetSize: CGSize
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    var showsProgress: Bool = true
    var cacheID: String? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: cacheKey) {
            await loadImage()
        }
    }

    private var cacheKey: String {
        let base = cacheID ?? UIImage.cacheKey(from: imageData)
        let width = Int(max(targetSize.width * displayScale, 1))
        let height = Int(max(targetSize.height * displayScale, 1))
        return "\(base)_downsample_\(width)x\(height)"
    }

    @MainActor
    private func loadImage() async {
        let renderStart = ContinuousClock().now
        image = await ImagePipeline.downsampledImage(
            imageData: imageData,
            cacheKey: cacheKey,
            targetSize: targetSize,
            scale: displayScale
        )
        let renderElapsed = renderStart.duration(to: ContinuousClock().now)
        let renderMs = Int(renderElapsed.components.seconds * 1_000)
            + Int(renderElapsed.components.attoseconds / 1_000_000_000_000_000)
        let targetPixels = Int(targetSize.width * displayScale) * Int(targetSize.height * displayScale)
        AppLog.debug("🖼️ DownsampledImageView: render=\(renderMs)ms source=\(PhotoUtilities.formatFileSize(imageData.count)) targetPixels=\(targetPixels)")
    }

    @ViewBuilder
    private var placeholder: some View {
        Color.gray.opacity(0.2)
            .overlay {
                if showsProgress {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
    }
}
