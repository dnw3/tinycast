import CoreGraphics
import CoreText
import Foundation
import ImageIO

@main
struct CaptureTextFormatTests {
    static func main() throws {
        let text = "Hello 中文 👩🏽‍💻\né motion"
        var format = CaptureTextFormat(base: CaptureTextStyle())
        let hello = NSRange(location: 0, length: 5)
        precondition(format.apply(.bold(true), to: hello, in: text))
        let chinese = (text as NSString).range(of: "中文")
        precondition(format.apply(.italic(true), to: chinese, in: text))
        precondition(format.style(at: 0).bold && !format.style(at: chinese.location).bold)
        precondition(format.style(at: chinese.location).italic && format.isValid(for: text))
        let emoji = (text as NSString).range(of: "👩🏽‍💻")
        let old = format
        precondition(!format.apply(.underline(true), to: NSRange(location: emoji.location + 1, length: 1), in: text))
        precondition(format == old)
        precondition(!format.apply(.size(.infinity), to: hello, in: text) && format == old)
        precondition(!format.apply(.bold(true), to: NSRange(location: Int.max, length: Int.max), in: text))
        var invalid = format
        invalid.runs.append(.init(location: 0, length: 1, style: format.base))
        precondition(!invalid.isValid(for: text))
        invalid.runs = [.init(location: emoji.location, length: 1, style: format.base)]
        precondition(!invalid.isValid(for: text))
        invalid.runs = Array(repeating: .init(location: 0, length: 1, style: format.base), count: 513)
        precondition(!invalid.isValid(for: text))
        let whole = NSRange(location: 0, length: text.utf16.count)
        precondition(format.apply(.underline(true), to: whole, in: text))
        precondition(format.style(at: chinese.location).italic && format.style(at: 0).bold)
        precondition(format.style(at: emoji.location).underline)
        var legacy = CaptureAnnotation(id: UUID(), tool: .text, points: [.zero, CGPoint(x: 100, y: 100)],
            ink: .red, text: "Legacy", font: .serif, fontSize: 32)
        legacy = try JSONDecoder().decode(CaptureAnnotation.self, from: JSONEncoder().encode(legacy))
        precondition(legacy.textFormat == nil && legacy.effectiveTextFormat.base.font == .serif)
        precondition(legacy.effectiveTextFormat.base.size == 32 && legacy.isValid)
        let decoded = try JSONDecoder().decode(CaptureTextFormat.self, from: JSONEncoder().encode(format))
        precondition(decoded == format)
        for family in CaptureAnnotation.Font.allCases {
            var style = CaptureTextStyle(font: family)
            style.bold = true; style.italic = true
            let traits = CTFontGetSymbolicTraits(CaptureTextRenderer.font(style))
            precondition(traits.contains(.boldTrait) && traits.contains(.italicTrait), "Font traits must render")
        }
        try render()
        print("Text runs, Unicode boundaries, traits, decorations, alignment, wrapping and final PNG passed")
    }

