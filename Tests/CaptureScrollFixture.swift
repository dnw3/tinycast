import CoreGraphics
import CoreText
import Foundation

enum CaptureScrollFixture {
    static func verify(in root: URL) throws {
        try browserFrames(in: root)
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
                let frame = try sample(source, axis: .vertical)
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

    static func browserFrames(in root: URL) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CaptureScroll")
        let before = root.appendingPathComponent("browser-before")
        let after = root.appendingPathComponent("browser-after")
        _ = try CaptureImageSource.load(fixtures.appendingPathComponent("fixed-header-before.png"), at: before)
        let size = try CaptureImageSource.load(fixtures.appendingPathComponent("fixed-header-after.png"), at: after)
        try browserRegions(before: before, after: after, size: size, in: root)
        let first = try sample(before, axis: .vertical)
        let second = try sample(after, axis: .vertical)
        precondition(ScrollStitchPolicy.stable(first, first))
        precondition(ScrollStitchPolicy.match(previous: first, current: first) == .duplicate)
        guard case .append(let offset, let leading, let trailing) =
            ScrollStitchPolicy.match(previous: first, current: second)
        else { preconditionFailure("Fixed-header browser frames must register despite text rasterization differences") }
        // A blank margin and the edge clearance are retaken from the newer frame; no pixel changes.
        precondition((279...280).contains(offset) && (62...70).contains(leading) && trailing <= 32 + ScrollStitchPolicy.edgeClearance, "\(offset) \(leading) \(trailing)")
        precondition(ScrollStitchPolicy.match(previous: second, current: first) == .reverse)
        let strip = root.appendingPathComponent("browser-strip")
        try ScrollFrameReader.strip(from: after,
            rect: CGRect(x: 0, y: size.height - offset, width: size.width, height: offset), to: strip)
        let original = try CaptureRasterReader(directory: after), appended = try CaptureRasterReader(directory: strip)
        var originalRow = [UInt8](repeating: 0, count: size.rowBytes)
        var appendedRow = originalRow
        for y in 0..<offset {
            try originalRow.withUnsafeMutableBytes { try original.read(row: size.height - offset + y, into: $0) }
            try appendedRow.withUnsafeMutableBytes { try appended.read(row: y, into: $0) }
            precondition(originalRow == appendedRow, "Registration smoothing must never alter exported strip pixels")
        }
    }

    /// A stored frame sampled as a session samples the live image it was captured as.
    private static func sample(_ directory: URL, axis: CaptureDocument.Axis) throws -> ScrollStitchPolicy.Frame {
        let reader = try CaptureRasterReader(directory: directory)
        let size = reader.raster.size
        var pixels = [UInt8](repeating: 0, count: size.rowBytes * size.height)
        try pixels.withUnsafeMutableBytes { buffer in
            for row in 0..<size.height {
                let start = row * size.rowBytes
                try reader.read(row: row, into: UnsafeMutableRawBufferPointer(rebasing: buffer[start..<(start + size.rowBytes)]))
            }
        }
        let image = CGImage(
            width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
        return try ScrollFrameReader.sample(image, axis: axis)
    }

    private static func browserRegions(before: URL, after: URL, size: CapturePixelSize, in root: URL) throws {
        let regions = [
            CGRect(x: 8, y: 0, width: size.width - 16, height: size.height),
            CGRect(x: 120, y: 0, width: 900, height: size.height),
            CGRect(x: 16, y: 64, width: size.width - 32, height: size.height - 64)
        ]
        for (index, region) in regions.enumerated() {
            let croppedBefore = root.appendingPathComponent("browser-region-before-\(index)")
            let croppedAfter = root.appendingPathComponent("browser-region-after-\(index)")
            try ScrollFrameReader.strip(from: before, rect: region, to: croppedBefore)
            try ScrollFrameReader.strip(from: after, rect: region, to: croppedAfter)
            let first = try sample(croppedBefore, axis: .vertical)
            let second = try sample(croppedAfter, axis: .vertical)
            let decision = ScrollStitchPolicy.match(previous: first, current: second)
            guard case .append(let offset, _, let trailing) = decision,
                (279...280).contains(offset), trailing <= 32 + ScrollStitchPolicy.edgeClearance else {
                preconditionFailure("Browser region \(region) failed: \(decision)")
            }
            precondition(ScrollStitchPolicy.match(previous: second, current: first) == .reverse)
        }
    }
}
