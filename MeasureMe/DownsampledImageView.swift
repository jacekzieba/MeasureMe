import SwiftUI

/// Lightweight image view that downscales large image data before decoding to reduce memory pressure.
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
        image = await ImagePipeline.downsampledImage(
            imageData: imageData,
            cacheKey: cacheKey,
            targetSize: targetSize,
            scale: displayScale
        )
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
