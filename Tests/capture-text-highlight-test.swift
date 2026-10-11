import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureTextHighlightTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = try CapturePixelSize(width: 160, height: 128), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: directory.appendingPathComponent(raster)) { _, row in
            row.initializeMemory(as: UInt8.self, repeating: 255)
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 160, height: 128), origin: .zero)])
        var cache = CaptureTextHighlight(document: document, lines: [
            CGRect(x: 10, y: 20, width: 140, height: 20), CGRect(x: 20, y: 60, width: 100, height: 15),
            CGRect(x: -10, y: 100, width: 30, height: 40), .null,
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)])
        precondition(cache.lines.count == 3 && cache.lines[2] == CGRect(x: 0, y: 100, width: 20, height: 28))
        let first = CGPoint(x: 40, y: 30), last = CGPoint(x: 90, y: 70)
        let highlights = cache.annotations(from: first, to: last, ink: .yellow, color: nil)
        precondition(highlights.count == 2 && highlights.allSatisfy(\.isValid))
        precondition(highlights[0].points == [CGPoint(x: 40, y: 30), CGPoint(x: 90, y: 30)])
        precondition(highlights[0].width == 4 && highlights[1].width == 3)
        let reversed = cache.annotations(from: last, to: first, ink: .yellow, color: nil)
        precondition(reversed.map(\.points) == highlights.map(\.points))
        let horizontal = cache.annotations(from: first, to: CGPoint(x: 90, y: 30), ink: .yellow, color: nil)
        precondition(horizontal.count == 1)
        precondition(cache.annotations(from: .zero, to: CGPoint(x: 1, y: 1), ink: .red, color: nil).isEmpty)
        precondition(cache.annotations(from: first, to: first, ink: .red, color: nil).isEmpty)
        precondition(cache.annotations(from: CGPoint(x: CGFloat.nan, y: 0), to: last, ink: .red, color: nil).isEmpty)
        document.edit.annotations = highlights
        document.revision += 1
        precondition(cache.advance(to: document) && cache.revision == 1)
        let roundTrip = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(document))
        precondition(roundTrip == document)
        let png = directory.appendingPathComponent("highlight.png")
        try CaptureRenderer.png(document: document, directory: directory, to: png)
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png as CFURL, nil)!, 0, nil)!
        let output = rgba(decoded)
        let preview = rgba(try CaptureRenderer.preview(document: document, directory: directory, maximum: 160))
        precondition(zip(output, preview).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
        let top = (30 * 160 + 60) * 4, gap = (50 * 160 + 60) * 4
        precondition(output[top + 2] < 240 && output[top] > 240 && output[gap + 2] == 255)
        precondition(output[(30 * 160 + 20) * 4 + 2] == 255, "Partial lines must not cover unselected text")
        var undo = CaptureUndoHistory(), edit = document.edit
        edit.annotations = []
        undo.commit(edit, to: &document)
        precondition(cache.advance(to: document))
        undo.undo(&document)
        precondition(document.edit.annotations == highlights && cache.advance(to: document))
        var changed = document
        changed.edit.crop = CGRect(x: 0, y: 0, width: 120, height: 100)
        precondition(!cache.advance(to: changed))
        changed = document; changed.edit.presentation = .init()
        precondition(!cache.advance(to: changed))
        changed = document; changed.edit.annotations.append(.init(id: UUID(), tool: .cover,
            points: [.zero, CGPoint(x: 10, y: 10)]))
        precondition(!cache.advance(to: changed))
        changed = document; changed.size = try CapturePixelSize(width: 160, height: 130)
        precondition(!cache.advance(to: changed))
        let other = CaptureDocument(id: UUID(), createdAt: document.createdAt, size: size, pieces: document.pieces)
        precondition(!cache.advance(to: other))
        print("Text-line partial/multiline geometry, clipping, invalidation, undo, JSON and PNG/preview passed")
    }

    static func rgba(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: 160, height: 128, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 128))
        return Data(bytes: context.data!, count: 160 * 128 * 4)
    }
}
