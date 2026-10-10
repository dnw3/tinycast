import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureRasterTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureRasterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try dimensions()
        viewport()
        try pngFilters()
        try roundTrip(in: directory)
        try narrowImages(in: directory)
        try transparency(in: directory)
        try failedWrites(in: directory)
        try damagedTiles(in: directory)
        print("Capture dimensions, viewport, tiles, PNG pixels, cancellation and corruption passed")
    }

    static func dimensions() throws {
        for (width, height) in [(0, 1), (1, 0), (-1, 2), (30_001, 1), (8001, 8000), (Int.max, Int.max)] {
            precondition((try? CapturePixelSize(width: width, height: height)) == nil)
        }
        let size = try CapturePixelSize(width: 1600, height: 30_000)
        precondition(size.byteCount == 192_000_000)
        let raster = CaptureRaster(size: size)
        precondition(raster.columns == 2 && raster.rows == 30)
        precondition(raster.tile(column: 1, row: 29)?.height == 304)
        precondition(raster.tile(column: 1, row: 29)?.width == 576)
        precondition(raster.tile(column: 2, row: 0) == nil)
        precondition(raster.tile(column: -1, row: 0) == nil)
        let invalid = Data("{\"size\":{\"width\":30001,\"height\":1}}".utf8)
        precondition((try? JSONDecoder().decode(CaptureRaster.self, from: invalid)) == nil)
    }

    static func viewport() {
        let viewport = CGSize(width: 800, height: 600)
        let vertical = CGSize(width: 1600, height: 30_000)
        precondition(CaptureViewportPolicy.scale(image: vertical, viewport: viewport, fit: .width) == 0.5)
        precondition(CaptureViewportPolicy.scale(image: vertical, viewport: viewport, fit: .window) == 0.02)
        let horizontal = CGSize(width: 30_000, height: 1200)
        precondition(CaptureViewportPolicy.scale(image: horizontal, viewport: viewport, fit: .height) == 0.5)
        precondition(CaptureViewportPolicy.scale(image: .zero, viewport: viewport, fit: .window) == 1)
        precondition(CaptureViewportPolicy.preferredFit(image: vertical) == .width)
        precondition(CaptureViewportPolicy.preferredFit(image: horizontal) == .height)
        precondition(CaptureViewportPolicy.preferredFit(image: CGSize(width: 1200, height: 800)) == .window)
        precondition(CaptureViewportPolicy.preferredFit(image: .zero) == .window)
        precondition(CaptureViewportPolicy.preferredFit(image: CGSize(width: CGFloat.infinity, height: 800)) == .window)
    }

    static func pngFilters() throws {
        for (kind, channels) in [(0, 1), (2, 3), (4, 2), (6, 4)] {
            for first in 0..<5 {
                let file = URL(fileURLWithPath: "Tests/Fixtures/capture/png-filters/\(kind)-\(first).png")
                let reader = try CapturePNGReader(url: file)
                precondition(reader.size.width == 17 && reader.size.height == 10)
                var row = [UInt8](repeating: 0, count: reader.size.rowBytes)
                for y in 0..<10 {
                    try row.withUnsafeMutableBytes { try reader.read(row: y, into: $0) }
                    for x in 0..<17 {
                        let pixel = (0..<channels).map { UInt8((x * 67 + y * 31 + $0 * 43) % 256) }
                        let expected = channels >= 3 ? Array(pixel.prefix(3)) : Array(repeating: pixel[0], count: 3)
                        let alpha = channels == 4 ? pixel[3] : channels == 2 ? pixel[1] : 255
                        precondition(Array(row[(x * 4)..<(x * 4 + 4)]) == expected + [alpha])
                    }
                }
            }
        }
    }

    static func roundTrip(in root: URL) throws {
        let size = try CapturePixelSize(width: 1031, height: 1043)
        let raster = root.appendingPathComponent("round-trip", isDirectory: true)
        let output = root.appendingPathComponent("output.png")
        try CaptureRasterStore.write(size: size, to: raster, fillRow: CaptureFixture.fill)
        let reader = try CaptureRasterReader(directory: raster)
        precondition(reader.raster.size == size)
        var actual = [UInt8](repeating: 0, count: size.rowBytes)
        var expected = actual
        for row in [0, 1023, 1024, 1042, 500, 1024] {
            try actual.withUnsafeMutableBytes { try reader.read(row: row, into: $0) }
            expected.withUnsafeMutableBytes { CaptureFixture.fill(row: row, buffer: $0) }
            precondition(actual == expected, "Tile seam or backward read changed pixels")
        }
        try CapturePNGWriter.write(raster: raster, to: output)
        try CaptureFixture.verifyPNG(at: output, size: size)
        try CapturePNGWriter.write(size: size, to: output, fillRow: CaptureFixture.fill)
        try CaptureFixture.verifyPNG(at: output, size: size)
    }

    static func failedWrites(in root: URL) throws {
        let size = try CapturePixelSize(width: 1031, height: 1043)
        let raster = root.appendingPathComponent("cancelled", isDirectory: true)
        let output = root.appendingPathComponent("existing.png")
        let sentinel = Data("existing output".utf8)
        try sentinel.write(to: output)
        let throwing: (Int, UnsafeMutableRawBufferPointer) throws -> Void = { row, buffer in
            if row == 1025 { throw CancellationError() }
            CaptureFixture.fill(row: row, buffer: buffer)
        }
        do {
            try CaptureRasterStore.write(size: size, to: raster, fillRow: throwing)
            preconditionFailure("A cancelled raster must not publish")
        } catch is CancellationError {}
        precondition(!FileManager.default.fileExists(atPath: raster.path))
        do {
            try CapturePNGWriter.write(size: size, to: output, fillRow: throwing)
            preconditionFailure("A cancelled export must not commit")
        } catch is CancellationError {}
        let preserved = try Data(contentsOf: output)
        precondition(preserved == sentinel)
        let children = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(!children.contains { $0.hasPrefix(".") }, "Failed writes left temporary data")
    }

    static func narrowImages(in root: URL) throws {
        for (width, height) in [(1, 1), (1, 2049), (2049, 1)] {
            let size = try CapturePixelSize(width: width, height: height)
            let raster = root.appendingPathComponent("narrow-\(width)-\(height)")
            let output = root.appendingPathComponent("narrow-\(width)-\(height).png")
            try CaptureRasterStore.write(size: size, to: raster, fillRow: CaptureFixture.fill)
            try CapturePNGWriter.write(raster: raster, to: output)
            try CaptureFixture.verifyPNG(at: output, size: size)
        }
    }

    static func transparency(in root: URL) throws {
        let size = try CapturePixelSize(width: 2, height: 1)
        let output = root.appendingPathComponent("transparent.png")
        try CapturePNGWriter.write(size: size, to: output) { _, buffer in
            buffer.copyBytes(from: [UInt8](arrayLiteral: 255, 0, 0, 128, 0, 0, 0, 0))
        }
        let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        let bytes = UnsafeRawBufferPointer(start: context.data!, count: 8)
        precondition(Array(bytes) == [128, 0, 0, 128, 0, 0, 0, 0], "PNG must use straight alpha")
    }

    static func damagedTiles(in root: URL) throws {
        let size = try CapturePixelSize(width: 1025, height: 2)
        let raster = root.appendingPathComponent("damaged", isDirectory: true)
        try CaptureRasterStore.write(size: size, to: raster, fillRow: CaptureFixture.fill)
        try Data().write(to: raster.appendingPathComponent("1-0.rgba"))
        let reader = try CaptureRasterReader(directory: raster)
        var row = [UInt8](repeating: 0, count: size.rowBytes)
        do {
            try row.withUnsafeMutableBytes { try reader.read(row: 0, into: $0) }
            preconditionFailure("A damaged tile must not become blank output")
        } catch CaptureRasterError.invalidTile {}
        do {
            try row.withUnsafeMutableBytes { try reader.read(row: 2, into: $0) }
            preconditionFailure("An out-of-range row must fail")
        } catch CaptureRasterError.invalidRow {}
    }
}
