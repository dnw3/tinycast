import CoreGraphics
import Foundation
import ImageIO

enum CaptureFixture {
    static func fill(row: Int, buffer: UnsafeMutableRawBufferPointer) {
        let bytes = buffer.bindMemory(to: UInt8.self)
        for x in 0..<(buffer.count / 4) {
            bytes[x * 4] = UInt8((x / 11 + row / 29) % 256)
            bytes[x * 4 + 1] = UInt8((x / 17 + row / 7) % 256)
            bytes[x * 4 + 2] = UInt8((x / 31 + row / 13) % 256)
            bytes[x * 4 + 3] = 255
        }
    }

    static func fillNoise(row: Int, buffer: UnsafeMutableRawBufferPointer) {
        let bytes = buffer.bindMemory(to: UInt8.self)
        for x in 0..<(buffer.count / 4) {
            var value = UInt64(row) &* 0x9E3779B97F4A7C15 &+ UInt64(x)
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            bytes[x * 4] = UInt8(truncatingIfNeeded: value)
            bytes[x * 4 + 1] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[x * 4 + 2] = UInt8(truncatingIfNeeded: value >> 16)
            bytes[x * 4 + 3] = 255
        }
    }

    static func verifyPNG(
        at url: URL, size: CapturePixelSize,
        fillRow: (Int, UnsafeMutableRawBufferPointer) -> Void = CaptureFixture.fill
    ) throws {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(image.width == size.width && image.height == size.height)
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
            bytesPerRow: size.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let decoded = context.data!.assumingMemoryBound(to: UInt8.self)
        var expected = [UInt8](repeating: 0, count: size.rowBytes)
        for row in 0..<size.height {
            expected.withUnsafeMutableBytes { fillRow(row, $0) }
            for byte in expected.indices {
                precondition(decoded[row * size.rowBytes + byte] == expected[byte], "PNG changed a pixel")
            }
        }
    }

}
