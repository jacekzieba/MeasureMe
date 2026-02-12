import SwiftUI
import SwiftData

/// Pojedynczy wiersz zdjęcia w liście
struct PhotoRowView: View {
    let photo: PhotoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Zdjęcie
            PhotoRowImage(
                imageData: photo.imageData,
                cacheID: String(describing: photo.id),
                height: 300
            )
            
            // Informacje
            PhotoMetadataView(photo: photo)
        }
        .modifier(PhotoCardStyle())
    }
}

// MARK: - Photo Metadata View

/// Widok metadanych zdjęcia (data, tagi, metryki)
private struct PhotoMetadataView: View {
    let photo: PhotoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Data
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                
                Text(photo.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            // Tagi
            if !photo.tags.isEmpty {
                PhotoTagsScrollView(tags: photo.tags)
            }
            
            // Metryki
            if !photo.linkedMetrics.isEmpty {
                PhotoMetricsLabel(count: photo.linkedMetrics.count)
            }
        }
    }
}

// MARK: - Photo Tags Scroll View

/// Przewijalna lista tagów
private struct PhotoTagsScrollView: View {
    let tags: [PhotoTag]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag.title)
                        .modifier(PhotoTagStyle())
                }
            }
        }
    }
}

// MARK: - Photo Metrics Label

/// Label pokazujący liczbę powiązanych metryk
private struct PhotoMetricsLabel: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            
            Text(AppLocalization.plural("photo.metrics.recorded", count))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - View Modifiers

/// Styl dla karty zdjęcia
struct PhotoCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#14213D").opacity(0.4),
                        Color(hex: "#000000")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#FCA311").opacity(0.2), lineWidth: 1)
            )
    }
}

/// Styl dla tagu zdjęcia
struct PhotoTagStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#FCA311").opacity(0.2))
            .foregroundStyle(Color(hex: "#FCA311"))
            .clipShape(Capsule())
    }
}

// MARK: - Row Image (Downsampled)

private struct PhotoRowImage: View {
    let imageData: Data
    let cacheID: String
    let height: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            DownsampledImageView(
                imageData: imageData,
                targetSize: CGSize(width: max(geo.size.width, 1), height: height),
                contentMode: .fill,
                cornerRadius: 12,
                cacheID: cacheID
            )
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview("Photo Row") {
    let photo = PhotoEntry(
        imageData: UIImage(systemName: "photo.fill")?.pngData() ?? Data(),
        date: .now,
        tags: [.wholeBody, .chest],
        linkedMetrics: []
    )
    
    PhotoRowView(photo: photo)
        .padding()
        .background(Color.black)
}
