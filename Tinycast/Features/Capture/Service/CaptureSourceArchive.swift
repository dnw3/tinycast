import Foundation

enum CaptureSourceArchive {
    nonisolated static func copy(
        document: CaptureDocument, from directory: URL, to destination: URL
    ) throws -> CaptureDocument {
        var archived = document
        for index in document.pieces.indices {
            let piece = document.pieces[index]
            let source = directory.appendingPathComponent(piece.raster)
            let metadata = try CaptureRasterStore.validate(at: source)
            let bounds = CGRect(x: 0, y: 0, width: metadata.size.width, height: metadata.size.height)
            guard bounds.contains(piece.source) else { throw CaptureRasterError.invalidTile }
            if bounds == piece.source {
                let target = destination.appendingPathComponent(piece.raster)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: source, to: target)
                }
            } else {
                let raster = UUID().uuidString
                try ScrollFrameReader.strip(
                    from: source, rect: piece.source, to: destination.appendingPathComponent(raster))
                archived.pieces[index] = .init(
                    raster: raster, source: CGRect(origin: .zero, size: piece.source.size),
                    origin: piece.origin, reflection: piece.reflection)
            }
        }
        for (index, layer) in document.imageLayers.enumerated() {
            let source = directory.appendingPathComponent(layer.raster)
            let metadata = try CaptureRasterStore.validate(at: source)
            let bounds = CGRect(x: 0, y: 0, width: metadata.size.width, height: metadata.size.height)
            guard bounds.contains(layer.source) else { throw CaptureRasterError.invalidTile }
            if bounds == layer.source {
                try copyRaster(layer.raster, from: directory, to: destination)
            } else {
                let raster = UUID().uuidString
                try ScrollFrameReader.strip(from: source, rect: layer.source, to: destination.appendingPathComponent(raster))
                archived.edit.imageLayers?[index] = .init(id: layer.id, raster: raster,
                    source: CGRect(origin: .zero, size: layer.source.size), frame: layer.frame,
                    opacity: layer.opacity, rotation: layer.rotation, reflection: layer.reflection,
                    backgroundMask: layer.backgroundMask)
            }
            if let mask = layer.backgroundMask { try copyRaster(mask.raster, from: directory, to: destination) }
        }
        return try archived.validated()
    }

    nonisolated private static func copyRaster(_ raster: String, from directory: URL, to destination: URL) throws {
        let source = directory.appendingPathComponent(raster), target = destination.appendingPathComponent(raster)
        _ = try CaptureRasterStore.validate(at: source)
        if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
    }
}
