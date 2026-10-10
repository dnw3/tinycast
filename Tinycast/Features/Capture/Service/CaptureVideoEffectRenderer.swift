import CoreImage
import CoreText
import Foundation

struct CaptureVideoEffectRenderer: Sendable {
    private struct Label: Sendable {
        let id: UUID
        let image: CIImage
    }

    private let effects: [CaptureVideoEffect]
    private let bounds: CGRect
    private let labels: [Label]

    nonisolated init(effects: [CaptureVideoEffect], size: CapturePixelSize) throws {
        self.effects = effects
        bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        var labels: [Label] = [], pixels = 0
        for effect in effects where effect.kind == .text {
            let rect = Self.rect(effect.rect, in: bounds).integral
            pixels += Int(rect.width * rect.height)
            guard pixels <= 8_000_000 else { throw Failure.textLimit }
            let image = CIImage(cgImage: try Self.text(effect.text, color: effect.color, size: rect.size))
                .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            labels.append(.init(id: effect.id, image: image))
        }
        self.labels = labels
    }

    nonisolated func image(_ source: CIImage, at time: Double) -> CIImage {
        let extent = source.extent
        var image = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: bounds.width / extent.width, y: bounds.height / extent.height))
        for effect in effects where effect.kind == .text && effect.contains(time) {
            if let label = labels.first(where: { $0.id == effect.id }) { image = label.image.composited(over: image) }
        }
        for effect in effects where effect.kind == .cover && effect.contains(time) {
            let components = effect.color.rgba
            let fill = CIImage(color: CIColor(red: components[0], green: components[1], blue: components[2]))
                .cropped(to: Self.rect(effect.rect, in: bounds).integral)
            image = fill.composited(over: image)
        }
        let viewport = Self.rect(CaptureVideoEffect.viewport(effects, at: time), in: bounds)
        return image.cropped(to: viewport)
            .transformed(by: CGAffineTransform(translationX: -viewport.minX, y: -viewport.minY))
            .transformed(by: CGAffineTransform(scaleX: bounds.width / viewport.width, y: bounds.height / viewport.height))
            .cropped(to: bounds)
    }

    nonisolated private static func rect(_ normalized: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: normalized.minX * bounds.width, y: (1 - normalized.maxY) * bounds.height,
            width: normalized.width * bounds.width, height: normalized.height * bounds.height)
    }

    nonisolated private static func text(_ text: String, color: CaptureColor, size: CGSize) throws -> CGImage {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        let foreground = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: color.rgba.map { CGFloat($0) })!
        func frame(_ fontSize: CGFloat) -> CTFrame {
            let attributes = [kCTFontAttributeName: CTFontCreateUIFontForLanguage(.system, fontSize, nil)!,
                kCTForegroundColorAttributeName: foreground] as CFDictionary
            let string = CFAttributedStringCreate(nil, text as CFString, attributes)!
            return CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(string), CFRange(),
                CGPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), transform: nil), nil)
        }
        var lower = CGFloat(6), upper = min(128, size.height * 0.85), result = frame(6)
        guard upper >= lower, CTFrameGetVisibleStringRange(result).length == text.utf16.count else { throw Failure.textLimit }
        for _ in 0..<10 {
            let fontSize = (lower + upper) / 2, candidate = frame(fontSize)
            if CTFrameGetVisibleStringRange(candidate).length == text.utf16.count {
                lower = fontSize; result = candidate
            } else { upper = fontSize }
        }
        CTFrameDraw(result, context)
        guard let image = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return image
    }

    enum Failure: LocalizedError {
        case textLimit
        var errorDescription: String? { "Shorten the video text or make its box larger." }
    }
}
