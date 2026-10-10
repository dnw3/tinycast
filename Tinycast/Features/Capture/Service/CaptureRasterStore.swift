import Foundation

enum CaptureRasterStore {
    nonisolated static func write(
        size: CapturePixelSize, to directory: URL,
        fillRow: (Int, UnsafeMutableRawBufferPointer) throws -> Void
    ) throws {
        let files = FileManager.default
        let temporary = directory.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).capture", isDirectory: true)
        try files.createDirectory(
            at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: temporary) }
        let raster = CaptureRaster(size: size)
        var buffer = [UInt8](repeating: 0, count: size.rowBytes)
        let batchRows = max(1, min(CaptureRaster.tileSide, 1_048_576 / size.rowBytes))
        for band in 0..<raster.rows {
            try Task.checkCancellation()
            let tiles = (0..<raster.columns).compactMap { raster.tile(column: $0, row: band) }
            var handles: [FileHandle] = []
            defer { for handle in handles { try? handle.close() } }
            for tile in tiles {
                let url = temporary.appendingPathComponent(tile.filename)
                guard
                    files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                else {
                    throw CocoaError(.fileWriteUnknown)
                }
                handles.append(try FileHandle(forWritingTo: url))
            }
            let start = band * CaptureRaster.tileSide
            let end = min(size.height, start + CaptureRaster.tileSide)
            var batches = tiles.map { Data(count: $0.rowBytes * batchRows) }
            for row in start..<end {
                try Task.checkCancellation()
                try buffer.withUnsafeMutableBytes { try fillRow(row, $0) }
                let batchRow = (row - start) % batchRows
                for (index, tile) in tiles.enumerated() {
                    let offset = tile.column * CaptureRaster.tileSide * 4
                    batches[index].withUnsafeMutableBytes { destination in
                        buffer.withUnsafeBytes { source in
                            destination.baseAddress!.advanced(by: batchRow * tile.rowBytes).copyMemory(
                                from: source.baseAddress!.advanced(by: offset), byteCount: tile.rowBytes)
                        }
                    }
                    if batchRow == batchRows - 1 || row == end - 1 {
                        try handles[index].write(contentsOf: batches[index].prefix((batchRow + 1) * tile.rowBytes))
                    }
                }
            }
        }
        try JSONEncoder().encode(raster).write(to: temporary.appendingPathComponent("raster.json"))
        try Task.checkCancellation()
        try files.moveItem(at: temporary, to: directory)
    }

    nonisolated static func read(at directory: URL) throws -> CaptureRaster {
        let url = directory.appendingPathComponent("raster.json")
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...4096).contains(size) else { throw CaptureRasterError.invalidTile }
        return try JSONDecoder().decode(CaptureRaster.self, from: Data(contentsOf: url))
    }

    nonisolated static func validate(at directory: URL) throws -> CaptureRaster {
        let raster = try read(at: directory)
        for row in 0..<raster.rows {
            for column in 0..<raster.columns {
                try Task.checkCancellation()
                guard let tile = raster.tile(column: column, row: row) else {
                    throw CaptureRasterError.invalidTile
                }
                let values = try directory.appendingPathComponent(tile.filename).resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                    values.fileSize == tile.byteCount
                else { throw CaptureRasterError.invalidTile }
            }
        }
        return raster
    }
}
