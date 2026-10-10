import Darwin
import Foundation

final class CaptureRasterReader {
    let raster: CaptureRaster
    private let directory: URL
    private var band = -1
    private var descriptors: [Int32] = []

    init(directory: URL) throws {
        self.directory = directory
        raster = try CaptureRasterStore.read(at: directory)
    }

    deinit { closeBand() }

    func read(row: Int, into buffer: UnsafeMutableRawBufferPointer) throws {
        guard (0..<raster.size.height).contains(row), buffer.count == raster.size.rowBytes else {
            throw CaptureRasterError.invalidRow
        }
        let nextBand = row / CaptureRaster.tileSide
        if band != nextBand { try openBand(nextBand) }
        for (column, descriptor) in descriptors.enumerated() {
            guard let tile = raster.tile(column: column, row: band) else {
                throw CaptureRasterError.invalidTile
            }
            let destination = buffer.baseAddress!.advanced(by: column * CaptureRaster.tileSide * 4)
            let offset = off_t((row % CaptureRaster.tileSide) * tile.rowBytes)
            var received = 0
            while received < tile.rowBytes {
                let count = pread(
                    descriptor, destination.advanced(by: received), tile.rowBytes - received,
                    offset + off_t(received))
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw CaptureRasterError.invalidTile }
                received += count
            }
        }
    }

    private func openBand(_ nextBand: Int) throws {
        closeBand()
        do {
            for column in 0..<raster.columns {
                guard let tile = raster.tile(column: column, row: nextBand) else {
                    throw CaptureRasterError.invalidTile
                }
                let url = directory.appendingPathComponent(tile.filename)
                let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                guard descriptor >= 0 else { throw CaptureRasterError.invalidTile }
                descriptors.append(descriptor)
                var metadata = stat()
                guard fstat(descriptor, &metadata) == 0,
                    metadata.st_mode & S_IFMT == S_IFREG,
                    metadata.st_size == tile.byteCount
                else { throw CaptureRasterError.invalidTile }
            }
            band = nextBand
        } catch {
            closeBand()
            throw error
        }
    }

    private func closeBand() {
        for descriptor in descriptors { close(descriptor) }
        descriptors.removeAll(keepingCapacity: true)
        band = -1
    }
}
