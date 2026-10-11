import Foundation

enum ScrollFrameReader {
    nonisolated static func sample(
        directory: URL, axis: CaptureDocument.Axis
    ) throws -> ScrollStitchPolicy.Frame {
        let reader = try CaptureRasterReader(directory: directory)
        let size = reader.raster.size
        let vertical = axis == .vertical
        let length = vertical ? size.height : size.width
        let cross = vertical ? size.width : size.height
        let lanes = min(32, max(1, cross / 4))
        var rgb = [UInt8](repeating: 0, count: length * lanes * 3)
        var originalRGB = rgb
        var cache: [Int: [UInt8]] = [:]
        func rows(around y: Int) throws -> [[UInt8]] {
            let lower = max(0, y - 2), upper = min(size.height - 1, y + 2)
            cache = cache.filter { (lower...upper).contains($0.key) }
            return try (-2...2).map { delta in
                let rowIndex = min(size.height - 1, max(0, y + delta))
                if let row = cache[rowIndex] { return row }
                var row = [UInt8](repeating: 0, count: size.rowBytes)
                try row.withUnsafeMutableBytes { try reader.read(row: rowIndex, into: $0) }
                cache[rowIndex] = row
                return row
            }
        }
        let positions = (0..<lanes).map { $0 * (cross - 1) / max(1, lanes - 1) }
        if vertical {
            for y in 0..<size.height {
                try Task.checkCancellation()
                let rows = try rows(around: y)
                for (lane, x) in positions.enumerated() {
                    for channel in 0..<3 {
                        originalRGB[(y * lanes + lane) * 3 + channel] = rows[2][x * 4 + channel]
                    }
                    average(rows, x: x, width: size.width, into: &rgb, offset: (y * lanes + lane) * 3)
                }
            }
        } else {
            for (lane, y) in positions.enumerated() {
                try Task.checkCancellation()
                let rows = try rows(around: y)
                for x in 0..<size.width {
                    for channel in 0..<3 {
                        originalRGB[(x * lanes + lane) * 3 + channel] = rows[2][x * 4 + channel]
                    }
                    average(rows, x: x, width: size.width, into: &rgb, offset: (x * lanes + lane) * 3)
                }
            }
        }
        return ScrollStitchPolicy.Frame(length: length, lanes: lanes, rgb: rgb, originalRGB: originalRGB)
    }

    private nonisolated static func average(
        _ rows: [[UInt8]], x: Int, width: Int, into rgb: inout [UInt8], offset: Int
    ) {
        var red = 0, green = 0, blue = 0
        for row in rows {
            for delta in -2...2 {
                let pixel = min(width - 1, max(0, x + delta)) * 4
                red += Int(row[pixel]); green += Int(row[pixel + 1]); blue += Int(row[pixel + 2])
            }
        }
        rgb[offset] = UInt8(red / 25)
        rgb[offset + 1] = UInt8(green / 25)
        rgb[offset + 2] = UInt8(blue / 25)
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
}
