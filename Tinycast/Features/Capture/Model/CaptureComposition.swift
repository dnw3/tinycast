import Foundation

enum CaptureComposition {
    static func append(
        _ image: CaptureImageLayer, to document: CaptureDocument, axis: CaptureDocument.Axis
    ) throws -> CaptureDocument {
        guard document.pieces.isEmpty, document.edit.crop == nil, document.edit.presentation == nil
        else { throw CaptureRasterError.invalidTile }
        var result = document, layer = image
        layer.frame.origin = axis == .vertical
            ? CGPoint(x: 0, y: document.bounds.maxY) : CGPoint(x: document.bounds.maxX, y: 0)
        result.size = try CapturePixelSize(width: Int(ceil(max(document.bounds.maxX, layer.bounds.maxX))),
            height: Int(ceil(max(document.bounds.maxY, layer.bounds.maxY))))
        result.edit.imageLayers = document.imageLayers + [layer]
        return try result.validated()
    }

    static func fit(_ document: CaptureDocument) throws -> CaptureDocument {
        guard document.pieces.isEmpty, !document.imageLayers.isEmpty else { throw CaptureRasterError.invalidTile }
        let bounds = document.imageLayers.reduce(CGRect.null) { $0.union($1.bounds) }.integral
        var result = document
        result.size = try CapturePixelSize(width: Int(bounds.width), height: Int(bounds.height))
        result.edit.crop = nil
        result.edit.translation?.blocks = document.edit.translation?.blocks.map { original in
            var block = original
            block.rect = original.rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return block
        } ?? []
        result.edit.imageLayers = document.imageLayers.map { original in
            var layer = original
            layer.frame = original.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return layer
        }
        result.edit.annotations = document.edit.annotations.map { original in
            var annotation = original
            annotation.move(by: CGSize(width: -bounds.minX, height: -bounds.minY))
            return annotation
        }
        return try result.validated()
    }
}
