import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Every scrolling sample as it was captured, with what the tracker made of it, for offline replay.
struct ScrollDiagnosticsRecorder: Sendable {
    /// About half a minute of scrolling as frames arrive; past it, a recording only fills the disk.
    static let frameLimit = 1_200

    let directory: URL

    nonisolated static func create(in root: URL, date: Date) throws -> ScrollDiagnosticsRecorder {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = root.appendingPathComponent("scroll-\(formatter.string(from: date))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ScrollDiagnosticsRecorder(directory: directory)
    }

    /// What matching needs and the pixels do not show: the frames' batch, pointer line and travel.
    nonisolated static func frameName(index: Int, batch: Int?, pointer: Int?, travel: Int?) -> String {
        String(format: "%05d", index) + (batch.map { "_b\($0)" } ?? "") + "_p\(pointer ?? -1)"
            + (travel.map { "_t\($0)" } ?? "") + ".png"
    }

    /// The marks a frame was recorded with, each nil when it was not known.
    nonisolated static func marks(inFrameNamed name: String) -> (batch: Int?, pointer: Int?, travel: Int?) {
        guard name.hasSuffix(".png") else { return (nil, nil, nil) }
        var batch: Int?, pointer: Int?, travel: Int?
        for part in name.dropLast(4).split(separator: "_") {
            if part.hasPrefix("b"), let value = Int(part.dropFirst()) { batch = value }
            if part.hasPrefix("p"), let value = Int(part.dropFirst()), value >= 0 { pointer = value }
            if part.hasPrefix("t"), let value = Int(part.dropFirst()) { travel = value }
        }
        return (batch, pointer, travel)
    }

    /// One frame's pixels; frames are written side by side, so this keeps up with the rate they arrive.
    nonisolated func write(_ image: CGImage, named name: String) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                directory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// One line of the trace, in the order the frames were taken.
    nonisolated func note(_ name: String, verdict: String) throws {
        let line = Data("\(name)\t\(verdict)\n".utf8)
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
