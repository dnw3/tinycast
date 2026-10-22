import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Every scrolling sample as it was captured, with what the tracker made of it, for offline replay.
struct ScrollDiagnosticsRecorder: Sendable {
    /// About two minutes of sampling while scrolling; past it, a recording only adds disk use.
    static let frameLimit = 2_000

    let directory: URL

    nonisolated static func create(in root: URL, date: Date) throws -> ScrollDiagnosticsRecorder {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = root.appendingPathComponent("scroll-\(formatter.string(from: date))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ScrollDiagnosticsRecorder(directory: directory)
    }

    /// The name carries the pointer's line, which matching needs and the pixels alone do not show.
    nonisolated static func frameName(index: Int, pointer: Int?) -> String {
        String(format: "%05d_p%d.png", index, pointer ?? -1)
    }

    /// The pointer line a frame was recorded with, or nil when the pointer was outside the region.
    nonisolated static func pointer(inFrameNamed name: String) -> Int? {
        guard let marker = name.range(of: "_p"), name.hasSuffix(".png") else { return nil }
        let value = Int(name[marker.upperBound..<name.index(name.endIndex, offsetBy: -4)]) ?? -1
        return value >= 0 ? value : nil
    }

    nonisolated func record(_ image: CGImage, index: Int, pointer: Int?, verdict: String) throws {
        let url = directory.appendingPathComponent(Self.frameName(index: index, pointer: pointer))
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let line = Data("\(Self.frameName(index: index, pointer: pointer))\t\(verdict)\n".utf8)
        let trace = directory.appendingPathComponent("trace.tsv")
        if let handle = try? FileHandle(forWritingTo: trace) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: trace)
        }
    }
}
