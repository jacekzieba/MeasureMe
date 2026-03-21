import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

// MARK: - Aspect Ratio

enum CardAspectRatio: String, CaseIterable, Sendable {
    case story
    case square

    nonisolated var width: Int { 1080 }

    nonisolated var height: Int {
        switch self {
        case .story: 1920
        case .square: 1080
        }
    }

    var label: String {
        switch self {
        case .story: localizedString("transformation.card.ratio.story")
        case .square: localizedString("transformation.card.ratio.square")
        }
    }

    var iconName: String {
        switch self {
        case .story: "rectangle.portrait"
        case .square: "square"
        }
    }

    private func localizedString(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

// MARK: - Input

struct TransformationCardInput: Sendable {
    let olderImageData: Data
    let newerImageData: Data
    let olderDate: Date
    let newerDate: Date
    let weightOld: Double?
    let weightNew: Double?
    let unitsSystem: String
    var aspectRatio: CardAspectRatio = .story
}

// MARK: - Renderer

nonisolated enum TransformationCardRenderer {

    private static let inkR: CGFloat = 5 / 255
    private static let inkG: CGFloat = 8 / 255
    private static let inkB: CGFloat = 22 / 255
    private static let amberR: CGFloat = 252 / 255
    private static let amberG: CGFloat = 163 / 255
    private static let amberB: CGFloat = 17 / 255
    private static let fogR: CGFloat = 198 / 255
    private static let fogG: CGFloat = 208 / 255
    private static let fogB: CGFloat = 225 / 255

    nonisolated static func render(_ input: TransformationCardInput) -> Data? {
        autoreleasepool { () -> Data? in
            let w = input.aspectRatio.width
            let h = input.aspectRatio.height
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            guard let ctx = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            ctx.interpolationQuality = .high

            switch input.aspectRatio {
            case .story:
                drawStoryLayout(ctx: ctx, input: input, w: w, h: h)
            case .square:
                drawSquareLayout(ctx: ctx, input: input, w: w, h: h)
            }

            guard let cgImage = ctx.makeImage() else { return nil }
            return jpegData(from: cgImage, quality: 0.95)
        }
    }

    // MARK: - Story Layout (9:16 — 1080×1920)

    private static func drawStoryLayout(ctx: CGContext, input: TransformationCardInput, w: Int, h: Int) {
        let cw = CGFloat(w)
        let ch = CGFloat(h)
        let hasWeight = input.weightOld != nil && input.weightNew != nil

        // Background
        ctx.setFillColor(red: inkR, green: inkG, blue: inkB, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // --- Measure content height to center vertically ---
        let titleH: CGFloat = 60
        let gapTitlePhotos: CGFloat = 36
        let photoW: CGFloat = cw - 80
        let photoGap: CGFloat = 24
        let photoH: CGFloat = 680
        let gapPhotosWeight: CGFloat = hasWeight ? 40 : 0
        let weightBlockH: CGFloat = hasWeight ? 80 : 0
        let gapWeightBrand: CGFloat = 36
        let brandH: CGFloat = 56

        let totalContentH = titleH + gapTitlePhotos
            + photoH + photoGap + photoH
            + gapPhotosWeight + weightBlockH
            + gapWeightBrand + brandH

        let topY = ch - (ch - totalContentH) / 2

        // Title
        let titleText = localizedString("transformation.card.title")
        let titleY = topY - titleH
        drawCenteredText(titleText, y: titleY, fontSize: 52, weight: .heavy,
                         color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, canvasWidth: cw)

        // Photos — stacked vertically (dates are on pills, no separate date line)
        let photoX: CGFloat = 40
        let photo1Y = titleY - gapTitlePhotos - photoH
        let photo2Y = photo1Y - photoGap - photoH

        let topRect = CGRect(x: photoX, y: photo1Y, width: photoW, height: photoH)
        let bottomRect = CGRect(x: photoX, y: photo2Y, width: photoW, height: photoH)

        if let img = downsampleCGImage(from: input.olderImageData, maxDimension: Int(max(photoW, photoH))) {
            drawRoundedRectImage(in: ctx, image: img, rect: topRect, cornerRadius: 20)
        }
        if let img = downsampleCGImage(from: input.newerImageData, maxDimension: Int(max(photoW, photoH))) {
            drawRoundedRectImage(in: ctx, image: img, rect: bottomRect, cornerRadius: 20)
        }

        // Then/Now pills with dates
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none

        drawPill(localizedString("transformation.card.before"), subtitle: dateFmt.string(from: input.olderDate),
                 in: ctx, photoRect: topRect, fontSize: 20)
        drawPill(localizedString("transformation.card.after"), subtitle: dateFmt.string(from: input.newerDate),
                 in: ctx, photoRect: bottomRect, fontSize: 20)

        // Weight section
        var nextY = photo2Y - gapPhotosWeight
        if hasWeight, let weightOld = input.weightOld, let weightNew = input.weightNew {
            nextY = drawWeightSection(ctx: ctx, cw: cw, y: nextY, weightOld: weightOld, weightNew: weightNew,
                                      unitsSystem: input.unitsSystem, weightFontSize: 34, barWidth: 660, barHeight: 28, percentFontSize: 22)
        }

        // Branding at bottom
        let brandingY = nextY - gapWeightBrand
        drawBranding(ctx: ctx, cw: cw, y: brandingY, fontSize: 34)
    }

    // MARK: - Square Layout (1:1 — 1080×1080)

    private static func drawSquareLayout(ctx: CGContext, input: TransformationCardInput, w: Int, h: Int) {
        let cw = CGFloat(w)
        let ch = CGFloat(h)
        let hasWeight = input.weightOld != nil && input.weightNew != nil

        // Background
        ctx.setFillColor(red: inkR, green: inkG, blue: inkB, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // --- Measure content to center vertically ---
        let titleH: CGFloat = 48
        let gapTitlePhotos: CGFloat = 24
        let photoSize: CGFloat = hasWeight ? 440 : 460
        let photoGap: CGFloat = 20
        let gapPhotosBottom: CGFloat = hasWeight ? 28 : 16
        let weightBlockH: CGFloat = hasWeight ? 70 : 0
        let gapBottomBrand: CGFloat = 24
        let brandH: CGFloat = 44

        let totalContentH = titleH + gapTitlePhotos + photoSize
            + gapPhotosBottom + weightBlockH + gapBottomBrand + brandH

        let topY = ch - (ch - totalContentH) / 2

        // Title
        let titleText = localizedString("transformation.card.title")
        let titleY = topY - titleH
        drawCenteredText(titleText, y: titleY, fontSize: 40, weight: .heavy,
                         color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, canvasWidth: cw)

        // Photos side by side
        let totalPhotosWidth = photoSize * 2 + CGFloat(photoGap)
        let photosX = (cw - totalPhotosWidth) / 2
        let photosTopY = titleY - gapTitlePhotos - photoSize

        let leftRect = CGRect(x: photosX, y: photosTopY, width: photoSize, height: photoSize)
        let rightRect = CGRect(x: photosX + photoSize + CGFloat(photoGap), y: photosTopY, width: photoSize, height: photoSize)

        if let leftCG = downsampleCGImage(from: input.olderImageData, maxDimension: Int(photoSize)) {
            drawRoundedRectImage(in: ctx, image: leftCG, rect: leftRect, cornerRadius: 16)
        }
        if let rightCG = downsampleCGImage(from: input.newerImageData, maxDimension: Int(photoSize)) {
            drawRoundedRectImage(in: ctx, image: rightCG, rect: rightRect, cornerRadius: 16)
        }

        // Then/Now pills with dates
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .none

        drawPill(localizedString("transformation.card.before"), subtitle: dateFmt.string(from: input.olderDate),
                 in: ctx, photoRect: leftRect, fontSize: 16)
        drawPill(localizedString("transformation.card.after"), subtitle: dateFmt.string(from: input.newerDate),
                 in: ctx, photoRect: rightRect, fontSize: 16)

        // Weight section (dates are already on pills, no separate date line)
        var nextY = photosTopY - gapPhotosBottom
        if hasWeight, let weightOld = input.weightOld, let weightNew = input.weightNew {
            nextY = drawWeightSection(ctx: ctx, cw: cw, y: nextY, weightOld: weightOld, weightNew: weightNew,
                                      unitsSystem: input.unitsSystem, weightFontSize: 28, barWidth: 600, barHeight: 24, percentFontSize: 18)
        }

        // Branding at bottom
        let brandingY = nextY - gapBottomBrand
        drawBranding(ctx: ctx, cw: cw, y: brandingY, fontSize: 26)
    }

    // MARK: - Shared Drawing Sections

    private static func drawBranding(ctx: CGContext, cw: CGFloat, y: CGFloat, fontSize: CGFloat) {
        let iconSize: CGFloat = fontSize * 1.4

        let textStr = "MeasureMe"
        let brandFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let roundedDesc = brandFont.fontDescriptor.withDesign(.rounded) ?? brandFont.fontDescriptor
        let roundedFont = UIFont(descriptor: roundedDesc, size: fontSize)
        let amberUIColor = UIColor(red: amberR, green: amberG, blue: amberB, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont,
            .foregroundColor: amberUIColor
        ]
        let attrStr = NSAttributedString(string: textStr, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Try BrandMark first, then AppIcon as fallback
        let brandImage = UIImage(named: "BrandMark") ?? UIImage(named: "AppIcon")
        let hasIcon = brandImage?.cgImage != nil
        let gap: CGFloat = hasIcon ? fontSize * 0.35 : 0
        let iconW: CGFloat = hasIcon ? iconSize : 0
        let totalW = iconW + gap + textBounds.width
        let startX = (cw - totalW) / 2

        // Draw icon centered on y
        if let iconCG = brandImage?.cgImage {
            let iconY = y - iconSize / 2
            let iconRect = CGRect(x: startX, y: iconY, width: iconSize, height: iconSize)
            // BrandMark is a circle, no rounding needed
            ctx.saveGState()
            ctx.addPath(CGPath(ellipseIn: iconRect, transform: nil))
            ctx.clip()
            ctx.draw(iconCG, in: iconRect)
            ctx.restoreGState()
        }

        // Text centered vertically with icon
        let textX = startX + iconW + gap
        let textY = y - textBounds.height / 2 - textBounds.origin.y
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    @discardableResult
    private static func drawWeightSection(ctx: CGContext, cw: CGFloat, y: CGFloat,
                                          weightOld: Double, weightNew: Double, unitsSystem: String,
                                          weightFontSize: CGFloat, barWidth: CGFloat,
                                          barHeight: CGFloat, percentFontSize: CGFloat) -> CGFloat {
        var nextY = y
        let oldDisplay = MetricKind.weight.valueForDisplay(fromMetric: weightOld, unitsSystem: unitsSystem)
        let newDisplay = MetricKind.weight.valueForDisplay(fromMetric: weightNew, unitsSystem: unitsSystem)
        let unitSymbol = MetricKind.weight.unitSymbol(unitsSystem: unitsSystem)

        let weightText = "\(formatWeight(oldDisplay)) \(unitSymbol)  →  \(formatWeight(newDisplay)) \(unitSymbol)"
        drawCenteredText(weightText, y: nextY, fontSize: weightFontSize, weight: .bold,
                         color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, canvasWidth: cw)
        nextY -= (weightFontSize + 14)

        // Progress bar
        let barX = (cw - barWidth) / 2
        let barRadius = barHeight / 2

        ctx.saveGState()
        let barBgRect = CGRect(x: barX, y: nextY - barHeight, width: barWidth, height: barHeight)
        let barBgPath = CGPath(roundedRect: barBgRect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
        ctx.addPath(barBgPath)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.1)
        ctx.fillPath()
        ctx.restoreGState()

        let percentChange = weightOld != 0 ? abs((weightNew - weightOld) / weightOld) : 0
        let fillFraction = min(max(percentChange, 0), 1)
        let fillWidth = barWidth * CGFloat(fillFraction)
        if fillWidth > 0 {
            ctx.saveGState()
            let fillRect = CGRect(x: barX, y: nextY - barHeight, width: fillWidth, height: barHeight)
            let fillPath = CGPath(roundedRect: fillRect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
            ctx.addPath(fillPath)
            ctx.setFillColor(red: amberR, green: amberG, blue: amberB, alpha: 1)
            ctx.fillPath()
            ctx.restoreGState()
        }

        let percentValue = weightOld != 0 ? ((weightNew - weightOld) / weightOld) * 100 : 0
        let sign = percentValue > 0 ? "+" : ""
        let percentText = "\(sign)\(formatWeight(percentValue))%"
        let percentX = barX + barWidth + 16
        drawText(percentText, x: percentX, y: nextY - barHeight + 2, fontSize: percentFontSize,
                 weight: .semibold, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx)

        return nextY - barHeight - 30
    }

    private static func drawDateRange(ctx: CGContext, cw: CGFloat, y: CGFloat, olderDate: Date, newerDate: Date, fontSize: CGFloat) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let dateText = "\(dateFormatter.string(from: olderDate))  →  \(dateFormatter.string(from: newerDate))"
        let fogColor = CGColor(red: fogR, green: fogG, blue: fogB, alpha: 1)
        drawCenteredText(dateText, y: y, fontSize: fontSize, weight: .medium, color: fogColor, in: ctx, canvasWidth: cw)
    }

    // MARK: - Drawing Helpers

    private static func drawRoundedRectImage(in ctx: CGContext, image: CGImage, rect: CGRect, cornerRadius: CGFloat) {
        ctx.saveGState()

        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let scale = max(rect.width / imgW, rect.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = rect.midX - drawW / 2
        let drawY = rect.midY - drawH / 2
        ctx.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        ctx.restoreGState()
    }

    private static func drawPill(_ text: String, subtitle: String? = nil, in ctx: CGContext, photoRect: CGRect, fontSize: CGFloat = 16) {
        let font = CTFontCreateWithName("SFProRounded-Bold" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Measure subtitle if present
        let subFont = CTFontCreateWithName("SFProRounded-Medium" as CFString, fontSize * 0.9, nil)
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: UIColor(white: 1, alpha: 0.8)
        ]
        var subLine: CTLine?
        var subBounds = CGRect.zero
        if let subtitle {
            let subAttrStr = NSAttributedString(string: subtitle, attributes: subAttrs)
            subLine = CTLineCreateWithAttributedString(subAttrStr)
            subBounds = CTLineGetBoundsWithOptions(subLine!, .useOpticalBounds)
        }

        let hPad: CGFloat = fontSize * 1.2
        let pillW = max(textBounds.width, subBounds.width) + hPad * 2
        let lineGap: CGFloat = subtitle != nil ? 4 : 0
        let pillH: CGFloat = subtitle != nil
            ? textBounds.height + subBounds.height + lineGap + fontSize * 0.9
            : textBounds.height + fontSize * 0.8
        let pillX = photoRect.midX - pillW / 2
        let pillY = photoRect.minY + fontSize * 0.8

        // Pill background
        ctx.saveGState()
        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH * 0.3, cornerHeight: pillH * 0.3, transform: nil)
        ctx.addPath(pillPath)
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.65)
        ctx.fillPath()
        ctx.restoreGState()

        if subtitle != nil, let subLine {
            // Two lines: title on top, subtitle below
            let titleX = pillX + (pillW - textBounds.width) / 2
            let subX = pillX + (pillW - subBounds.width) / 2

            let titleBaseY = pillY + subBounds.height + lineGap + (pillH - textBounds.height - subBounds.height - lineGap) / 2 - textBounds.origin.y
            let subBaseY = pillY + (pillH - textBounds.height - subBounds.height - lineGap) / 2 - subBounds.origin.y

            ctx.saveGState()
            ctx.textPosition = CGPoint(x: titleX, y: titleBaseY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()

            ctx.saveGState()
            ctx.textPosition = CGPoint(x: subX, y: subBaseY)
            CTLineDraw(subLine, ctx)
            ctx.restoreGState()
        } else {
            // Single line
            let textX = pillX + (pillW - textBounds.width) / 2
            let textY = pillY + (pillH - textBounds.height) / 2 - textBounds.origin.y
            ctx.saveGState()
            ctx.textPosition = CGPoint(x: textX, y: textY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }

    private static func drawCenteredText(
        _ text: String,
        y: CGFloat,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        color: CGColor,
        in ctx: CGContext,
        canvasWidth: CGFloat
    ) {
        let uiFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let roundedDesc = uiFont.fontDescriptor.withDesign(.rounded) ?? uiFont.fontDescriptor
        let roundedFont = UIFont(descriptor: roundedDesc, size: fontSize)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont,
            .foregroundColor: UIColor(cgColor: color)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let textX = (canvasWidth - textBounds.width) / 2
        let textY = y - textBounds.origin.y

        ctx.saveGState()
        ctx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        color: CGColor,
        in ctx: CGContext
    ) {
        let uiFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let roundedDesc = uiFont.fontDescriptor.withDesign(.rounded) ?? uiFont.fontDescriptor
        let roundedFont = UIFont(descriptor: roundedDesc, size: fontSize)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont,
            .foregroundColor: UIColor(cgColor: color)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)

        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Image Utilities

    private nonisolated static func downsampleCGImage(from data: Data, maxDimension: Int) -> CGImage? {
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

    // MARK: - Formatting Helpers

    private static func formatWeight(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        if formatted.hasSuffix(".0") {
            return String(formatted.dropLast(2))
        }
        return formatted
    }

    /// Resolves the localization bundle without touching any MainActor-isolated state.
    /// Mirrors AppLanguage.bundle logic inline so this nonisolated enum can call it freely.
    private static var currentBundle: Bundle {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if raw == "en" || raw == "pl",
           let path = Bundle.main.path(forResource: raw, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private static func localizedString(_ key: String) -> String {
        let bundle = currentBundle
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func localizedPlural(_ key: String, _ count: Int) -> String {
        let bundle = currentBundle
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String.localizedStringWithFormat(format, count)
    }
}
