import CoreGraphics
import CoreText
import Foundation

enum CaptureAnnotationRenderer {
    nonisolated static func draw(_ annotations: [CaptureAnnotation], in context: CGContext) {
        for annotation in annotations {
            guard let start = annotation.points.first, let end = annotation.points.last else { continue }
            let reversed = [.arrow, .curvedArrow].contains(annotation.tool) && annotation.reversed == true
            let first = reversed ? end : start
            let last = reversed ? start : end
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
            context.translateBy(x: annotation.transformCenter.x, y: annotation.transformCenter.y)
            context.rotate(by: (annotation.rotation ?? 0) * .pi / 180)
            context.scaleBy(x: annotation.reflection?.horizontal == true ? -1 : 1,
                y: annotation.reflection?.vertical == true ? -1 : 1)
            context.translateBy(x: -annotation.transformCenter.x, y: -annotation.transformCenter.y)
            switch annotation.tool {
            case .rectangle:
                let radius = min(annotation.cornerRadius ?? 0, min(bounds.width, bounds.height) / 2)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
                drawShape(annotation, in: context)
            case .ellipse:
                context.addEllipse(in: bounds)
                drawShape(annotation, in: context)
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
                let arrow = annotation.tool == .arrow || annotation.tool == .curvedArrow
                if arrow, annotation.arrowStyle == .thick { context.setLineWidth(annotation.width * 3) }
                context.strokePath()
                if arrow {
                    let control = annotation.tool == .curvedArrow ? annotation.curveControl : first
                    drawHead(at: last, from: control, annotation: annotation, in: context)
                    if annotation.arrowStyle == .double {
                        drawHead(at: first, from: annotation.tool == .curvedArrow ? annotation.curveControl : last,
                            annotation: annotation, in: context)
                    }
                }
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
                if annotation.smoothed == true, annotation.tool == .pen, annotation.points.count > 2 {
                    context.move(to: first)
                    for index in 1..<annotation.points.count - 1 {
                        let point = annotation.points[index], next = annotation.points[index + 1]
                        context.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2),
                            control: point)
                    }
                    context.addLine(to: last)
                } else { context.addLines(between: annotation.points) }
                context.strokePath()
            case .text, .emoji:
                if annotation.tool == .text, annotation.textFormat != nil {
                    CaptureTextRenderer.draw(annotation, in: context)
                } else { drawText(
                    annotation.text, rect: bounds,
                    font: textFont(annotation.font ?? .system, size: annotation.fontSize ?? annotation.width * 6),
                    color: color, context: context) }
            case .number:
                let rect = annotation.numberBounds, diameter = rect.width
                if annotation.numberLeader == true, annotation.points.count > 1 {
                    context.move(to: CGPoint(x: rect.midX, y: rect.midY))
                    context.addLine(to: last)
                    context.strokePath()
                    context.fillEllipse(in: CGRect(x: last.x - annotation.width / 2,
                        y: last.y - annotation.width / 2, width: annotation.width, height: annotation.width))
                }
                context.fillEllipse(in: rect)
                if annotation.numberFormat == nil {
                    drawText(annotation.text, rect: rect.insetBy(dx: diameter * 0.25, dy: diameter * 0.1),
                        font: textFont(.system, size: diameter * 0.65), color: CGColor(gray: 1, alpha: 1), context: context)
                } else { drawNumber(annotation.numberLabel, rect: rect, context: context) }
            case .select, .crop, .spotlight: break
            }
            context.restoreGState()
        }
        spotlight(annotations, in: context)
    }

    nonisolated private static func drawNumber(_ label: String, rect: CGRect, context: CGContext) {
        let font = textFont(.system, size: rect.width * 0.65)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)]
            as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, label as CFString, attributes)!)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let scale = min(1, rect.width * 0.78 / max(1, bounds.width))
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: -scale)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    nonisolated private static func drawShape(_ annotation: CaptureAnnotation, in context: CGContext) {
        switch annotation.effectiveShapeStyle {
        case .outline: context.strokePath()
        case .fill: context.fillPath()
        case .both: context.drawPath(using: .fillStroke)
        }
    }

    nonisolated private static func drawHead(
        at tip: CGPoint, from tail: CGPoint, annotation: CaptureAnnotation, in context: CGContext
    ) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length = max(12, annotation.width * (annotation.arrowStyle == .thick ? 6 : 4))
        let edges = [-0.5, 0.5].map { turn in
            CGPoint(x: tip.x - cos(angle + turn) * length, y: tip.y - sin(angle + turn) * length)
        }
        context.setLineWidth(annotation.width)
        context.move(to: edges[0])
        context.addLine(to: tip)
        context.addLine(to: edges[1])
        if (annotation.arrowStyle ?? .open) == .open { context.strokePath() } else {
            context.closePath()
            context.fillPath()
        }
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
