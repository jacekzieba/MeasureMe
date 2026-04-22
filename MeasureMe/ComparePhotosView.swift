import SwiftUI
import SwiftData
import Photos
import ImageIO
import UniformTypeIdentifiers

// MARK: - Compare Mode

private enum CompareMode: String, CaseIterable, Identifiable {
    case slider
    case sideBySide
    case ghost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slider:    return AppLocalization.string("compare.mode.slider")
        case .sideBySide: return AppLocalization.string("compare.mode.sideBySide")
        case .ghost:     return AppLocalization.string("compare.mode.ghost")
        }
    }

    var icon: String {
        switch self {
        case .slider:    return "camera.metering.none"
        case .sideBySide: return "rectangle.split.2x1"
        case .ghost:     return "person.2.crop.square.stack"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .slider:
            return AppLocalization.string("accessibility.compare.mode.slider")
        case .sideBySide:
            return AppLocalization.string("accessibility.compare.mode.side")
        case .ghost:
            return AppLocalization.string("accessibility.compare.mode.ghost")
        }
    }

    var requiresPremium: Bool {
        self == .ghost
    }
}

/// Widok porównujący dwa zdjęcia obok siebie
struct ComparePhotosView: View {
    private let photosTheme = FeatureTheme.photos
    private let measurementsTheme = FeatureTheme.measurements
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var premiumStore: PremiumStore

    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    @State private var compareMode: CompareMode = .slider
    @State private var showSaveAlert = false
    @State private var saveMessage = ""
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showTransformationSheet = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    // Ghost overlay state
    @State private var ghostOpacity: Double = 0.5
    @State private var ghostOffset: CGSize = .zero
    @State private var ghostScale: CGFloat = 1.0
    @GestureState private var ghostDragOffset: CGSize = .zero
    @GestureState private var ghostPinchScale: CGFloat = 1.0
    @AppStorage("compare.ghostHintDismissed") private var ghostHintDismissed: Bool = false

    private var olderCompareCacheID: String {
        compareCacheID(for: olderPhoto)
    }

    private var newerCompareCacheID: String {
        compareCacheID(for: newerPhoto)
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(
                    topHeight: 280,
                    tint: photosTheme.strongTint,
                    showsSpotlight: true
                )

                GeometryReader { geometry in
                    ZStack {
                        compareModeContent(in: geometry)
                            .id(compareMode)
                            .transition(compareModeTransition)
                    }
                    .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate), value: compareMode)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                compareModeSelector
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            .navigationTitle(AppLocalization.string("Compare"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppColorRoles.surfaceChrome, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("photos.compare.done")
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isExporting {
                        ProgressView()
                    }

                    Button {
                        openTransformationCard()
                    } label: {
                        Image(systemName: "sparkles.rectangle.stack")
                    }
                    .accessibilityLabel(AppLocalization.string("transformation.card.share"))
                    .accessibilityIdentifier("photos.compare.transformation")

                    Button {
                        exportMergedComparison()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(isExporting)
                    .accessibilityLabel(AppLocalization.string("Export"))
                    .accessibilityIdentifier("photos.compare.export")
                }
            }
            .alert(AppLocalization.string("Export"), isPresented: $showSaveAlert) {
                Button(AppLocalization.string("OK"), role: .cancel) { }
            } message: {
                Text(saveMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showTransformationSheet) {
                TransformationCardPreviewSheet(
                    olderPhoto: olderPhoto,
                    newerPhoto: newerPhoto,
                    unitsSystem: unitsSystem
                )
            }
        }
    }

