import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureTextInput {
    nonisolated static func prepare(
        document: CaptureDocument, source: CaptureSource, at directory: URL,
        content: TextRecognitionResult.Content = .text
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let bounds = document.outputBounds
        var tiles: [TextRecognitionResult.Request.Tile] = []
        if content != .text {
            let image = try CaptureRenderer.preview(document: document, directory: source.directory)
            try write(image, to: directory.appendingPathComponent("overview.png"))
            tiles.append(.init(filename: "overview.png", rect: bounds))
        }
        let step = content == .text ? 896 : 512
        for y in stride(from: Int(bounds.minY), to: Int(bounds.maxY), by: step) {
            for x in stride(from: Int(bounds.minX), to: Int(bounds.maxX), by: step) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let rect = CGRect(
                        x: x, y: y, width: min(1024, Int(bounds.maxX) - x),
                        height: min(1024, Int(bounds.maxY) - y))
                    let filename = "\(tiles.count).png"
                    let image = try CaptureRenderer.image(
                        document: document, directory: source.directory, rect: rect)
                    try write(image, to: directory.appendingPathComponent(filename))
                    tiles.append(.init(filename: filename, rect: rect))
                }
            }
        }
        let request = TextRecognitionResult.Request(
            requestID: document.id, revision: document.revision, tiles: tiles, content: content)
        let url = directory.appendingPathComponent("request.json")
        try JSONEncoder().encode(request).write(to: url, options: .atomic)
        return url
    }

    nonisolated private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureRasterError.invalidTile }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureRasterError.invalidTile }
    }
}
