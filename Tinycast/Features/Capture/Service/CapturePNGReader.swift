import Foundation
import zlib

final class CapturePNGReader {
    let size: CapturePixelSize
    private let handle: FileHandle
    private let channels: Int
    private var stream = z_stream()
    private var input = Data()
    private var inputOffset = 0
    private var previous: [UInt8]
    private var filtered: [UInt8]
    private var remaining = 0
    private var chunkType = ""
    private var checksum: uLong = 0
    private var ended = false
    private var row = 0

    enum Failure: Error { case unsupported, corrupt }

    init(url: URL) throws {
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= 300_000_000 else { throw Failure.corrupt }
        handle = try FileHandle(forReadingFrom: url)
        guard try handle.read(upToCount: 8) == Data([137, 80, 78, 71, 13, 10, 26, 10]),
            let header = try handle.read(upToCount: 25), header.count == 25,
            Self.number(header, at: 0) == 13, String(data: header[4..<8], encoding: .ascii) == "IHDR"
        else { throw Failure.unsupported }
        guard Zlib.crc32(Data(header[4..<21])) == Self.number(header, at: 21) else { throw Failure.corrupt }
        size = try CapturePixelSize(
            width: Int(Self.number(header, at: 8)), height: Int(Self.number(header, at: 12)))
        guard header[16] == 8, header[18] == 0, header[19] == 0, header[20] == 0 else {
            throw Failure.unsupported
        }
        switch header[17] {
        case 0: channels = 1
        case 2: channels = 3
        case 4: channels = 2
        case 6: channels = 4
        default: throw Failure.unsupported
        }
        previous = [UInt8](repeating: 0, count: size.width * channels)
        filtered = [UInt8](repeating: 0, count: size.width * channels + 1)
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Failure.corrupt
        }
    }

    deinit { inflateEnd(&stream); try? handle.close() }

    func read(row: Int, into output: UnsafeMutableRawBufferPointer) throws {
        guard row == self.row, row < size.height, output.count == size.rowBytes else { throw Failure.corrupt }
        try inflateRow()
        guard filtered[0] <= 4 else { throw Failure.corrupt }
        previous.withUnsafeMutableBufferPointer { prior in
            filtered.withUnsafeMutableBufferPointer { bytes in
                let pixels = bytes.baseAddress!.advanced(by: 1), above = prior.baseAddress!
                let count = prior.count
                switch bytes[0] {
                case 1:
                    var index = channels
                    while index < count { pixels[index] &+= pixels[index - channels]; index += 1 }
                case 2:
                    var index = 0
                    while index < count { pixels[index] &+= above[index]; index += 1 }
                case 3:
                    var index = 0
                    while index < count {
                        let left = index >= channels ? pixels[index - channels] : 0
                        pixels[index] &+= UInt8((Int(left) + Int(above[index])) / 2)
                        index += 1
                    }
                case 4:
                    var index = 0
                    while index < count {
                        let left = index >= channels ? pixels[index - channels] : 0
                        let corner = index >= channels ? above[index - channels] : 0
                        pixels[index] &+= Self.paeth(left, above[index], corner)
                        index += 1
                    }
                default: break
                }
                if channels == 4 {
                    output.copyMemory(from: UnsafeRawBufferPointer(start: pixels, count: count))
                } else {
                    var x = 0
                    while x < size.width {
                        let index = x * channels
                        output[x * 4] = pixels[index]
                        output[x * 4 + 1] = pixels[index + (channels == 3 ? 1 : 0)]
                        output[x * 4 + 2] = pixels[index + (channels == 3 ? 2 : 0)]
                        output[x * 4 + 3] = channels == 2 ? pixels[index + 1] : 255
                        x += 1
                    }
                }
                above.update(from: pixels, count: count)
            }
        }
        self.row += 1
        if self.row == size.height { try finish() }
    }

    private func inflateRow() throws {
        var written = 0
        while written < filtered.count {
            try Task.checkCancellation()
            if inputOffset == input.count { input = try readCompressed(); inputOffset = 0 }
            guard !input.isEmpty, !ended else { throw Failure.corrupt }
            let status = input.withUnsafeBytes { bytes in
                filtered.withUnsafeMutableBytes { destination in
                    stream.next_in = UnsafeMutablePointer(
                        mutating: bytes.bindMemory(to: Bytef.self).baseAddress!.advanced(by: inputOffset))
                    stream.avail_in = uInt(bytes.count - inputOffset)
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress!.advanced(
                        by: written)
                    stream.avail_out = uInt(destination.count - written)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    inputOffset = bytes.count - Int(stream.avail_in)
                    written = destination.count - Int(stream.avail_out)
                    return status
                }
            }
            guard status == Z_OK || status == Z_STREAM_END else { throw Failure.corrupt }
            ended = status == Z_STREAM_END
        }
    }

    private func finish() throws {
        var byte: UInt8 = 0
        while !ended {
            if inputOffset == input.count { input = try readCompressed(); inputOffset = 0 }
            guard !input.isEmpty else { throw Failure.corrupt }
            let status = input.withUnsafeBytes { bytes in
                withUnsafeMutablePointer(to: &byte) { output in
                    stream.next_in = UnsafeMutablePointer(
                        mutating: bytes.bindMemory(to: Bytef.self).baseAddress!.advanced(by: inputOffset))
                    stream.avail_in = uInt(bytes.count - inputOffset)
                    stream.next_out = output
                    stream.avail_out = 1
                    let result = inflate(&stream, Z_NO_FLUSH)
                    inputOffset = bytes.count - Int(stream.avail_in)
                    return result
                }
            }
            guard stream.avail_out == 1, status == Z_OK || status == Z_STREAM_END else {
                throw Failure.corrupt
            }
            ended = status == Z_STREAM_END
        }
        guard inputOffset == input.count, try readCompressed().isEmpty, chunkType == "IEND" else {
            throw Failure.corrupt
        }
    }

    private func readCompressed() throws -> Data {
        while true {
            if remaining == 0 {
                if !chunkType.isEmpty {
                    guard let crc = try handle.read(upToCount: 4), crc.count == 4,
                        UInt32(checksum) == Self.number(crc, at: 0)
                    else { throw Failure.corrupt }
                    if chunkType == "IEND" { return Data() }
                }
                guard let header = try handle.read(upToCount: 8), header.count == 8,
                    let type = String(data: header[4..<8], encoding: .ascii)
                else { throw Failure.corrupt }
                remaining = Int(Self.number(header, at: 0))
                guard remaining <= 300_000_000 else { throw Failure.corrupt }
                chunkType = type
                checksum = Data(header[4..<8]).withUnsafeBytes {
                    crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, 4)
                }
                if ["tRNS", "iCCP", "gAMA", "cHRM", "cICP"].contains(type) { throw Failure.unsupported }
                if type.first?.isUppercase == true, type != "IDAT", type != "IEND" {
                    throw Failure.unsupported
                }
                if type == "IEND", remaining != 0 { throw Failure.corrupt }
                if remaining == 0 { continue }
            }
            let count = min(65_536, remaining)
            guard let bytes = try handle.read(upToCount: count), bytes.count == count else {
                throw Failure.corrupt
            }
            remaining -= count
            checksum = bytes.withUnsafeBytes {
                crc32(checksum, $0.bindMemory(to: Bytef.self).baseAddress, uInt(bytes.count))
            }
            if chunkType == "IDAT" { return bytes }
        }
    }

    private static func number(_ data: Data, at index: Int) -> UInt32 {
        data[index..<index + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func paeth(_ left: UInt8, _ above: UInt8, _ corner: UInt8) -> UInt8 {
        let prediction = Int(left) + Int(above) - Int(corner)
        let a = abs(prediction - Int(left)), b = abs(prediction - Int(above)),
            c = abs(prediction - Int(corner))
        return a <= b && a <= c ? left : b <= c ? above : corner
    }
}
