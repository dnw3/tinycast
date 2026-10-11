import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureAnnotationStyleTests {
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
        var number = CaptureAnnotation(id: UUID(), tool: .number,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)], ink: .black, text: "1")
        document.edit.annotations = [number]
        let numberPixels = try pixels(document, directory: directory)
        number.reversed = true
        document.edit.annotations = [number]
        let unchangedNumberPixels = try pixels(document, directory: directory)
        precondition(numberPixels == unchangedNumberPixels, "Arrow reversal must not move numbered annotations")
        let legacy = CaptureAnnotation(id: UUID(), tool: .arrow,
            points: [CGPoint(x: 30, y: 64), CGPoint(x: 130, y: 64)], ink: .black)
        let decoded = try JSONDecoder().decode(CaptureAnnotation.self, from: JSONEncoder().encode(legacy))
        precondition(decoded.arrowStyle == nil && decoded.controlPoint == nil)
        var filled = CaptureAnnotation(id: UUID(), tool: .rectangle,
            points: [CGPoint(x: 30, y: 24), CGPoint(x: 130, y: 104)], ink: .black, filled: true)
        precondition(filled.effectiveShapeStyle == .fill)
        filled.filled = false
        precondition(filled.effectiveShapeStyle == .outline)
        var coverage: [CaptureAnnotation.ArrowStyle: Int] = [:]
        for style in CaptureAnnotation.ArrowStyle.allCases {
            var arrow = legacy
            arrow.arrowStyle = style
            document.edit.annotations = [arrow]
            let forward = try pixels(document, directory: directory)
            coverage[style] = forward.filter { $0 < 128 }.count
            if style == .single { precondition(forward[(67 * 160 + 117) * 4] < 10) }
            if style == .open { precondition(forward[(67 * 160 + 117) * 4] > 240) }
            arrow.reversed = true
            document.edit.annotations = [arrow]
            let backward = try pixels(document, directory: directory)
            precondition(region(forward, x: 112..<135) > region(forward, x: 25..<48) || style == .double)
            precondition(region(backward, x: 25..<48) > region(backward, x: 112..<135) || style == .double)
            arrow.tool = .curvedArrow
            arrow.controlPoint = CGPoint(x: 80, y: 10)
            document.edit.annotations = [arrow]
            _ = try pixels(document, directory: directory)
        }
        precondition(coverage[.single]! != coverage[.open]!)
        precondition(coverage[.double]! > coverage[.single]!)
        precondition(coverage[.thick]! > coverage[.double]!)
        for tool in [CaptureAnnotation.Tool.rectangle, .ellipse] {
            filled.tool = tool
            for style in CaptureAnnotation.ShapeStyle.allCases {
                filled.shapeStyle = style
                filled.cornerRadius = tool == .rectangle ? 20 : nil
                document.edit.annotations = [filled]
                let values = try pixels(document, directory: directory)
                precondition(values[(64 * 160 + 80) * 4] == (style == .outline ? 255 : 0))
                if tool == .rectangle { precondition(values[(25 * 160 + 31) * 4] == 255) }
            }
        }
        var curve = legacy
        curve.tool = .curvedArrow
        curve.controlPoint = CGPoint(x: 80, y: 10)
        curve.controlCenter = CGPoint(x: 80, y: 64)
        curve.rotation = 32
        curve.reflection = .init(horizontal: true)
        let roundTrip = curve.untransformed(curve.displayedControl!)
        precondition(hypot(roundTrip.x - 80, roundTrip.y - 10) < 0.000001)
        curve.move(by: CGSize(width: 2, height: 3))
        precondition(curve.controlPoint == CGPoint(x: 82, y: 13))
        precondition(curve.controlCenter == CGPoint(x: 82, y: 67))
        precondition(curve.isValid)
        curve.cornerRadius = .infinity
        precondition(!curve.isValid)
        curve.cornerRadius = 12
        document.edit.annotations = [curve]
        let encoded = try JSONEncoder().encode(document)
        let reopened = try JSONDecoder().decode(CaptureDocument.self, from: encoded).validated()
        precondition(reopened.edit.annotations == document.edit.annotations)
        let archive = directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let archived = try CaptureSourceArchive.copy(document: reopened, from: directory, to: archive)
        let archivedPixels = try pixels(archived, directory: archive)
        let originalPixels = try pixels(document, directory: directory)
        precondition(archivedPixels == originalPixels)
        var undo = CaptureUndoHistory(), edit = document.edit
        edit.annotations[0].arrowStyle = .double
        undo.commit(edit, to: &document)
        undo.undo(&document)
        precondition(document.edit.annotations == reopened.edit.annotations)
        undo.redo(&document)
        precondition(document.edit.annotations[0].arrowStyle == .double)
        for axis in CaptureDocument.Axis.allCases {
            let reflected = try CaptureReflection.flip(document, axis: axis)
            let reflectedPixels = try pixels(reflected, directory: directory)
            let beforeReflection = try pixels(document, directory: directory)
            for y in 0..<128 {
                for x in 0..<160 {
                    let oldX = axis == .horizontal ? 159 - x : x
                    let oldY = axis == .vertical ? 127 - y : y
                    let offset = (y * 160 + x) * 4, oldOffset = (oldY * 160 + oldX) * 4
                    for channel in 0..<4 {
                        precondition(abs(Int(reflectedPixels[offset + channel])
                            - Int(beforeReflection[oldOffset + channel])) <= 2)
                    }
                }
            }
            let restored = try CaptureReflection.flip(reflected, axis: axis)
            let restoredPixels = try pixels(restored, directory: directory)
            let currentPixels = try pixels(document, directory: directory)
            precondition(restoredPixels == currentPixels)
        }
        print("Arrow heads/reversal, rounded shape pixels, curve transforms, archive and undo passed")
    }

    static func region(_ data: [UInt8], x: Range<Int>) -> Int {
        (40..<88).reduce(0) { total, y in
            total + x.filter { data[(y * 160 + $0) * 4] < 128 }.count
        }
    }

    static func pixels(_ document: CaptureDocument, directory: URL) throws -> [UInt8] {
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        try CaptureRenderer.png(document: document, directory: directory, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let decoded = rgba(image)
        let preview = try CaptureRenderer.preview(document: document, directory: directory, maximum: 160)
        let previewPixels = rgba(preview)
        let maximumDifference = zip(decoded, previewPixels).map { abs(Int($0) - Int($1)) }.max()!
        precondition(maximumDifference <= 2, "Preview and PNG must match within antialiasing precision")
        return decoded
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: 160, height: 128, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 128))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 160 * 128 * 4))
    }
}
