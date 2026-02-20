import SwiftUI
import UIKit

/// Widok miniatury wielokrotnego uzytku oparty o wspolny pipeline downsamplingu i cache.
struct PhotoThumbnailView: View {
    let imageData: Data
    let size: CGFloat
    var cacheID: String? = nil

    var body: some View {
        DownsampledImageView(
            imageData: imageData,
            targetSize: CGSize(width: size, height: size),
            contentMode: .fill,
            cornerRadius: 12,
            showsProgress: false,
            cacheID: cacheID
        )
        .frame(width: size, height: size)
    }
}

#Preview {
    let data = UIImage(systemName: "photo.fill")?.pngData() ?? Data()
    return PhotoThumbnailView(imageData: data, size: 110, cacheID: "preview")
        .padding()
        .background(Color.black)
}
