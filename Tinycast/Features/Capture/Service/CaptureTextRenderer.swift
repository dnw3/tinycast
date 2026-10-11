import CoreGraphics
import CoreText
import Foundation

enum CaptureTextRenderer {
    nonisolated static func font(_ style: CaptureTextStyle) -> CTFont {
        let base = CaptureAnnotationRenderer.textFont(style.font, size: style.size)
        var traits: CTFontSymbolicTraits = []
        if style.bold { traits.insert(.boldTrait) }
        if style.italic { traits.insert(.italicTrait) }
        return CTFontCreateCopyWithSymbolicTraits(base, 0, nil, traits, [.boldTrait, .italicTrait]) ?? base
    }

    nonisolated static func string(_ text: String, format: CaptureTextFormat) -> CFAttributedString {
        let result = CFAttributedStringCreateMutable(nil, 0)!
        CFAttributedStringReplaceString(result, CFRange(), text as CFString)
        CFAttributedStringSetAttributes(result, CFRange(location: 0, length: text.utf16.count),
            attributes(format.base), false)
        for run in format.runs {
            CFAttributedStringSetAttributes(result, CFRange(location: run.location, length: run.length),
                attributes(run.style), true)
        }
        return result
    }

    nonisolated static func draw(_ annotation: CaptureAnnotation, in context: CGContext) {
        guard let format = annotation.textFormat else { return }
        let bounds = annotation.drawingBounds
        let setter = CTFramesetterCreateWithAttributedString(string(annotation.text, format: format))
        let frame = CTFramesetterCreateFrame(setter, CFRange(),
            CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil), nil)
        if annotation.reflection?.horizontal == true || annotation.reflection?.vertical == true {
            reflected(frame, bounds: bounds, format: format, in: context)
        } else { draw(frame, bounds: bounds, format: format, in: context) }
    }

    nonisolated private static func draw(
        _ frame: CTFrame, bounds: CGRect, format: CaptureTextFormat, in context: CGContext
    ) {
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        decorations(frame, format: format, strike: false, in: context)
        CTFrameDraw(frame, context)
        decorations(frame, format: format, strike: true, in: context)
        context.restoreGState()
    }

    nonisolated private static func reflected(
        _ frame: CTFrame, bounds: CGRect, format: CaptureTextFormat, in context: CGContext
    ) {
        let visible = bounds.intersection(context.boundingBoxOfClipPath).integral
        guard CaptureGeometry.valid(visible) else { return }
        for y in stride(from: Int(visible.minY), to: Int(visible.maxY), by: 512) {
            for x in stride(from: Int(visible.minX), to: Int(visible.maxX), by: 512) {
                autoreleasepool {
                    let tile = CGRect(x: x, y: y, width: min(512, Int(visible.maxX) - x),
                        height: min(512, Int(visible.maxY) - y))
                    let sample = tile.insetBy(dx: -1, dy: -1)
                    guard let bitmap = CGContext(data: nil, width: Int(sample.width), height: Int(sample.height),
                        bitsPerComponent: 8, bytesPerRow: Int(sample.width) * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return }
                    bitmap.translateBy(x: -sample.minX, y: sample.maxY)
                    bitmap.scaleBy(x: 1, y: -1)
                    draw(frame, bounds: bounds, format: format, in: bitmap)
                    guard let image = bitmap.makeImage() else { return }
                    context.saveGState()
                    context.clip(to: tile)
                    context.interpolationQuality = .none
                    context.translateBy(x: sample.minX, y: sample.maxY)
                    context.scaleBy(x: 1, y: -1)
                    context.draw(image, in: CGRect(origin: .zero, size: sample.size))
                    context.restoreGState()
                }
            }
        }
    }

    nonisolated private static func attributes(_ style: CaptureTextStyle) -> CFDictionary {
        var alignment: CTTextAlignment = switch style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        let paragraph = withUnsafePointer(to: &alignment) { value in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                value: value)
            return CTParagraphStyleCreate(&setting, 1)
        }
        var attributes: [CFString: Any] = [kCTFontAttributeName: font(style),
            kCTForegroundColorAttributeName: color(style.color), kCTParagraphStyleAttributeName: paragraph,
            kCTUnderlineStyleAttributeName: style.underline ? 1 : 0,
            "TinycastStrike" as CFString: style.strikethrough,
            "TinycastBackground" as CFString: style.background?.hex ?? ""]
        if let outline = style.outline {
            attributes[kCTStrokeColorAttributeName] = color(outline)
            attributes[kCTStrokeWidthAttributeName] = -style.outlineWidth
        }
        return attributes as CFDictionary
    }

    nonisolated private static func color(_ value: CaptureColor) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: value.rgba.map { CGFloat($0) })!
    }

    nonisolated private static func decorations(
        _ frame: CTFrame, format: CaptureTextFormat, strike: Bool, in context: CGContext
    ) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine] else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        for (index, line) in lines.enumerated() {
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                let style = format.style(at: CTRunGetStringRange(run).location)
                guard strike ? style.strikethrough : style.background != nil else { continue }
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetPositions(run, CFRange(), &positions)
                CTRunGetAdvances(run, CFRange(), &advances)
                let left = positions.map(\.x).min()!
                let right = zip(positions, advances).map { $0.x + $1.width }.max()!
                var ascent: CGFloat = 0, descent: CGFloat = 0
                _ = CTRunGetTypographicBounds(run, CFRange(), &ascent, &descent, nil)
                let origin = origins[index]
                if strike {
                    let font = font(style)
                    let y = origin.y + CTFontGetXHeight(font) / 2
                    context.setStrokeColor(color(style.color))
                    context.setLineWidth(max(1, CTFontGetUnderlineThickness(font)))
                    context.move(to: CGPoint(x: origin.x + left, y: y))
                    context.addLine(to: CGPoint(x: origin.x + right, y: y))
                    context.strokePath()
                } else if let background = style.background {
                    context.setFillColor(color(background))
                    context.fill(CGRect(x: origin.x + left, y: origin.y - descent,
                        width: right - left, height: ascent + descent))
                }
            }
        }
    }
}
