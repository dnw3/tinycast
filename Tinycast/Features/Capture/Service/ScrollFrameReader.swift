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
        let margin = lanes > 1 ? edgeMargin(cross: cross) : 0
        let positions = (0..<lanes).map { margin + $0 * (cross - 1 - margin * 2) / max(1, lanes - 1) }
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

    /// Extra lines to retake so the seam falls where both frames agree and nothing is drawn.
    nonisolated static func seam(
        previous: CGImage, current: CGImage, shift: Int, retaken: Int, axis: CaptureDocument.Axis, atStart: Bool
    ) -> Int {
        guard previous.width == current.width, previous.height == current.height,
            let before = try? rows(previous, axis: axis), let after = try? rows(current, axis: axis)
        else { return 0 }
        let length = before.count, room = min(seamReach, length - shift - retaken - 1)
        guard room > 0 else { return 0 }
        var best = (extra: 0, score: Int.max)
        for extra in 0...room {
            // Forward, the cut is that many above the earlier frame's retaken end; back, below its start.
            let earlier = atStart ? retaken + extra : length - retaken - extra - 1
            let later = atStart ? earlier + shift : earlier - shift
            guard (0..<length).contains(later) else { continue }
            var differ = 0, ink = 0
            let line = before[earlier], other = after[later], base = line[0]
            for index in line.indices {
                differ += abs(Int(line[index]) - Int(other[index]))
                ink += abs(Int(line[index]) - Int(base))
            }
            let score = differ * 4 + ink
            if score < best.score { best = (extra, score) }
        }
        return best.extra
    }

    /// Lines a seam may move from the retaken end, about 24pt at 2×: a line of text and its spacing.
    static let seamReach = 48

    /// One row of green per line along the axis, which is all a seam needs to compare.
    private nonisolated static func rows(_ image: CGImage, axis: CaptureDocument.Axis) throws -> [[UInt8]] {
        let size = try CapturePixelSize(width: image.width, height: image.height)
        var pixels = [UInt8](repeating: 0, count: size.rowBytes * size.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: size.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return true
        }
        guard drawn else { throw CaptureRasterError.invalidSize }
        let vertical = axis == .vertical
        let length = vertical ? size.height : size.width, cross = vertical ? size.width : size.height
        return (0..<length).map { line in
            (0..<cross).map { across in
                let x = vertical ? across : line, y = vertical ? line : across
                return pixels[y * size.rowBytes + x * 4 + 1]
            }
        }
    }

    /// Lanes stay clear of both edges, where an overlay scroller moves at its own pace.
    nonisolated static func edgeMargin(cross: Int) -> Int { min(32, cross / 16) }

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