    private var compareModeSelector: some View {
        HStack(spacing: 6) {
            ForEach(CompareMode.allCases) { mode in
                compareModeButton(for: mode)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(AppColorRoles.surfaceChrome)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: [
                                    photosTheme.softTint.opacity(colorScheme == .dark ? 0.40 : 0.60),
                                    measurementsTheme.softTint.opacity(colorScheme == .dark ? 0.18 : 0.12),
                                    .clear
                                ],
                                colorScheme: colorScheme,
                                lightColor: AppColorRoles.surfaceSecondary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppColorRoles.borderStrong, lineWidth: 1)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .inset(by: 0.5)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.70), lineWidth: 0.6)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .zIndex(10)
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photos.compare.modePicker")
    }

    private func compareModeButton(for mode: CompareMode) -> some View {
        let isSelected = compareMode == mode

        return Button {
            guard !mode.requiresPremium || premiumStore.isPremium else {
                premiumStore.presentPaywall(reason: .feature("Ghost Photo Comparison"))
                return
            }
            withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
                compareMode = mode
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(mode.label)
                    .font(AppTypography.captionEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if mode.requiresPremium && !premiumStore.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? AppColorRoles.textOnAccent : AppColorRoles.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                ClaudeLightStyle.directionalGradient(
                                    colors: [
                                        photosTheme.accent.opacity(0.96),
                                        photosTheme.accent.opacity(0.78)
                                    ],
                                    colorScheme: colorScheme,
                                    lightColor: photosTheme.accent,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
                    .shadow(color: photosTheme.accent.opacity(isSelected ? 0.25 : 0), radius: 8, x: 0, y: 4)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("photos.compare.mode.\(mode.rawValue)")
    }

    @ViewBuilder
    private func compareModeContent(in geometry: GeometryProxy) -> some View {
        switch compareMode {
        case .slider:
            sliderComparisonView(in: geometry)
        case .sideBySide:
            sideBySideView(in: geometry)
        case .ghost:
            ghostOverlayView(in: geometry)
        }
    }

    private var compareModeTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .bottom))
    }
    
    // MARK: - Slider Comparison (date labels)
    @ViewBuilder
    private func sliderComparisonView(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            Text(AppLocalization.string("Drag to compare"))
                .font(AppTypography.headline)
                .foregroundStyle(AppColorRoles.textSecondary)
            
            BeforeAfterSlider(
                beforeImage: olderPhoto.imageData,
                afterImage: newerPhoto.imageData,
                beforeCacheID: olderCompareCacheID,
                afterCacheID: newerCompareCacheID,
                beforeDateLabel: olderPhoto.date.formatted(date: .abbreviated, time: .omitted),
                afterDateLabel: newerPhoto.date.formatted(date: .abbreviated, time: .omitted),
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
                        tint: photosTheme.softTint,
                        contentPadding: 10
                    ) {
                        VStack(spacing: 8) {
                            DownsampledImageView(
                                imageData: olderPhoto.imageData,
                                targetSize: CGSize(width: cardWidth, height: cardHeight),
                                contentMode: .fit,
                                cornerRadius: 12,
                                cacheID: olderCompareCacheID,
                                renderScaleOverride: compareSideBySideRenderScale
                            )
                            .frame(maxHeight: cardHeight)
                            
                            Text(olderPhoto.date.formatted(date: .abbreviated, time: .omitted))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                    
                    // Newer photo
                    AppGlassCard(
                        depth: .elevated,
                        cornerRadius: 16,
                        tint: photosTheme.strongTint,
                        contentPadding: 10
                    ) {
                        VStack(spacing: 8) {
                            DownsampledImageView(
                                imageData: newerPhoto.imageData,
                                targetSize: CGSize(width: cardWidth, height: cardHeight),
                                contentMode: .fit,
                                cornerRadius: 12,
                                cacheID: newerCompareCacheID,
                                renderScaleOverride: compareSideBySideRenderScale
                            )
                            .frame(maxHeight: cardHeight)
                            
                            Text(newerPhoto.date.formatted(date: .abbreviated, time: .omitted))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                }
                .padding(.horizontal)
                
                comparisonInfo
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Ghost Overlay View

    @ViewBuilder
    private func ghostOverlayView(in geometry: GeometryProxy) -> some View {
        let imageWidth = max(1, geometry.size.width - 40)
        let imageHeight = max(1, geometry.size.height * 0.55)
        let imageSize = CGSize(width: imageWidth, height: imageHeight)

        ScrollView {
            VStack(spacing: 12) {
                ZStack {
                    // Base layer: "before" (older) image
                    DownsampledImageView(
                        imageData: olderPhoto.imageData,
                        targetSize: imageSize,
                        contentMode: .fit,
                        cornerRadius: 12,
                        cacheID: olderCompareCacheID,
                        renderScaleOverride: compareSideBySideRenderScale
                    )
                    .frame(width: imageWidth, height: imageHeight)

                    // Overlay layer: "after" (newer) image
                    DownsampledImageView(
                        imageData: newerPhoto.imageData,
                        targetSize: imageSize,
                        contentMode: .fit,
                        cornerRadius: 0,
                        cacheID: newerCompareCacheID,
                        renderScaleOverride: compareSideBySideRenderScale
                    )
                    .frame(width: imageWidth, height: imageHeight)
                    .opacity(ghostOpacity)
                    .scaleEffect(ghostScale * ghostPinchScale)
                    .offset(
                        x: ghostOffset.width + ghostDragOffset.width,
                        y: ghostOffset.height + ghostDragOffset.height
                    )
                    .gesture(ghostDragGesture)
                    .gesture(ghostPinchGesture)
                    .accessibilityIdentifier("photos.compare.ghost.afterImage")

                    CompareAlignmentGrid()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        .allowsHitTesting(false)

                    // Date badges
                    VStack {
                        HStack {
                            dateBadge(olderPhoto.date)
                            Spacer()
                            dateBadge(newerPhoto.date)
                        }
                        .padding(12)
                        Spacer()
                    }
                }
                .frame(width: imageWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ghostControls

                comparisonInfo
            }
            .padding()
        }
    }

    @ViewBuilder
    private var ghostControls: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 16,
            tint: photosTheme.softTint,
            contentPadding: 12
        ) {
            VStack(spacing: 10) {
                if !ghostHintDismissed {
                    Button {
                        ghostHintDismissed = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.draw")
                                .font(.caption)
                                .foregroundStyle(photosTheme.accent)
                            Text(AppLocalization.string("compare.ghost.hint"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColorRoles.textSecondary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColorRoles.textSecondary.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(AppColorRoles.borderSubtle)
                }

                HStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    Slider(value: $ghostOpacity, in: 0...1)
                        .tint(.appAccent)
                        .accessibilityLabel(AppLocalization.string("accessibility.compare.ghost.opacity"))
                        .accessibilityValue("\(Int(ghostOpacity * 100))%")
                        .accessibilityIdentifier("photos.compare.ghost.opacity")

                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }

                HStack {
                    Text(AppLocalization.string("compare.ghost.opacity.label"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)

                    Spacer()

                    Text("\(Int(ghostOpacity * 100))%")
                        .font(AppTypography.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                }

                if ghostOffset != .zero || ghostScale != 1.0 {
                    Button {
                        resetGhostAlignment()
                    } label: {
                        Label(AppLocalization.string("Snap to center"), systemImage: "scope")
                            .font(AppTypography.captionEmphasis)
                    }
                    .buttonStyle(LiquidCapsuleButtonStyle(tint: photosTheme.accent))
                    .accessibilityIdentifier("photos.compare.ghost.reset")
                }
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func dateBadge(_ date: Date) -> some View {
        Text(date.formatted(date: .abbreviated, time: .omitted))
            .font(.caption)
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(AppColorRoles.textPrimary)
            .padding(8)
            .background(AppColorRoles.surfaceChrome.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: AppColorRoles.shadowSoft.opacity(0.45), radius: 10, x: 0, y: 4)
    }

    private var ghostDragGesture: some Gesture {
        DragGesture()
            .updating($ghostDragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                ghostOffset.width += value.translation.width
                ghostOffset.height += value.translation.height
                ghostHintDismissed = true
            }
    }

    private var ghostPinchGesture: some Gesture {
        MagnifyGesture()
            .updating($ghostPinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                ghostScale = MetricChange.clampedGhostScale(ghostScale, magnification: value.magnification)
                ghostHintDismissed = true
            }
    }

    private func resetGhostAlignment() {
        withAnimation(.easeInOut(duration: 0.3)) {
            ghostOffset = .zero
            ghostScale = 1.0
        }
    }

    // MARK: - Comparison Info
    @ViewBuilder
    private var comparisonInfo: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 18,
            tint: photosTheme.softTint,
            contentPadding: 14
        ) {
            VStack(spacing: 14) {
                // Time difference
                let daysDiff = Calendar.current.dateComponents([.day], from: olderPhoto.date, to: newerPhoto.date).day ?? 0
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(AppColorRoles.textSecondary)
                    Text(AppLocalization.plural("compare.days.apart", daysDiff))
                        .font(AppTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                
                // Metric changes
                if !metricChanges.isEmpty {
                    AppGlassCard(
                        depth: .base,
                        cornerRadius: 14,
                        tint: measurementsTheme.softTint,
                        contentPadding: 12
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppLocalization.string("Changes"))
                                .font(AppTypography.headlineEmphasis)
                                .foregroundStyle(AppColorRoles.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(metricChanges, id: \.kind) { change in
                                MetricChangeRow(change: change)
                            }
                        }
                    }
                }

                // Prominent share transformation button
                Button {
                    openTransformationCard()
                } label: {
                    Label(AppLocalization.string("transformation.card.share"), systemImage: "sparkles.rectangle.stack")
                        .font(AppTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppAccentButtonStyle())
                .accessibilityIdentifier("photos.compare.transformation.prominent")
            }
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Metric Changes
    private var metricChanges: [MetricChange] {
        MetricChange.changes(older: olderPhoto.linkedMetrics, newer: newerPhoto.linkedMetrics)
    }

    private var compareSideBySideRenderScale: CGFloat {
        max(UIScreen.main.scale * 2, 3)
    }

    private func compareCacheID(for photo: PhotoEntry) -> String {
        let modelID = String(describing: photo.persistentModelID)
        let sourceSignature = "\(photo.imageData.count)_\(UIImage.cacheKey(from: photo.imageData))"
        return "\(modelID)_compare_\(sourceSignature)"
    }
    
    // MARK: - Export
    
    private func exportMergedComparison() {
        guard premiumStore.isPremium else {
            premiumStore.presentPaywall(reason: .feature("Comparison Export"))
            return
        }

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

    private func openTransformationCard() {
        guard premiumStore.isPremium else {
            premiumStore.presentPaywall(reason: .feature("Transformation Card"))
            return
        }
        showTransformationSheet = true
    }
    
    private func performExport() {
        let olderData = olderPhoto.imageData
        let newerData = newerPhoto.imageData
        
        Task.detached(priority: .userInitiated) {
            let exportStart = ContinuousClock().now
            let mergedData = Self.mergeImagesHorizontallyJPEGData(leftData: olderData, rightData: newerData)
            let exportElapsed = exportStart.duration(to: ContinuousClock().now)
            let exportMs = Int(exportElapsed.components.seconds * 1_000)
                + Int(exportElapsed.components.attoseconds / 1_000_000_000_000_000)
            
            await MainActor.run {
                guard let mergedData,
                      let merged = UIImage(data: mergedData) else {
                    AppLog.debug("❌ ComparePhotosView: export_merge_failed in \(exportMs)ms")
                    saveMessage = AppLocalization.string("Failed to prepare the comparison image.")
                    showSaveAlert = true
                    isExporting = false
                    return
                }

                AppLog.debug("✅ ComparePhotosView: export_merge_ms=\(exportMs) output=\(PhotoUtilities.formatFileSize(mergedData.count))")
                
                ImageSaver.save(merged) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            saveMessage = AppLocalization.string("Saved to MeasureMe album.")
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
            guard let leftCG = downsampleForExportCGImage(from: leftData, maxDimension: 2048),
                  let rightCG = downsampleForExportCGImage(from: rightData, maxDimension: 2048) else {
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

    private nonisolated static func downsampleForExportCGImage(from data: Data, maxDimension: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary)
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

enum ImageSaveResult {
    case success
    case failure(String)
}

enum PhotoAlbumSaver {
    static let albumTitle = "MeasureMe"

    static func saveToMeasureMeAlbum(_ image: UIImage, completion: @escaping (ImageSaveResult) -> Void) {
        Task {
            do {
                let album = try await ensureAlbum()
                try await add(image: image, to: album)
                await MainActor.run {
                    completion(.success)
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error.localizedDescription))
                }
            }
        }
    }

    private static func ensureAlbum() async throws -> PHAssetCollection {
        if let existing = fetchAlbum() {
            return existing
        }

        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
            placeholder = request.placeholderForCreatedAssetCollection
        }

        guard let localIdentifier = placeholder?.localIdentifier else {
            throw AlbumError.creationFailed
        }

        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let created = collections.firstObject else {
            throw AlbumError.creationFailed
        }
        return created
    }

    private static func add(image: UIImage, to album: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            guard let placeholder = assetRequest.placeholderForCreatedAsset,
                  let albumRequest = PHAssetCollectionChangeRequest(for: album) else {
                return
            }
            albumRequest.addAssets([placeholder] as NSArray)
        }
    }

    private static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        return PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }

    private enum AlbumError: LocalizedError {
        case creationFailed

        var errorDescription: String? {
            AppLocalization.string("Could not create MeasureMe album.")
        }
    }
}

final class ImageSaver: NSObject {
    private static var activeSavers: [ImageSaver] = []
    private let completion: (ImageSaveResult) -> Void
    
    private init(completion: @escaping (ImageSaveResult) -> Void) {
        self.completion = completion
    }
    
    static func save(_ image: UIImage, completion: @escaping (ImageSaveResult) -> Void) {
        PhotoAlbumSaver.saveToMeasureMeAlbum(image, completion: completion)
    }

    static func saveLegacy(_ image: UIImage, completion: @escaping (ImageSaveResult) -> Void) {
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

private struct CompareAlignmentGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1...2 {
            let x = rect.minX + rect.width * CGFloat(index) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

            let y = rect.minY + rect.height * CGFloat(index) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

// MARK: - Metric Change Model
struct MetricChange {
    let kind: MetricKind
    let oldValue: Double
    let newValue: Double
    let difference: Double
    let storedUnit: String

    var percentageChange: Double? {
        guard oldValue != 0 else { return nil }
        return (difference / oldValue) * 100
    }

    /// Oblicza zmiany metryk między dwoma zestawami snapshotów.
    static func changes(
        older: [MetricValueSnapshot],
        newer: [MetricValueSnapshot]
    ) -> [MetricChange] {
        let olderMetrics = Dictionary(
            uniqueKeysWithValues: older.compactMap { snapshot -> (String, MetricValueSnapshot)? in
                guard let kind = snapshot.kind else { return nil }
                return (kind.rawValue, snapshot)
            }
        )
        let newerMetrics = Dictionary(
            uniqueKeysWithValues: newer.compactMap { snapshot -> (String, MetricValueSnapshot)? in
                guard let kind = snapshot.kind else { return nil }
                return (kind.rawValue, snapshot)
            }
        )

        var result: [MetricChange] = []
        for (kindRaw, newerSnapshot) in newerMetrics {
            if let olderSnapshot = olderMetrics[kindRaw],
               let kind = newerSnapshot.kind {
                let difference = newerSnapshot.value - olderSnapshot.value
                result.append(MetricChange(
                    kind: kind,
                    oldValue: olderSnapshot.value,
                    newValue: newerSnapshot.value,
                    difference: difference,
                    storedUnit: newerSnapshot.unit
                ))
            }
        }
        return result.sorted { $0.kind.title < $1.kind.title }
    }

    /// Clamp dla ghost pinch scale.
    static func clampedGhostScale(_ currentScale: CGFloat, magnification: CGFloat) -> CGFloat {
        min(max(currentScale * magnification, 0.5), 3.0)
    }
}

// MARK: - Metric Change Row
private struct MetricChangeRow: View {
    let change: MetricChange
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.kind.title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                
                HStack(spacing: 4) {
                    Text("\(displayValue(change.oldValue).formatted(.number.precision(.fractionLength(1)))) → \(displayValue(change.newValue).formatted(.number.precision(.fractionLength(1)))) \(displayUnit)")
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
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
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                    }
                } else {
                    Text(AppLocalization.string("No change"))
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
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
        // Dla wiekszosci metryk wzrost jest czerwony (niekorzystny), spadek zielony (korzystny)
        // Wyjatek: lean body mass, gdzie wzrost jest korzystny
        let isGoodIncrease = change.kind == .leanBodyMass
        
        if change.difference > 0 {
            return isGoodIncrease ? AppColorRoles.stateSuccess : AppColorRoles.stateError
        } else if change.difference < 0 {
            return isGoodIncrease ? AppColorRoles.stateError : AppColorRoles.stateSuccess
        } else {
            return AppColorRoles.textSecondary
        }
    }
}

// MARK: - Before/After Slider
private struct BeforeAfterSlider: View {
    let beforeImage: Data
    let afterImage: Data
    let beforeCacheID: String?
    let afterCacheID: String?
    let beforeDateLabel: String
    let afterDateLabel: String
    let size: CGSize
    
    @Environment(\.displayScale) private var displayScale
    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false
    
    // Wlasciwosc obliczana zapewniajaca poprawne wymiary
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
        max(effectiveScale * 2, 3)
    }
    
    // Cache dla obrazów - używamy ImageCache
    @State private var cachedBeforeImage: UIImage?
    @State private var cachedAfterImage: UIImage?
    
    private var bothImagesReady: Bool {
        cachedBeforeImage != nil && cachedAfterImage != nil
    }

    var body: some View {
        let clampedSlider = sliderPosition.isFinite ? min(max(sliderPosition, 0), 1) : 0.5

        ZStack {
            if bothImagesReady {
                // Obraz "po" (tlo po prawej stronie slidera)
                Image(uiImage: cachedAfterImage!)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: validSize.width, height: validSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Obraz "przed" (maska po lewej stronie slidera)
                Image(uiImage: cachedBeforeImage!)
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

                // Slider handle
                GeometryReader { geometry in
                    ZStack {
                        // Vertical line
                        Rectangle()
                            .fill(AppColorRoles.surfaceChrome)
                            .frame(width: isDragging ? 4 : 3)
                            .shadow(color: AppColorRoles.shadowSoft.opacity(0.4), radius: isDragging ? 8 : 5)

                        // Handle circle
                        Circle()
                            .fill(AppColorRoles.surfaceChrome)
                            .frame(width: isDragging ? 50 : 44, height: isDragging ? 50 : 44)
                            .shadow(color: AppColorRoles.shadowSoft.opacity(0.45), radius: isDragging ? 8 : 5)
                            .overlay(
                                Circle()
                                    .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                            )
                            .overlay {
                                HStack(spacing: isDragging ? 5 : 4) {
                                    Image(systemName: "chevron.left")
                                        .font(isDragging ? .caption : .caption2)
                                        .foregroundStyle(AppColorRoles.textTertiary)
                                    Image(systemName: "chevron.right")
                                        .font(isDragging ? .caption : .caption2)
                                        .foregroundStyle(AppColorRoles.textTertiary)
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
                    Text(beforeDateLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .padding(8)
                        .background(AppColorRoles.surfaceChrome.opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding()
                        .opacity(clampedSlider > 0.2 ? 1 : 0.3)

                    Spacer()

                    Text(afterDateLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .padding(8)
                        .background(AppColorRoles.surfaceChrome.opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding()
                        .opacity(clampedSlider < 0.8 ? 1 : 0.3)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // Placeholder while loading
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColorRoles.surfaceInteractive)
                    .frame(width: validSize.width, height: validSize.height)
                    .overlay {
                        ProgressView()
                            .tint(AppColorRoles.textSecondary)
                    }
            }
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
        let beforeBase = beforeCacheID ?? UIImage.cacheKey(from: beforeImage)
        let afterBase = afterCacheID ?? UIImage.cacheKey(from: afterImage)
        return "\(beforeBase)|\(afterBase)|\(widthPx)x\(heightPx)@\(compareRenderScale)"
    }
}
