import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureForegroundService {
    nonisolated static func input(for layer: CaptureImageLayer, directory: URL, to url: URL) throws {
        let size = try CapturePixelSize(width: Int(layer.source.width), height: Int(layer.source.height))
        let document = CaptureDocument(id: layer.id, createdAt: .distantPast, size: size,
            pieces: [.init(raster: layer.raster, source: layer.source, origin: .zero)])
        let image = try CaptureRenderer.preview(document: document, directory: directory, maximum: 1024)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureRasterError.invalidTile }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureRasterError.invalidTile }
    }
}
