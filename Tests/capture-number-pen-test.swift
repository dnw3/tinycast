import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureNumberPenTests {
    static func main() throws {
        for (style, value, expected) in [
            (CaptureNumberFormat.Style.decimal, 25, "25"), (.roman, 4, "IV"), (.roman, 49, "XLIX"),
            (.roman, 3999, "MMMCMXCIX"), (.uppercase, 26, "Z"), (.uppercase, 27, "AA"),
            (.uppercase, 703, "AAA"), (.lowercase, 52, "az")
        ] {
            let format = CaptureNumberFormat(style: style, value: value)
            precondition(format.isValid && format.label == expected)
            let decoded = try JSONDecoder().decode(CaptureNumberFormat.self, from: JSONEncoder().encode(format))
            precondition(decoded == format)
        }
        for value in [Int.min, 0, 4000, Int.max] {
            let format = CaptureNumberFormat(value: value)
            precondition(!format.isValid && format.label.isEmpty)
        }
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
            points: [CGPoint(x: 12, y: 12), CGPoint(x: 130, y: 100)], ink: .red, width: 5, text: "7")
        let legacy = try JSONDecoder().decode(CaptureAnnotation.self, from: JSONEncoder().encode(number))
        precondition(legacy.numberFormat == nil && legacy.numberLeader == nil && legacy.numberLabel == "7")
        precondition(legacy.drawingBounds == legacy.numberBounds && legacy.displayedControl == nil)
        var variants: [Data] = []
        for style in CaptureNumberFormat.Style.allCases {
            number.numberFormat = .init(style: style, value: 28)
            document.edit.annotations = [number]
            let image = try pixels(document, directory: directory)
            variants.append(image)
            precondition(number.numberLabel.count > 0)
            let decoded = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(document))
            precondition(decoded == document)
        }
        precondition(Set(variants).count == 4, "Each numbering format must render a distinct label")
        let center = number.transformCenter
        number.numberLeader = true
        precondition(number.transformCenter == center && number.drawingBounds.contains(CGPoint(x: 130, y: 100)))
        precondition(number.displayedControl == number.points.last)
        number.rotation = 32
        number.reflection = .init(horizontal: true)
        let local = number.untransformed(number.displayedControl!)
        precondition(hypot(local.x - 130, local.y - 100) < 0.0001)
        number.rotation = nil; number.reflection = nil
        document.edit.annotations = [number]
        let leader = try pixels(document, directory: directory)
        precondition(leader != variants.last! && leader[(100 * 160 + 130) * 4 + 1] < 100)
        var undo = CaptureUndoHistory(), edit = document.edit
        edit.annotations[0].numberLeader = false
        undo.commit(edit, to: &document)
        undo.undo(&document)
        let undone = try pixels(document, directory: directory)
        precondition(undone == leader)
        undo.redo(&document)
        let redone = try pixels(document, directory: directory)
        precondition(redone == variants.last!)
        var pen = CaptureAnnotation(id: UUID(), tool: .pen,
            points: [CGPoint(x: 10, y: 80), CGPoint(x: 40, y: 15), CGPoint(x: 80, y: 110),
                CGPoint(x: 120, y: 20), CGPoint(x: 145, y: 90)], ink: .black)
        document.edit.annotations = [pen]
        let angular = try pixels(document, directory: directory, tolerance: 3)
        pen.smoothed = true
        document.edit.annotations = [pen]
        let smooth = try pixels(document, directory: directory)
        precondition(smooth != angular)
        precondition(pen.points.first == CGPoint(x: 10, y: 80) && pen.points.last == CGPoint(x: 145, y: 90))
        let decodedPen = try JSONDecoder().decode(CaptureAnnotation.self, from: JSONEncoder().encode(pen))
        precondition(decodedPen == pen)
        edit = document.edit
        edit.annotations[0].smoothed = false
        undo.commit(edit, to: &document); undo.undo(&document)
        let restoredSmooth = try pixels(document, directory: directory)
        precondition(restoredSmooth == smooth)
        print("Number formats, bounded values, leaders, transforms, smoothing, PNG/preview and undo passed")
    }

    static func pixels(_ document: CaptureDocument, directory: URL, tolerance: Int = 2) throws -> Data {
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        try CaptureRenderer.png(document: document, directory: directory, to: url)
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let output = rgba(image)
        let preview = rgba(try CaptureRenderer.preview(document: document, directory: directory, maximum: 160))
        let differences = zip(output, preview).map { abs(Int($0) - Int($1)) }
        let maximum = differences.max()!
        if maximum > tolerance {
            let offset = differences.firstIndex(of: maximum)!
            let position = "PNG/preview max=\(maximum) x=\(offset / 4 % 160) y=\(offset / 640)"
            FileHandle.standardError.write(Data("\(position) annotations=\(document.edit.annotations)\n".utf8))
        }
        precondition(maximum <= tolerance)
        return output
    }

    static func rgba(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: 160, height: 128, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 128))
        return Data(bytes: context.data!, count: 160 * 128 * 4)
    }
}
