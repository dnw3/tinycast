import Foundation

struct CaptureReflection: Codable, Equatable, Sendable {
    var horizontal = false
    var vertical = false

    var isIdentity: Bool { !horizontal && !vertical }

    func rect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: horizontal ? bounds.minX + bounds.maxX - rect.maxX : rect.minX,
            y: vertical ? bounds.minY + bounds.maxY - rect.maxY : rect.minY,
            width: rect.width, height: rect.height)
    }

    mutating func toggle(_ axis: CaptureDocument.Axis) {
        if axis == .horizontal { horizontal.toggle() } else { vertical.toggle() }
    }

    static func flip(_ document: CaptureDocument, axis: CaptureDocument.Axis) throws -> CaptureDocument {
        var result = document
        let operation = CaptureReflection(horizontal: axis == .horizontal, vertical: axis == .vertical)
        result.pieces = document.pieces.map { original in
            var piece = original
            piece.origin = operation.rect(original.bounds, in: document.bounds).origin
            var reflection = original.reflection ?? .init()
            reflection.toggle(axis)
            piece.reflection = reflection.isIdentity ? nil : reflection
            return piece
        }
        if (document.axis ?? .vertical) == axis { result.pieces.reverse() }
        result.edit.crop = document.edit.crop.map { operation.rect($0, in: document.bounds) }
        result.edit.translation?.blocks = document.edit.translation?.blocks.map { original in
            var block = original
            block.rect = operation.rect(original.rect, in: document.bounds)
            var reflection = original.reflection ?? .init()
            reflection.toggle(axis)
            block.reflection = reflection.isIdentity ? nil : reflection
            return block
        } ?? []
        result.edit.imageLayers = document.edit.imageLayers.map { layers in
            layers.map { original in
                var layer = original
                layer.frame = operation.rect(original.frame, in: document.bounds)
                layer.rotation = -original.rotation
                var reflection = original.reflection ?? .init()
                reflection.toggle(axis)
                layer.reflection = reflection.isIdentity ? nil : reflection
                return layer
            }
        }
        result.edit.annotations = document.edit.annotations.map { original in
            var annotation = original
            let center = original.transformCenter
            annotation.move(by: CGSize(
                width: axis == .horizontal ? document.bounds.minX + document.bounds.maxX - center.x * 2 : 0,
                height: axis == .vertical ? document.bounds.minY + document.bounds.maxY - center.y * 2 : 0))
            if let rotation = original.rotation { annotation.rotation = -rotation }
            var reflection = original.reflection ?? .init()
            reflection.toggle(axis)
            annotation.reflection = reflection.isIdentity ? nil : reflection
            return annotation
        }
        return try result.validated()
    }
}
