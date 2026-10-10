import Accelerate
import CoreGraphics
import Foundation

enum CapturePresentationRenderer {
    nonisolated static func image(
        document: CaptureDocument, directory: URL, rect: CGRect, includingVectorAnnotations: Bool
    ) throws -> CGImage {
        guard let style = document.edit.presentation, style.isValid, CaptureGeometry.valid(rect),
            document.outputBounds.contains(rect), rect.width * rect.height <= 4_194_304,
            let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
                bitsPerComponent: 8, bytesPerRow: Int(rect.width) * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        context.translateBy(x: -rect.minX, y: rect.height + rect.minY)
        context.scaleBy(x: 1, y: -1)
        background(style, bounds: document.outputBounds, visible: rect, in: context)
        let frame = style.frame(for: document.contentBounds)
        let path = path(document)
        if style.shadow > 0 {
            context.saveGState()
            context.addRect(document.outputBounds)
            context.addPath(path)
            context.clip(using: .evenOdd)
            context.setShadow(offset: CGSize(width: 0, height: -style.shadow / 3),
                blur: style.shadow, color: CGColor(gray: 0, alpha: 0.35))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
        context.addPath(path)
        context.clip()
        if style.windowFrame { header(frame, in: context) }
        let content = document.contentBounds.intersection(rect)
        if CaptureGeometry.valid(content) {
            var plain = document
            plain.edit.presentation = nil
            let image = try CaptureRenderer.contentImage(document: plain, directory: directory,
                rect: content, includingVectorAnnotations: includingVectorAnnotations)
            context.saveGState()
            context.translateBy(x: content.minX, y: content.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: content.size))
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return image
    }

    nonisolated static func path(_ document: CaptureDocument) -> CGPath {
        guard let style = document.edit.presentation else { return CGPath(rect: document.contentBounds, transform: nil) }
        let rect = style.frame(for: document.contentBounds)
        let radius = min(style.radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    nonisolated private static func background(
        _ style: CapturePresentation, bounds: CGRect, visible: CGRect, in context: CGContext
    ) {
        guard style.background != .transparent else { return }
        let first = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: style.color.rgba.map { CGFloat($0) })!
        context.setFillColor(first)
        context.fill(visible)
        if style.background == .gradient {
            gradient(style, bounds: bounds, visible: visible, in: context)
        } else if style.background == .grid {
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: style.secondary.rgba.map { CGFloat($0) })!)
            for y in stride(from: bounds.minY + floor((visible.minY - bounds.minY) / 24) * 24,
                to: visible.maxY, by: 24) {
                for x in stride(from: bounds.minX + floor((visible.minX - bounds.minX) / 24) * 24,
                    to: visible.maxX, by: 24) {
                    context.fill(CGRect(x: x, y: y, width: 1, height: 24))
                    context.fill(CGRect(x: x, y: y, width: 24, height: 1))
                }
            }
        }
    }

    nonisolated private static func gradient(
        _ style: CapturePresentation, bounds: CGRect, visible: CGRect, in context: CGContext
    ) {
        guard let data = context.data else { return }
        let width = Int(visible.width), count = vDSP_Length(width)
        let length = bounds.width * bounds.width + bounds.height * bounds.height
        var start = Double(visible.minX) + 0.5, step = 1.0
        var positions = [Double](repeating: 0, count: width)
        var values = positions
        vDSP_vrampD(&start, &step, &positions, 1, count)
        let first = [style.color.red, style.color.green, style.color.blue]
        let last = [style.secondary.red, style.secondary.green, style.secondary.blue]
        for row in 0..<Int(visible.height) {
            let vertical = ((visible.minY + CGFloat(row) + 0.5 - bounds.minY) * bounds.height
                - bounds.minX * bounds.width) / length
            let output = data.advanced(by: row * context.bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for channel in 0..<3 {
                let delta = Double(last[channel]) - Double(first[channel])
                var slope = delta * bounds.width / length
                var offset = Double(first[channel]) + delta * vertical + 0.5 + 0.000000001
                vDSP_vsmsaD(positions, 1, &slope, &offset, &values, 1, count)
                vDSP_vfixu8D(values, 1, output.advanced(by: channel), 4, count)
            }
        }
    }

    nonisolated private static func header(_ frame: CGRect, in context: CGContext) {
        context.setFillColor(CGColor(gray: 0.13, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 32))
        let colors = [CaptureColor(red: 255, green: 95, blue: 87), .init(red: 254, green: 188, blue: 46),
            .init(red: 40, green: 200, blue: 64)]
        for (index, color) in colors.enumerated() where frame.width >= 68 {
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: color.rgba.map { CGFloat($0) })!)
            context.fillEllipse(in: CGRect(x: frame.minX + 12 + CGFloat(index) * 18,
                y: frame.minY + 11, width: 10, height: 10))
        }
    }
}
