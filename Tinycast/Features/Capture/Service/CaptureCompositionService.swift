import Foundation

enum CaptureCompositionService {
    nonisolated static func append(
        _ image: CaptureImageLayer, to document: CaptureDocument, directory: URL, axis: CaptureDocument.Axis
    ) throws -> CaptureDocument {
        if document.pieces.isEmpty, document.edit.crop == nil, document.edit.presentation == nil {
            return try CaptureComposition.append(image, to: document, axis: axis)
        }
        let bounds = document.outputBounds
        let width = axis == .horizontal ? bounds.width + image.frame.width : max(bounds.width, image.frame.width)
        let height = axis == .vertical ? bounds.height + image.frame.height : max(bounds.height, image.frame.height)
        _ = try CapturePixelSize(width: Int(ceil(width)), height: Int(ceil(height)))
        guard bounds.width * bounds.height + image.source.width * image.source.height <= 64_000_000
        else { throw CaptureRasterError.invalidSize }
        let flattened = try flatten(document, directory: directory)
        do { return try CaptureComposition.append(image, to: flattened, axis: axis) } catch {
            for layer in flattened.imageLayers {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(layer.raster))
            }
            throw error
        }
    }

    nonisolated static func flatten(_ document: CaptureDocument, directory: URL) throws -> CaptureDocument {
        let raster = UUID().uuidString, png = directory.appendingPathComponent("combine-\(UUID()).png")
        let destination = directory.appendingPathComponent(raster)
        var completed = false
        defer {
            try? FileManager.default.removeItem(at: png)
            if !completed { try? FileManager.default.removeItem(at: destination) }
        }
        try CaptureRenderer.png(document: document, directory: directory, to: png)
        let size = try CaptureImageSource.load(png, at: destination)
        var result = CaptureDocument(id: document.id, createdAt: document.createdAt, size: size, pieces: [],
            captureScale: document.captureScale, revision: document.revision)
        let frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        result.edit.imageLayers = [.init(id: UUID(), raster: raster, source: frame, frame: frame)]
        completed = true
        return result
    }
}
