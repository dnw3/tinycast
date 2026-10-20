import CoreGraphics
import Foundation

enum ScrollFrameReader {
    /// Drawn as a stored raster is, so a sample sees the pixels its strip will be cut from.
    nonisolated static func sample(
        _ image: CGImage, axis: CaptureDocument.Axis
    ) throws -> ScrollStitchPolicy.Frame {
        let size = try CapturePixelSize(width: image.width, height: image.height)
        var pixels = [UInt8](repeating: 0, count: size.rowBytes * size.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                    bytesPerRow: size.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        guard drawn else { throw CaptureRasterError.invalidSize }
        let vertical = axis == .vertical
        let length = vertical ? size.height : size.width
        let cross = vertical ? size.width : size.height
        let lanes = min(32, max(1, cross / 4))
        var rgb = [UInt8](repeating: 0, count: length * lanes * 3)
        var originalRGB = rgb
        let positions = (0..<lanes).map { $0 * (cross - 1) / max(1, lanes - 1) }
        pixels.withUnsafeBufferPointer { pixels in
            for line in 0..<length {
                for (lane, across) in positions.enumerated() {
                    let x = vertical ? across : line, y = vertical ? line : across
                    let offset = (line * lanes + lane) * 3
                    var sum = (0, 0, 0)
                    for dy in -2...2 {
                        let row = min(size.height - 1, max(0, y + dy)) * size.rowBytes
                        for dx in -2...2 {
                            let pixel = row + min(size.width - 1, max(0, x + dx)) * 4
                            sum.0 += Int(pixels[pixel]); sum.1 += Int(pixels[pixel + 1]); sum.2 += Int(pixels[pixel + 2])
                        }
                    }
                    rgb[offset] = UInt8(sum.0 / 25)
                    rgb[offset + 1] = UInt8(sum.1 / 25)
                    rgb[offset + 2] = UInt8(sum.2 / 25)
                    let center = y * size.rowBytes + x * 4
                    for channel in 0..<3 { originalRGB[offset + channel] = pixels[center + channel] }
                }
            }
        }
        return ScrollStitchPolicy.Frame(length: length, lanes: lanes, rgb: rgb, originalRGB: originalRGB)
    }

    nonisolated static func strip(from source: URL, rect: CGRect, to destination: URL) throws {
        let reader = try CaptureRasterReader(directory: source)
        guard CaptureGeometry.valid(rect), rect == rect.integral,
            CGRect(x: 0, y: 0, width: reader.raster.size.width, height: reader.raster.size.height).contains(
                rect)
        else { throw CaptureRasterError.invalidRow }
        let size = try CapturePixelSize(width: Int(rect.width), height: Int(rect.height))
        var row = [UInt8](repeating: 0, count: reader.raster.size.rowBytes)
        try CaptureRasterStore.write(size: size, to: destination) { y, output in
            try row.withUnsafeMutableBytes { try reader.read(row: y + Int(rect.minY), into: $0) }
            row.withUnsafeBytes {
                output.copyMemory(
                    from: UnsafeRawBufferPointer(
                        start: $0.baseAddress!.advanced(by: Int(rect.minX) * 4), count: output.count))
            }
        }
    }

    /// A live frame's strip: only the strip's lines are written, never the whole frame.
    nonisolated static func strip(_ image: CGImage, rect: CGRect, to destination: URL) throws {
        guard CaptureGeometry.valid(rect), rect == rect.integral,
            CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(rect),
            let cropped = image.cropping(to: rect)
        else { throw CaptureRasterError.invalidRow }
        _ = try CaptureImageSource.store(cropped, at: destination)
    }
}
