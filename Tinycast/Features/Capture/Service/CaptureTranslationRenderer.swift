import CoreGraphics
import CoreText
import Foundation

enum CaptureTranslationRenderer {
    nonisolated static func validate(_ translation: CaptureTranslation) throws {
        guard translation.isValid else { throw Failure.layout }
        for block in translation.blocks where block.included { _ = try frame(block) }
    }

    nonisolated static func draw(_ translation: CaptureTranslation?, in context: CGContext) throws {
        guard let translation, translation.enabled else { return }
        for block in translation.blocks where block.included && context.boundingBoxOfClipPath.intersects(block.rect) {
            let visible = context.boundingBoxOfClipPath.intersection(block.rect).integral
            let reflection = block.reflection ?? .init()
            let sample = reflection.rect(visible, in: block.rect).integral
            let image = try image(block, sample: sample)
            context.saveGState()
            context.clip(to: block.rect)
            context.translateBy(x: block.rect.midX, y: block.rect.midY)
            context.scaleBy(x: reflection.horizontal ? -1 : 1, y: reflection.vertical ? -1 : 1)
            context.translateBy(x: -block.rect.midX + sample.minX, y: -block.rect.midY + sample.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: sample.size))
            context.restoreGState()
        }
    }

    nonisolated private static func image(_ block: CaptureTranslation.Block, sample: CGRect) throws -> CGImage {
        guard CaptureGeometry.valid(sample), sample.width * sample.height <= 4_194_304,
            let context = CGContext(data: nil, width: Int(sample.width), height: Int(sample.height),
                bitsPerComponent: 8, bytesPerRow: Int(sample.width) * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        context.translateBy(x: -sample.minX, y: sample.height + sample.minY)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: block.background.rgba.map { CGFloat($0) })!)
        context.fill(block.rect)
        context.translateBy(x: block.rect.minX, y: block.rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(try frame(block), context)
        guard let image = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return image
    }

    nonisolated private static func frame(_ block: CaptureTranslation.Block) throws -> CTFrame {
        let luminance = Double(block.background.red) * 0.2126
            + Double(block.background.green) * 0.7152 + Double(block.background.blue) * 0.0722
        let color = CGColor(gray: luminance > 140 ? 0 : 1, alpha: 1)
        func make(_ size: CGFloat) -> CTFrame {
            let attributes = [kCTFontAttributeName: CTFontCreateUIFontForLanguage(.system, size, nil)!,
                kCTForegroundColorAttributeName: color] as CFDictionary
            let string = CFAttributedStringCreate(nil, block.text as CFString, attributes)!
            let setter = CTFramesetterCreateWithAttributedString(string)
            let bounds = CGRect(origin: .zero, size: block.rect.size).insetBy(dx: 1, dy: 1)
            return CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: bounds, transform: nil), nil)
        }
        var lower = CGFloat(6), upper = min(64, block.rect.height * 0.85)
        var result = make(lower)
        guard upper >= lower, CTFrameGetVisibleStringRange(result).length == block.text.utf16.count
        else { throw Failure.layout }
        for _ in 0..<10 {
            let size = (lower + upper) / 2, candidate = make(size)
            if CTFrameGetVisibleStringRange(candidate).length == block.text.utf16.count {
                lower = size; result = candidate
            } else { upper = size }
        }
        return result
    }

    enum Failure: LocalizedError {
        case layout
        var errorDescription: String? { "A translation is too long for its paragraph. Shorten it, or use the text panel." }
    }
}