    static func render() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = try CapturePixelSize(width: 320, height: 200), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: directory.appendingPathComponent(raster)) { _, row in
            row.initializeMemory(as: UInt8.self, repeating: 255)
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 320, height: 200), origin: .zero)])
        var annotation = CaptureAnnotation(id: UUID(), tool: .text,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 300, y: 180)], ink: .black,
            text: "Hello World", font: .system, fontSize: 24,
            textFormat: CaptureTextFormat(base: CaptureTextStyle()))
        document.edit.annotations = [annotation]
        let plain = try pixels(document, directory: directory)
        let changes: [CaptureTextChange] = [.bold(true), .italic(true), .underline(true), .strikethrough(true),
            .background(CaptureColor(red: 255, green: 255, blue: 0)),
            .outline(CaptureColor(red: 255, green: 0, blue: 0)), .alignment(.center), .alignment(.right)]
        for change in changes {
            var format = annotation.textFormat!
            precondition(format.apply(change, to: NSRange(location: 0, length: annotation.text.utf16.count),
                in: annotation.text))
            document.edit.annotations[0].textFormat = format
            let styled = try pixels(document, directory: directory)
            precondition(styled != plain, "Each style must alter final output pixels")
            switch change {
            case .background:
                precondition(stride(from: 0, to: styled.count, by: 4).contains {
                    styled[$0] > 240 && styled[$0 + 1] > 240 && styled[$0 + 2] < 10
                })
            case .outline:
                precondition(stride(from: 0, to: styled.count, by: 4).contains {
                    Int(styled[$0]) > Int(styled[$0 + 1]) + 20 && styled[$0 + 1] < 100
                })
            case .alignment:
                precondition((20..<60).allSatisfy { x in (20..<60).allSatisfy { styled[($0 * 320 + x) * 4] == 255 } })
            default: break
            }
        }
        annotation.text = "Hello 中文 👩🏽‍💻 multiple lines and mixed styles"
        annotation.textFormat = CaptureTextFormat(base: CaptureTextStyle())
        precondition(annotation.textFormat!.apply(.bold(true), to: NSRange(location: 0, length: 5), in: annotation.text))
        document.edit.annotations = [annotation]
        let wide = try pixels(document, directory: directory)
        document.edit.annotations[0].points[1].x = 140
        let narrow = try pixels(document, directory: directory)
        precondition(wide != narrow && document.edit.annotations[0].textFormat == annotation.textFormat)
        precondition((65..<155).contains { y in (20..<140).contains { narrow[(y * 320 + $0) * 4] < 128 } })
        let restored = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(document)).validated()
        let reopened = try pixels(restored, directory: directory)
        precondition(reopened == narrow)
        let archive = directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        let archived = try CaptureSourceArchive.copy(document: document, from: directory, to: archive)
        let archivedPixels = try pixels(archived, directory: archive)
        precondition(archivedPixels == narrow)
        for axis in CaptureDocument.Axis.allCases {
            let flipped = try CaptureReflection.flip(document, axis: axis)
            let result = try pixels(flipped, directory: directory)
            var maximumDifference = 0
            var differences = 0
            for y in 0..<200 {
                for x in 0..<320 {
                    let source = (y * 320 + x) * 4
                    let target = ((axis == .vertical ? 199 - y : y) * 320 + (axis == .horizontal ? 319 - x : x)) * 4
                    for channel in 0..<4 {
                        let difference = abs(Int(narrow[source + channel]) - Int(result[target + channel]))
                        maximumDifference = max(maximumDifference, difference)
                        if difference > 2 { differences += 1 }
                    }
                }
            }
            precondition(maximumDifference <= 2, "\(axis) mirror: maximum \(maximumDifference), differences \(differences)")
        }
        var undo = CaptureUndoHistory(), edited = document.edit
        edited.annotations[0].textFormat!.base.strikethrough = true
        undo.commit(edited, to: &document)
        undo.undo(&document)
        let undone = try pixels(document, directory: directory)
        precondition(undone == narrow)
        undo.redo(&document)
        precondition(document.edit == edited)
    }

    static func pixels(_ document: CaptureDocument, directory: URL) throws -> [UInt8] {
        let file = directory.appendingPathComponent(UUID().uuidString + ".png")
        try CaptureRenderer.png(document: document, directory: directory, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(file as CFURL, nil)!, 0, nil)!
        let preview = try CaptureRenderer.preview(document: document, directory: directory, maximum: 320)
        let output = rgba(decoded), expected = rgba(preview)
        let differences = output.indices.filter { abs(Int(output[$0]) - Int(expected[$0])) > 2 }
        if !differences.isEmpty {
            let detail = differences.prefix(10).map { "\($0 / 1280),\(($0 % 1280) / 4):\(output[$0])/\(expected[$0])" }
            let message = "\(document.edit.annotations[0].textFormat!) \(differences.count) \(detail)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        precondition(differences.isEmpty)
        return output
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 1280,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 200))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 320 * 200 * 4))
    }
}
