import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

// MARK: - Input

struct TransformationCardInput: Sendable {
    let olderImageData: Data
    let newerImageData: Data
    let olderDate: Date
    let newerDate: Date
    let weightOld: Double?
    let weightNew: Double?
    let unitsSystem: String
}

// MARK: - Renderer

enum TransformationCardRenderer {

    private static let canvasSize = 1080
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
            let size = canvasSize
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            guard let ctx = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            ctx.interpolationQuality = .high

            let hasWeight = input.weightOld != nil && input.weightNew != nil
            let photoSize: Int = hasWeight ? 480 : 500

            // 1. Background
            ctx.setFillColor(red: inkR, green: inkG, blue: inkB, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Compute layout (origin is bottom-left in CG)
            let days = max(Calendar.current.dateComponents([.day], from: input.olderDate, to: input.newerDate).day ?? 0, 0)

            // 2. Title "MY TRANSFORMATION"
            let titleText = localizedString("transformation.card.title")
            let titleY: CGFloat
            if hasWeight {
                titleY = CGFloat(size) - 60
            } else {
                titleY = CGFloat(size) - 70
            }
            drawCenteredText(titleText, y: titleY, fontSize: 36, weight: .bold, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, canvasWidth: CGFloat(size))

            // 3. Days count
            let daysText: String
            if days == 0 {
                daysText = localizedString("transformation.card.days.zero")
            } else {
                daysText = localizedPlural("transformation.card.days", days)
            }
            let daysY = titleY - 46
            let amberColor = CGColor(red: amberR, green: amberG, blue: amberB, alpha: 1)
            drawCenteredText(daysText, y: daysY, fontSize: 22, weight: .bold, color: amberColor, in: ctx, canvasWidth: CGFloat(size))

            // 4. Photos
            let photoGap = 20
            let totalPhotosWidth = photoSize * 2 + photoGap
            let photosX = (size - totalPhotosWidth) / 2
            let photosTopY: CGFloat
            if hasWeight {
                photosTopY = daysY - 30 - CGFloat(photoSize)
            } else {
                photosTopY = daysY - 40 - CGFloat(photoSize)
            }

            let leftRect = CGRect(x: CGFloat(photosX), y: photosTopY, width: CGFloat(photoSize), height: CGFloat(photoSize))
            let rightRect = CGRect(x: CGFloat(photosX + photoSize + photoGap), y: photosTopY, width: CGFloat(photoSize), height: CGFloat(photoSize))

            if let leftCG = downsampleCGImage(from: input.olderImageData, maxDimension: photoSize) {
                drawRoundedRectImage(in: ctx, image: leftCG, rect: leftRect, cornerRadius: 16)
            }
            if let rightCG = downsampleCGImage(from: input.newerImageData, maxDimension: photoSize) {
                drawRoundedRectImage(in: ctx, image: rightCG, rect: rightRect, cornerRadius: 16)
            }

            // 5. Before/After pills on photos
            let beforeText = localizedString("transformation.card.before")
            let afterText = localizedString("transformation.card.after")
            drawPill(beforeText, in: ctx, photoRect: leftRect)
            drawPill(afterText, in: ctx, photoRect: rightRect)

            // 6. Weight stats + progress bar
            var nextY = photosTopY - 30
            if hasWeight, let weightOld = input.weightOld, let weightNew = input.weightNew {
                let oldDisplay = MetricKind.weight.valueForDisplay(fromMetric: weightOld, unitsSystem: input.unitsSystem)
                let newDisplay = MetricKind.weight.valueForDisplay(fromMetric: weightNew, unitsSystem: input.unitsSystem)
                let unitSymbol = MetricKind.weight.unitSymbol(unitsSystem: input.unitsSystem)

                let weightText = "\(formatWeight(oldDisplay)) \(unitSymbol)  →  \(formatWeight(newDisplay)) \(unitSymbol)"
                drawCenteredText(weightText, y: nextY, fontSize: 28, weight: .bold, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx, canvasWidth: CGFloat(size))
                nextY -= 40

                // Progress bar
                let barWidth: CGFloat = 600
                let barHeight: CGFloat = 24
                let barX = (CGFloat(size) - barWidth) / 2
                let barRadius: CGFloat = 12

                // Background
                ctx.saveGState()
                let barBgRect = CGRect(x: barX, y: nextY - barHeight, width: barWidth, height: barHeight)
                let barBgPath = CGPath(roundedRect: barBgRect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
                ctx.addPath(barBgPath)
                ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.1)
                ctx.fillPath()
                ctx.restoreGState()

                // Fill
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

                // Percentage label
                let percentValue = weightOld != 0 ? ((weightNew - weightOld) / weightOld) * 100 : 0
                let sign = percentValue > 0 ? "+" : ""
                let percentText = "\(sign)\(formatWeight(percentValue))%"
                let percentX = barX + barWidth + 16
                drawText(percentText, x: percentX, y: nextY - barHeight + 2, fontSize: 18, weight: .semibold, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), in: ctx)

                nextY -= (barHeight + 30)
            }

            // 7. Date range
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            let olderDateStr = dateFormatter.string(from: input.olderDate)
            let newerDateStr = dateFormatter.string(from: input.newerDate)
            let dateText = "\(olderDateStr)  →  \(newerDateStr)"
            let fogColor = CGColor(red: fogR, green: fogG, blue: fogB, alpha: 1)
            drawCenteredText(dateText, y: nextY, fontSize: 18, weight: .regular, color: fogColor, in: ctx, canvasWidth: CGFloat(size))

            // 8. Watermark
            let watermarkColor = CGColor(red: fogR, green: fogG, blue: fogB, alpha: 0.4)
            drawCenteredText("MeasureMe", y: 30, fontSize: 14, weight: .regular, color: watermarkColor, in: ctx, canvasWidth: CGFloat(size))

            // 9. Finalize
            guard let cgImage = ctx.makeImage() else { return nil }
            return jpegData(from: cgImage, quality: 0.95)
        }
    }

    // MARK: - Drawing Helpers

    private static func drawRoundedRectImage(in ctx: CGContext, image: CGImage, rect: CGRect, cornerRadius: CGFloat) {
        ctx.saveGState()

        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        // Center-crop (aspect fill)
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

    private static func drawPill(_ text: String, in ctx: CGContext, photoRect: CGRect) {
        let font = CTFontCreateWithName("SFProRounded-Bold" as CFString, 16, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let pillW = textBounds.width + 24
        let pillH: CGFloat = 30
        let pillX = photoRect.midX - pillW / 2
        let pillY = photoRect.minY + 14

        // Pill background
        ctx.saveGState()
        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)
        ctx.addPath(pillPath)
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        ctx.fillPath()
        ctx.restoreGState()

        // Pill text
        ctx.saveGState()
        let textX = pillX + (pillW - textBounds.width) / 2
        let textY = pillY + (pillH - textBounds.height) / 2 - textBounds.origin.y
        ctx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
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

    private static func localizedString(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private static func localizedPlural(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString(key, comment: ""), count)
    }
}
