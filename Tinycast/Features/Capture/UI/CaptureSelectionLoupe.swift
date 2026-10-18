import AppKit

@MainActor
enum CaptureSelectionLoupe {
    /// Labels drawn over the screenshot stay dark in either appearance so any pixels behind them read.
    static let labelFill = NSColor.black.withAlphaComponent(0.85)

    static func draw(
        image: CGImage, at point: CGPoint, bounds: CGRect,
        context: CGContext, metrics: InterfaceMetrics
    ) {
        guard let pixel = CaptureScreenSample.pixel(at: point, in: bounds, image: image),
            let hex = CaptureScreenSample.hex(image: image, pixel: pixel) else { return }
        let radius = (Theme.Size.captureLoupePixels / 2).rounded(.down)
        let area = CGRect(x: pixel.x - radius, y: pixel.y - radius,
            width: Theme.Size.captureLoupePixels, height: Theme.Size.captureLoupePixels)
        let source = area.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let crop = image.cropping(to: source) else { return }
        let cell = metrics.scaled(Theme.Size.captureLoupeCell)
        let gap = metrics.spacing.md
        let text = NSAttributedString(string: "\(hex)\n\(Int(pixel.x)), \(Int(pixel.y))", attributes: [
            .font: font(metrics), .foregroundColor: NSColor.white
        ])
        let frame = frame(at: point, bounds: bounds, metrics: metrics)
        labelFill.setFill()
        NSBezierPath(roundedRect: frame, xRadius: metrics.radius.barControl,
            yRadius: metrics.radius.barControl).fill()
        let raster = CGRect(x: frame.minX + gap + (source.minX - area.minX) * cell,
            y: frame.maxY - gap - (source.minY - area.minY + CGFloat(crop.height)) * cell,
            width: CGFloat(crop.width) * cell, height: CGFloat(crop.height) * cell)
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(crop, in: raster)
        let focus = CGRect(x: raster.minX + (pixel.x - source.minX) * cell,
            y: raster.maxY - (pixel.y - source.minY + 1) * cell, width: cell, height: cell)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(focus.insetBy(dx: -0.5, dy: -0.5))
        context.restoreGState()
        text.draw(at: CGPoint(x: frame.minX + gap, y: frame.minY + gap))
    }

    static func frame(at point: CGPoint, bounds: CGRect, metrics: InterfaceMetrics) -> CGRect {
        let gap = metrics.spacing.md
        let side = metrics.scaled(Theme.Size.captureLoupeCell) * Theme.Size.captureLoupePixels
        let label = NSAttributedString(string: "#FFFFFF\n88888, 88888", attributes: [.font: font(metrics)])
        let width = max(side, label.size().width) + gap * 2
        let height = side + label.size().height + gap * 3
        let x = point.x + width + gap * 3 <= bounds.maxX ? point.x + gap * 3 : point.x - width - gap * 3
        return CGRect(x: max(bounds.minX + gap, min(x, bounds.maxX - width - gap)),
            y: max(bounds.minY + gap, min(point.y - height - gap * 3, bounds.maxY - height - gap)),
            width: width, height: height)
    }

    private static func font(_ metrics: InterfaceMetrics) -> NSFont {
        .monospacedSystemFont(ofSize: metrics.typography.chipNSFont.pointSize, weight: .regular)
    }
}
