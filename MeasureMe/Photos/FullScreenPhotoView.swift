import SwiftUI

/// Pełnoekranowy widok zdjęcia z możliwością zoomowania i przesuwania
struct FullScreenPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data
    var cacheID: String? = nil
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                DownsampledImageView(
                    imageData: imageData,
                    targetSize: geo.size,
                    contentMode: .fit,
                    cornerRadius: 0,
                    cacheID: cacheID
                )
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .gesture(dragGesture)
                .onTapGesture(count: 2) {
                    if scale > 1.0 {
                        resetZoom()
                    } else {
                        scale = 2.0
                    }
                }
            }
            
            closeButton
        }
    }
    
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.iconHero)
                        .foregroundStyle(.white)
                        .shadow(radius: 5)
                }
                .accessibilityLabel(AppLocalization.string("Close"))
                .padding()
            }
            Spacer()
        }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 1.0), 5.0)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.0 {
                    resetZoom()
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1.0 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private func resetZoom() {
        scale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

#Preview {
    let sampleImage = UIImage(systemName: "photo.fill")!
    let imageData = sampleImage.pngData()!
    
    return FullScreenPhotoView(imageData: imageData)
}
