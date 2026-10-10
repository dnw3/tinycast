import Foundation
import zlib

enum CapturePNGWriter {
    nonisolated static func write(
        size: CapturePixelSize, to url: URL,
        fillRow: (Int, UnsafeMutableRawBufferPointer) throws -> Void
    ) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).png")
        let files = FileManager.default
        guard files.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? files.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let encoder = try Encoder(handle: handle)
        try encoder.write(size: size, fillRow: fillRow)
        try handle.close()
        try Task.checkCancellation()
        if rename(temporary.path, url.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    nonisolated static func write(raster directory: URL, to url: URL) throws {
        let reader = try CaptureRasterReader(directory: directory)
        try write(size: reader.raster.size, to: url, fillRow: reader.read)
    }

    private final class Encoder {
        let handle: FileHandle
        var stream = z_stream()
        var output = [UInt8](repeating: 0, count: 64 * 1024)

        init(handle: FileHandle) throws {
            self.handle = handle
            let result = deflateInit_(
                &stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard result == Z_OK else { throw CaptureRasterError.compressionFailed }
        }

        deinit { deflateEnd(&stream) }

        func write(
            size: CapturePixelSize, fillRow: (Int, UnsafeMutableRawBufferPointer) throws -> Void
        ) throws {
            try handle.write(contentsOf: Data([137, 80, 78, 71, 13, 10, 26, 10]))
            var header = bigEndian(UInt32(size.width)) + bigEndian(UInt32(size.height))
            header.append(contentsOf: [8, 6, 0, 0, 0])
            try chunk("IHDR", header)
            try chunk("sRGB", Data([0]))
            var current = [UInt8](repeating: 0, count: size.rowBytes)
            var previous = current
            var filtered = [UInt8](repeating: 0, count: size.rowBytes + 1)
            filtered[0] = 2
            for row in 0..<size.height {
                try Task.checkCancellation()
                try current.withUnsafeMutableBytes { try fillRow(row, $0) }
                for index in current.indices { filtered[index + 1] = current[index] &- previous[index] }
                try filtered.withUnsafeBufferPointer { try compress($0, finish: false) }
                swap(&previous, &current)
            }
            try compress(UnsafeBufferPointer(start: nil, count: 0), finish: true)
            try chunk("IEND", Data())
        }

        private func compress(_ input: UnsafeBufferPointer<UInt8>, finish: Bool) throws {
            stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress)
            stream.avail_in = uInt(input.count)
            while true {
                let status = output.withUnsafeMutableBufferPointer { bytes in
                    stream.next_out = bytes.baseAddress
                    stream.avail_out = uInt(bytes.count)
                    return deflate(&stream, finish ? Z_FINISH : Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw CaptureRasterError.compressionFailed
                }
                let produced = output.count - Int(stream.avail_out)
                if produced > 0 { try chunk("IDAT", Data(output.prefix(produced))) }
                if finish ? status == Z_STREAM_END : stream.avail_in == 0 { break }
            }
            stream.next_in = nil
            stream.next_out = nil
        }

        private func chunk(_ name: String, _ data: Data) throws {
            try handle.write(contentsOf: bigEndian(UInt32(data.count)))
            let payload = Data(name.utf8) + data
            try handle.write(contentsOf: payload)
            try handle.write(contentsOf: bigEndian(Zlib.crc32(payload)))
        }

        private func bigEndian(_ value: UInt32) -> Data {
            withUnsafeBytes(of: value.bigEndian) { Data($0) }
        }
    }
}
