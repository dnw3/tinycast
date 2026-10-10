import CoreGraphics
import CoreText
import Foundation

enum CaptureAnnotationRenderer {
    nonisolated static func draw(_ annotations: [CaptureAnnotation], in context: CGContext) {
        for annotation in annotations {
            guard let first = annotation.points.first, let last = annotation.points.last else { continue }
            context.saveGState()
            let color = CGColor(
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: annotation.rgba.map { CGFloat($0) })!
            context.setStrokeColor(color)
            context.setFillColor(color)
            context.setLineWidth(annotation.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let bounds = annotation.drawingBounds
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.rotate(by: (annotation.rotation ?? 0) * .pi / 180)
            context.scaleBy(x: annotation.reflection?.horizontal == true ? -1 : 1,
                y: annotation.reflection?.vertical == true ? -1 : 1)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            switch annotation.tool {
            case .rectangle:
                if annotation.filled == true { context.fill(bounds) } else { context.stroke(bounds) }
            case .ellipse:
                if annotation.filled == true { context.fillEllipse(in: bounds) } else { context.strokeEllipse(in: bounds) }
            case .cover, .pixelate, .blur:
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(bounds)
            case .magnifier:
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fillEllipse(in: bounds)
                context.strokeEllipse(in: bounds)
            case .erase:
                if annotation.color == nil { context.setFillColor(CGColor(gray: 0, alpha: 1)) }
                context.fill(bounds)
            case .arrow, .curvedArrow, .line, .ruler:
                context.move(to: first)
                if annotation.tool == .curvedArrow {
                    context.addQuadCurve(to: last, control: annotation.curveControl)
                } else { context.addLine(to: last) }
                if annotation.tool == .arrow || annotation.tool == .curvedArrow {
                    let tail = annotation.tool == .curvedArrow ? annotation.curveControl : first
                    let angle = atan2(last.y - tail.y, last.x - tail.x)
                    let length = max(12, annotation.width * 4)
                    for turn in [-0.5, 0.5] {
                        context.move(to: last)
                        context.addLine(
                            to: CGPoint(x: last.x - cos(angle + turn) * length, y: last.y - sin(angle + turn) * length))
                    }
                }
                context.strokePath()
                if annotation.tool == .ruler {
                    let label = "\(Int(hypot(last.x - first.x, last.y - first.y).rounded())) px"
                    let size = max(12, annotation.width * 4)
                    let labelBounds = CGRect(x: bounds.midX, y: bounds.midY - size * 1.5,
                        width: size * CGFloat(label.count), height: size * 1.5)
                    drawText(label, rect: labelBounds, font: textFont(.system, size: size), color: color, context: context)
                }
            case .pen, .highlighter:
                if annotation.tool == .highlighter {
                    context.setAlpha(0.3)
                    context.setLineWidth(annotation.width * 5)
                    context.setLineCap(.butt)
                }
                context.addLines(between: annotation.points)
                context.strokePath()
            case .text, .emoji:
                drawText(
                    annotation.text, rect: bounds,
                    font: textFont(annotation.font ?? .system, size: annotation.fontSize ?? annotation.width * 6),
                    color: color, context: context)
            case .number:
                let diameter = max(28, annotation.width * 9)
                let rect = CGRect(x: first.x, y: first.y, width: diameter, height: diameter)
                context.fillEllipse(in: rect)
                drawText(
                    annotation.text, rect: rect.insetBy(dx: diameter * 0.25, dy: diameter * 0.1),
                    font: textFont(.system, size: diameter * 0.65), color: CGColor(gray: 1, alpha: 1), context: context)
            case .select, .crop, .spotlight: break
            }
            context.restoreGState()
        }
        spotlight(annotations, in: context)
    }

    nonisolated static func spotlight(_ annotations: [CaptureAnnotation], in context: CGContext) {
        let areas = annotations.filter { $0.tool == .spotlight && CaptureGeometry.valid($0.drawingBounds) }
        guard !areas.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let bounds = context.boundingBoxOfClipPath
        for annotation in areas {
            let rect = annotation.drawingBounds
            let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: (annotation.rotation ?? 0) * .pi / 180)
                .translatedBy(x: -rect.midX, y: -rect.midY)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(rect, transform: transform)
            context.addPath(path)
            context.clip(using: .evenOdd)
        }
        context.setFillColor(CGColor(gray: 0, alpha: 0.55))
        context.fill(bounds)
    }

    nonisolated static func textFont(_ font: CaptureAnnotation.Font, size: CGFloat) -> CTFont {
        switch font {
        case .system: CTFontCreateUIFontForLanguage(.system, size, nil)!
        case .serif: CTFontCreateWithName("TimesNewRomanPSMT" as CFString, size, nil)
        case .monospaced: CTFontCreateWithName("Menlo-Regular" as CFString, size, nil)
        }
    }

    nonisolated private static func drawText(
        _ text: String, rect: CGRect, font: CTFont, color: CGColor, context: CGContext
    ) {
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        let string = CFAttributedStringCreate(nil, text as CFString, attributes)!
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(), CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
