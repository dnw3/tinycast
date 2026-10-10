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
        var row = [UInt8](repeating: 0, count: size.rowBytes)
        let positions = (0..<lanes).map { $0 * (cross - 1) / max(1, lanes - 1) }
        if vertical {
            for y in 0..<size.height {
                try Task.checkCancellation()
                try row.withUnsafeMutableBytes { try reader.read(row: y, into: $0) }
                for (lane, x) in positions.enumerated() {
                    for channel in 0..<3 { rgb[(y * lanes + lane) * 3 + channel] = row[x * 4 + channel] }
                }
            }
        } else {
            for (lane, y) in positions.enumerated() {
                try Task.checkCancellation()
                try row.withUnsafeMutableBytes { try reader.read(row: y, into: $0) }
                for x in 0..<size.width {
                    for channel in 0..<3 { rgb[(x * lanes + lane) * 3 + channel] = row[x * 4 + channel] }
                }
            }
        }
        return ScrollStitchPolicy.Frame(length: length, lanes: lanes, rgb: rgb)
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
