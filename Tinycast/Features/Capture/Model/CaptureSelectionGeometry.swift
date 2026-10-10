import Foundation

enum CaptureSelectionGeometry {
    enum Handle: CaseIterable {
        case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left

        var unitPoint: CGPoint {
            switch self {
            case .bottomLeft: .init(x: 0, y: 0)
            case .bottom: .init(x: 0.5, y: 0)
            case .bottomRight: .init(x: 1, y: 0)
            case .right: .init(x: 1, y: 0.5)
            case .topRight: .init(x: 1, y: 1)
            case .top: .init(x: 0.5, y: 1)
            case .topLeft: .init(x: 0, y: 1)
            case .left: .init(x: 0, y: 0.5)
            }
        }
    }

    static func point(_ handle: Handle, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * handle.unitPoint.x,
            y: rect.minY + rect.height * handle.unitPoint.y)
    }

    static func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(bounds.minX, rect.minX + delta.width), bounds.maxX - rect.width),
            y: min(max(bounds.minY, rect.minY + delta.height), bounds.maxY - rect.height),
            width: rect.width, height: rect.height)
    }

    static func resized(_ rect: CGRect, handle: Handle, to point: CGPoint, in bounds: CGRect) -> CGRect {
        let point = CGPoint(
            x: min(bounds.maxX, max(bounds.minX, point.x)),
            y: min(bounds.maxY, max(bounds.minY, point.y)))
        let unit = handle.unitPoint
        var left = rect.minX, right = rect.maxX, bottom = rect.minY, top = rect.maxY
        if unit.x == 0 { left = min(point.x, right - 2) }
        if unit.x == 1 { right = max(point.x, left + 2) }
        if unit.y == 0 { bottom = min(point.y, top - 2) }
        if unit.y == 1 { top = max(point.y, bottom + 2) }
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom).intersection(bounds)
    }

    static func frame(pixels: CGRect, in sourceFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: sourceFrame.minX + pixels.minX / scale,
            y: sourceFrame.maxY - pixels.maxY / scale,
            width: pixels.width / scale, height: pixels.height / scale)
    }

    static func reframe(
        _ document: CaptureDocument, raster: String, pixels: CGRect,
        oldFrame: CGRect, newFrame: CGRect, oldScale: CGFloat, scale: CGFloat
    ) throws -> CaptureDocument {
        let reflection = document.pieces.count == 1 ? document.pieces[0].reflection : nil
        var unreflected = document
        if reflection?.horizontal == true { unreflected = try CaptureReflection.flip(unreflected, axis: .horizontal) }
        if reflection?.vertical == true { unreflected = try CaptureReflection.flip(unreflected, axis: .vertical) }
        var result = unreflected
        result.captureScale = scale
        result.size = try CapturePixelSize(width: Int(pixels.width), height: Int(pixels.height))
        result.pieces = [.init(raster: raster, source: pixels, origin: .zero)]
        result.edit.crop = nil
        let ratio = scale / oldScale
        let offset = CGPoint(
            x: (oldFrame.minX - newFrame.minX) * scale,
            y: (newFrame.maxY - oldFrame.maxY) * scale)
        result.edit.translation?.blocks = unreflected.edit.translation?.blocks.map { original in
            var block = original
            block.rect = CGRect(x: original.rect.minX * ratio + offset.x,
                y: original.rect.minY * ratio + offset.y,
                width: original.rect.width * ratio, height: original.rect.height * ratio)
            return block
        } ?? []
        result.edit.imageLayers = unreflected.edit.imageLayers.map { layers in
            layers.map { original in
                var layer = original
                layer.frame = CGRect(x: original.frame.minX * ratio + offset.x,
                    y: original.frame.minY * ratio + offset.y,
                    width: original.frame.width * ratio, height: original.frame.height * ratio)
                return layer
            }
        }
        result.edit.annotations = unreflected.edit.annotations.map { original in
            var annotation = original
            annotation.points = original.points.map {
                CGPoint(x: $0.x * ratio + offset.x, y: $0.y * ratio + offset.y)
            }
            annotation.width = min(128, max(1, original.width * ratio))
            annotation.fontSize = original.fontSize.map { min(768, max(6, $0 * ratio)) }
            return annotation
        }
        if reflection?.horizontal == true { result = try CaptureReflection.flip(result, axis: .horizontal) }
        if reflection?.vertical == true { result = try CaptureReflection.flip(result, axis: .vertical) }
        return try result.validated()
    }
}
