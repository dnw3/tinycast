import CoreGraphics
import Foundation

enum CaptureMagnifierRenderer {
    nonisolated static func draw(
        _ annotation: CaptureAnnotation, document: CaptureDocument, directory: URL,
        rect: CGRect, context: CGContext
    ) throws {
        let bounds = annotation.bounds, scale = annotation.magnification ?? 2
        let visible = bounds.intersection(rect).intersection(document.outputBounds)
        guard CaptureGeometry.valid(visible) else { return }
        let sample = CGRect(x: bounds.midX + (visible.minX - bounds.midX) / scale,
            y: bounds.midY + (visible.minY - bounds.midY) / scale,
            width: visible.width / scale, height: visible.height / scale)
            .insetBy(dx: -2, dy: -2).integral.intersection(document.outputBounds)
        guard CaptureGeometry.valid(sample) else { return }
        var underlying = document
        underlying.edit.annotations.removeAll { $0.tool == .magnifier }
        let image = try CaptureRenderer.image(document: underlying, directory: directory, rect: sample)
        let target = CGRect(x: bounds.midX + (sample.minX - bounds.midX) * scale,
            y: bounds.midY + (sample.minY - bounds.midY) * scale,
            width: sample.width * scale, height: sample.height * scale)
        context.saveGState()
        context.addEllipse(in: bounds)
        context.clip()
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: target.size))
        context.restoreGState()
        context.saveGState()
        context.setStrokeColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: annotation.rgba.map { CGFloat($0) })!)
        context.setLineWidth(annotation.width)
        context.strokeEllipse(in: bounds)
        context.restoreGState()
    }
}
