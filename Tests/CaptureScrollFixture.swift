import CoreGraphics
import CoreText
import Foundation

enum CaptureScrollFixture {
    static func verify(in root: URL) throws {
        let page = root.appendingPathComponent("text-page")
        let width = 900, height = 2_400, viewport = 600
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        for index in 0..<35 {
            let top = index * 71
            context.setFillColor(CGColor(gray: index.isMultiple(of: 2) ? 0.96 : 1, alpha: 1))
            context.fill(CGRect(x: 0, y: height - top - 71, width: width, height: 71))
            context.setFillColor(CGColor(gray: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: height - top - 71, width: width, height: 1))
            let text = String(format: "%03d", index + 1)
                + "    Capture fixture \(index + 1) · Tinycast scrolling screenshot · 中文正文 \(index + 1)"
            let attributes = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 0.1, alpha: 1)
            ] as CFDictionary
            let string = CFAttributedStringCreate(nil, text as CFString, attributes)!
            context.textPosition = CGPoint(x: 24, y: height - top - 43)
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
            let code = String(format: "%05d", ((index + 1) * 7_919) % 65_521)
            let label = CFAttributedStringCreate(nil, code as CFString, attributes)!
            context.textPosition = CGPoint(x: 810, y: height - top - 43)
            CTLineDraw(CTLineCreateWithAttributedString(label), context)
        }
        _ = try CaptureImageSource.store(context.makeImage()!, at: page)
        for fixed in [false, true] {
            var previous: ScrollStitchPolicy.Frame?
            let size = try CapturePixelSize(width: width, height: viewport)
            var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size, pieces: [], axis: .vertical)
            for offset in [0, 83, 166, 249] {
                let source = root.appendingPathComponent("text-frame-\(fixed)-\(offset)")
                let reader = try CaptureRasterReader(directory: page)
                try CaptureRasterStore.write(size: size, to: source) { row, buffer in
                    try reader.read(row: row + offset, into: buffer)
                    if fixed, row < 42 || row >= viewport - 20 {
                        for pixel in stride(from: 0, to: buffer.count, by: 4) {
                            buffer[pixel] = 220; buffer[pixel + 1] = 231
                            buffer[pixel + 2] = 242; buffer[pixel + 3] = 255
                        }
                    }
                }
                let frame = try ScrollFrameReader.sample(directory: source, axis: .vertical)
                var displacement: Int?, trailing = 0
                if let previous {
                    let decision = ScrollStitchPolicy.match(previous: previous, current: frame)
                    guard case .append(let shift, _, let fixedTrailing) = decision, shift == 83 else {
                        fatalError("Text rows failed at \(offset), fixed=\(fixed): \(decision)")
                    }
                    displacement = shift
                    trailing = fixedTrailing
                    precondition(ScrollStitchPolicy.match(previous: frame, current: previous) == .reverse)
                }
                let raster = UUID().uuidString
                let plan = try CaptureScrollAppend.plan(
                    document: document, frame: size, raster: raster, offset: displacement, trailing: trailing)
                try ScrollFrameReader.strip(from: source, rect: plan.source, to: root.appendingPathComponent(raster))
                document = plan.document
                precondition(ScrollStitchPolicy.stable(frame, frame))
                precondition(ScrollStitchPolicy.match(previous: frame, current: frame) == .duplicate)
                previous = frame
            }
            let expectedSize = try CapturePixelSize(width: width, height: viewport + 249)
            precondition(document.size == expectedSize)
            let composite = try CaptureCompositeReader(document: document, directory: root)
            let original = try CaptureRasterReader(directory: page)
            var expected = [UInt8](repeating: 0, count: width * 4)
            for row in 0..<document.size.height {
                try expected.withUnsafeMutableBytes { try original.read(row: row, into: $0) }
                if fixed, row < 42 || row >= document.size.height - 20 {
                    for pixel in stride(from: 0, to: expected.count, by: 4) {
                        expected[pixel] = 220; expected[pixel + 1] = 231
                        expected[pixel + 2] = 242; expected[pixel + 3] = 255
                    }
                }
                let actual = try composite.read(rect: CGRect(x: 0, y: row, width: width, height: 1))
                precondition(actual == Data(expected), "Text image mismatch at row \(row), fixed=\(fixed)")
            }
        }
    }
}
