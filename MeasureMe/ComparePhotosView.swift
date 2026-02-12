import SwiftUI
import SwiftData
import Photos
import ImageIO
import UniformTypeIdentifiers

/// Widok porównujący dwa zdjęcia obok siebie
struct ComparePhotosView: View {
    @Environment(\.dismiss) private var dismiss
    
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry
    
    @State private var showSlider = true
    @State private var showSaveAlert = false
    @State private var saveMessage = ""
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                GeometryReader { geometry in
                    if showSlider {
                        sliderComparisonView(in: geometry)
                    } else {
                        sideBySideView(in: geometry)
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Compare"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isExporting {
                        ProgressView()
                    }
                    Button {
                        exportMergedComparison()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(isExporting)
                    .accessibilityLabel(AppLocalization.string("Export comparison image"))
                    
                    Button {
                        showSlider.toggle()
                    } label: {
                        Image(systemName: showSlider ? "rectangle.split.2x1" : "camera.metering.none")
                    }
                    .accessibilityLabel(showSlider
                        ? AppLocalization.string("accessibility.compare.mode.side")
                        : AppLocalization.string("accessibility.compare.mode.slider"))
                }
            }
            .alert(AppLocalization.string("Export"), isPresented: $showSaveAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(saveMessage)
            }
        }
    }
    
    // MARK: - Slider Comparison (Then/Now)
    @ViewBuilder
    private func sliderComparisonView(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            Text(AppLocalization.string("Drag to compare"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
            
            BeforeAfterSlider(
                beforeImage: olderPhoto.imageData,
                afterImage: newerPhoto.imageData,
                beforeCacheID: String(describing: olderPhoto.id),
                afterCacheID: String(describing: newerPhoto.id),
                size: CGSize(
                    width: max(1, geometry.size.width - 40),
                    height: max(1, geometry.size.height * 0.6)
                )
            )
            
            comparisonInfo
        }
        .padding()
    }
    
    // MARK: - Side by Side View
    @ViewBuilder
    private func sideBySideView(in geometry: GeometryProxy) -> some View {
        let cardWidth = max((geometry.size.width - 44) / 2, 1)
        let cardHeight = max(geometry.size.height * 0.4, 1)

        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    // Older photo
                    AppGlassCard(
                        depth: .elevated,
                        cornerRadius: 16,
                        tint: Color.appAccent.opacity(0.14),
                        contentPadding: 10
                    ) {
                        VStack(spacing: 8) {
                            DownsampledImageView(
                                imageData: olderPhoto.imageData,
                                targetSize: CGSize(width: cardWidth, height: cardHeight),
                                contentMode: .fit,
                                cornerRadius: 12,
                                cacheID: String(describing: olderPhoto.id)
                            )
                            .frame(maxHeight: cardHeight)
                            
                            VStack(spacing: 4) {
                            Text(AppLocalization.string("Then"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(olderPhoto.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.62))
                            }
                        }
                    }
                    
                    // Newer photo
                    AppGlassCard(
                        depth: .elevated,
                        cornerRadius: 16,
                        tint: Color.cyan.opacity(0.14),
                        contentPadding: 10
                    ) {
                        VStack(spacing: 8) {
                            DownsampledImageView(
                                imageData: newerPhoto.imageData,
                                targetSize: CGSize(width: cardWidth, height: cardHeight),
                                contentMode: .fit,
                                cornerRadius: 12,
                                cacheID: String(describing: newerPhoto.id)
                            )
                            .frame(maxHeight: cardHeight)
                            
                            VStack(spacing: 4) {
                            Text(AppLocalization.string("Now"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(newerPhoto.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.62))
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                comparisonInfo
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Comparison Info
    @ViewBuilder
    private var comparisonInfo: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 18,
            tint: Color.cyan.opacity(0.14),
            contentPadding: 14
        ) {
            VStack(spacing: 14) {
                // Time difference
                let daysDiff = Calendar.current.dateComponents([.day], from: olderPhoto.date, to: newerPhoto.date).day ?? 0
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.white.opacity(0.76))
                    Text(AppLocalization.plural("compare.days.apart", daysDiff))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.84))
                }
                
                // Metric changes
                if !metricChanges.isEmpty {
                    AppGlassCard(
                        depth: .base,
                        cornerRadius: 14,
                        tint: Color.appAccent.opacity(0.12),
                        contentPadding: 12
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppLocalization.string("Changes"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(metricChanges, id: \.kind) { change in
                                MetricChangeRow(change: change)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Metric Changes
    private var metricChanges: [MetricChange] {
        var changes: [MetricChange] = []
        
        // Get all metrics from both photos
        let olderMetrics = Dictionary(uniqueKeysWithValues: olderPhoto.linkedMetrics.compactMap { snapshot -> (String, MetricValueSnapshot)? in
            guard let kind = snapshot.kind else { return nil }
            return (kind.rawValue, snapshot)
        })
        
        let newerMetrics = Dictionary(uniqueKeysWithValues: newerPhoto.linkedMetrics.compactMap { snapshot -> (String, MetricValueSnapshot)? in
            guard let kind = snapshot.kind else { return nil }
            return (kind.rawValue, snapshot)
        })
        
        // Find common metrics and calculate changes
        for (kindRaw, newerSnapshot) in newerMetrics {
            if let olderSnapshot = olderMetrics[kindRaw],
               let kind = newerSnapshot.kind {
                let difference = newerSnapshot.value - olderSnapshot.value
                changes.append(MetricChange(
                    kind: kind,
                    oldValue: olderSnapshot.value,
                    newValue: newerSnapshot.value,
                    difference: difference,
                    storedUnit: newerSnapshot.unit
                ))
            }
        }
        
        return changes.sorted { $0.kind.title < $1.kind.title }
    }
    
    // MARK: - Export
    
    private func exportMergedComparison() {
        guard !isExporting else { return }
        isExporting = true
        
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        performExport()
                    } else {
                        saveMessage = AppLocalization.string("Photo access denied. Enable Photos access in Settings to save.")
                        showSaveAlert = true
                        isExporting = false
                    }
                }
            }
            return
        }
        
        guard status == .authorized || status == .limited else {
            saveMessage = AppLocalization.string("Photo access denied. Enable Photos access in Settings to save.")
            showSaveAlert = true
            isExporting = false
            return
        }
        
        performExport()
    }
    
    private func performExport() {
        let olderData = olderPhoto.imageData
        let newerData = newerPhoto.imageData
        
        Task.detached(priority: .userInitiated) {
            let mergedData = Self.mergeImagesHorizontallyJPEGData(leftData: olderData, rightData: newerData)
            
            await MainActor.run {
                guard let mergedData,
                      let merged = UIImage(data: mergedData) else {
                    saveMessage = AppLocalization.string("Failed to prepare the comparison image.")
                    showSaveAlert = true
                    isExporting = false
                    return
                }
                
                ImageSaver.save(merged) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            saveMessage = AppLocalization.string("Saved to Photos.")
                        case .failure(let message):
                            saveMessage = message
                        }
                        showSaveAlert = true
                        isExporting = false
                    }
                }
            }
        }
    }
    
    private nonisolated static func mergeImagesHorizontallyJPEGData(leftData: Data, rightData: Data) -> Data? {
        autoreleasepool {
            guard let leftSource = CGImageSourceCreateWithData(leftData as CFData, nil),
                  let rightSource = CGImageSourceCreateWithData(rightData as CFData, nil),
                  let leftCG = CGImageSourceCreateImageAtIndex(leftSource, 0, nil),
                  let rightCG = CGImageSourceCreateImageAtIndex(rightSource, 0, nil) else {
                return nil
            }
            
            let leftHeight = CGFloat(leftCG.height)
            let rightHeight = CGFloat(rightCG.height)
            let targetHeight = min(leftHeight, rightHeight)
            guard targetHeight > 0 else { return nil }
            
            let leftScale = targetHeight / leftHeight
            let rightScale = targetHeight / rightHeight
            
            let leftWidth = CGFloat(leftCG.width) * leftScale
            let rightWidth = CGFloat(rightCG.width) * rightScale
            
            let canvasWidth = leftWidth + rightWidth
            let canvasHeight = targetHeight
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: Int(canvasWidth),
                height: Int(canvasHeight),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            
            context.interpolationQuality = .high
            
            let leftRect = CGRect(x: 0, y: 0, width: leftWidth, height: canvasHeight)
            let rightRect = CGRect(x: leftWidth, y: 0, width: rightWidth, height: canvasHeight)
            
            context.draw(leftCG, in: leftRect)
            context.draw(rightCG, in: rightRect)
            
            guard let mergedCG = context.makeImage() else { return nil }
            return jpegData(from: mergedCG, quality: 0.95)
        }
    }

    private nonisolated static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - Image Saver

private enum ImageSaveResult {
    case success
    case failure(String)
}

private final class ImageSaver: NSObject {
    private static var activeSavers: [ImageSaver] = []
    private let completion: (ImageSaveResult) -> Void
    
    private init(completion: @escaping (ImageSaveResult) -> Void) {
        self.completion = completion
    }
    
    static func save(_ image: UIImage, completion: @escaping (ImageSaveResult) -> Void) {
        let saver = ImageSaver(completion: completion)
        activeSavers.append(saver)
        UIImageWriteToSavedPhotosAlbum(
            image,
            saver,
            #selector(ImageSaver.saveCompleted(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }
    
    @objc
    private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error {
            completion(.failure(error.localizedDescription))
        } else {
            completion(.success)
        }
        Self.activeSavers.removeAll { $0 === self }
    }
}

// MARK: - Metric Change Model
private struct MetricChange {
    let kind: MetricKind
    let oldValue: Double
    let newValue: Double
    let difference: Double
    let storedUnit: String
    
    var percentageChange: Double? {
        guard oldValue != 0 else { return nil }
        return (difference / oldValue) * 100
    }
}

// MARK: - Metric Change Row
private struct MetricChangeRow: View {
    let change: MetricChange
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.kind.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    Text("\(displayValue(change.oldValue).formatted(.number.precision(.fractionLength(1)))) → \(displayValue(change.newValue).formatted(.number.precision(.fractionLength(1)))) \(displayUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                if change.difference != 0 {
                    Image(systemName: change.difference > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption)
                        .foregroundStyle(changeColor)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(abs(displayValue(change.difference)).formatted(.number.precision(.fractionLength(1)))) \(displayUnit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(changeColor)
                        
                        if let percentage = change.percentageChange {
                            Text("\(abs(percentage).formatted(.number.precision(.fractionLength(1))))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(AppLocalization.string("No change"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var isMetricStored: Bool {
        change.storedUnit == change.kind.unitSymbol(unitsSystem: "metric")
    }

    private var displayUnit: String {
        isMetricStored ? change.kind.unitSymbol(unitsSystem: unitsSystem) : change.storedUnit
    }

    private func displayValue(_ value: Double) -> Double {
        isMetricStored ? change.kind.valueForDisplay(fromMetric: value, unitsSystem: unitsSystem) : value
    }
    
    private var changeColor: Color {
        // For most metrics, increase is red (bad), decrease is green (good)
        // Exception: lean body mass where increase is good
        let isGoodIncrease = change.kind == .leanBodyMass
        
        if change.difference > 0 {
            return isGoodIncrease ? .green : .red
        } else if change.difference < 0 {
            return isGoodIncrease ? .red : .green
        } else {
            return .secondary
        }
    }
}

// MARK: - Before/After Slider
private struct BeforeAfterSlider: View {
    let beforeImage: Data
    let afterImage: Data
    let beforeCacheID: String?
    let afterCacheID: String?
    let size: CGSize
    
    @Environment(\.displayScale) private var displayScale
    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false
    
    // Computed property to ensure valid dimensions
    private var validSize: CGSize {
        let validWidth = size.width.isFinite && size.width > 0 ? size.width : 300
        let validHeight = size.height.isFinite && size.height > 0 ? size.height : 300
        return CGSize(
            width: max(1, validWidth),
            height: max(1, validHeight)
        )
    }

    private var effectiveScale: CGFloat {
        max(displayScale, 1)
    }

    private var compareRenderScale: CGFloat {
        effectiveScale * 1.5
    }
    
    // Cache dla obrazów - używamy ImageCache
    @State private var cachedBeforeImage: UIImage?
    @State private var cachedAfterImage: UIImage?
    
    var body: some View {
        let clampedSlider = sliderPosition.isFinite ? min(max(sliderPosition, 0), 1) : 0.5

        ZStack {
            // Before image (background) - z cache
            if let beforeUIImage = cachedBeforeImage {
                Image(uiImage: beforeUIImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: validSize.width, height: validSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Color(.systemGray5)
                    .frame(width: validSize.width, height: validSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // After image (masked) - z cache
            if let afterUIImage = cachedAfterImage {
                Image(uiImage: afterUIImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: validSize.width, height: validSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .mask {
                        Rectangle()
                            .frame(width: validSize.width * clampedSlider)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
            }
            
            // Slider handle
            GeometryReader { geometry in
                ZStack {
                    // Vertical line
                    Rectangle()
                        .fill(.white)
                        .frame(width: isDragging ? 4 : 3)
                        .shadow(radius: isDragging ? 8 : 5)
                    
                    // Handle circle
                    Circle()
                        .fill(.white)
                        .frame(width: isDragging ? 50 : 44, height: isDragging ? 50 : 44)
                        .shadow(radius: isDragging ? 8 : 5)
                        .overlay {
                            HStack(spacing: isDragging ? 5 : 4) {
                                Image(systemName: "chevron.left")
                                    .font(isDragging ? .caption : .caption2)
                                    .foregroundStyle(.gray)
                                Image(systemName: "chevron.right")
                                    .font(isDragging ? .caption : .caption2)
                                    .foregroundStyle(.gray)
                            }
                        }
                }
                .frame(maxHeight: .infinity)
                .position(x: validSize.width * clampedSlider, y: geometry.size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                            
                            let newPosition = value.location.x / max(validSize.width, 1)
                            guard newPosition.isFinite else { return }
                            sliderPosition = min(max(newPosition, 0), 1)
                        }
                        .onEnded { _ in
                            isDragging = false
                            
                            // Snap do środka jeśli blisko
                            if abs(sliderPosition - 0.5) < 0.05 {
                                sliderPosition = 0.5
                            }
                        }
                )
            }
            
            // Labels
            HStack {
                Text(AppLocalization.string("Then"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding()
                    .opacity(clampedSlider > 0.2 ? 1 : 0.3)
                
                Spacer()
                
                Text(AppLocalization.string("Now"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding()
                    .opacity(clampedSlider < 0.8 ? 1 : 0.3)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: validSize.width, height: validSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: cacheLoadKey) {
            await loadImages()
        }
    }
    
    // MARK: - Image Loading
    
    @MainActor
    private func loadImages() async {
        let targetSize = validSize
        let scale = compareRenderScale
        let widthPx = Int(max(targetSize.width * scale, 1))
        let heightPx = Int(max(targetSize.height * scale, 1))
        let beforeBase = beforeCacheID ?? UIImage.cacheKey(from: beforeImage)
        let afterBase = afterCacheID ?? UIImage.cacheKey(from: afterImage)
        let beforeKey = "\(beforeBase)_slider_\(widthPx)x\(heightPx)"
        let afterKey = "\(afterBase)_slider_\(widthPx)x\(heightPx)"

        cachedBeforeImage = await ImagePipeline.downsampledImage(
            imageData: beforeImage,
            cacheKey: beforeKey,
            targetSize: targetSize,
            scale: scale
        )

        cachedAfterImage = await ImagePipeline.downsampledImage(
            imageData: afterImage,
            cacheKey: afterKey,
            targetSize: targetSize,
            scale: scale
        )
    }

    private var cacheLoadKey: String {
        let widthPx = Int(max(validSize.width * compareRenderScale, 1))
        let heightPx = Int(max(validSize.height * compareRenderScale, 1))
        return "\(widthPx)x\(heightPx)@\(compareRenderScale)"
    }
}
