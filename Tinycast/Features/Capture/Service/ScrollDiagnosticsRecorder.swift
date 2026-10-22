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

    /// The name carries what matching needs and the pixels alone do not show: pointer line and travel.
    nonisolated static func frameName(index: Int, pointer: Int?, travel: Int?) -> String {
        String(format: "%05d_p%d", index, pointer ?? -1) + (travel.map { "_t\($0)" } ?? "") + ".png"
    }

    /// The pointer line and scroll travel a frame was recorded with, each nil when it was not known.
    nonisolated static func marks(inFrameNamed name: String) -> (pointer: Int?, travel: Int?) {
        guard name.hasSuffix(".png") else { return (nil, nil) }
        var pointer: Int?, travel: Int?
        for part in name.dropLast(4).split(separator: "_") {
            if part.hasPrefix("p"), let value = Int(part.dropFirst()), value >= 0 { pointer = value }
            if part.hasPrefix("t"), let value = Int(part.dropFirst()) { travel = value }
        }
        return (pointer, travel)
    }

    nonisolated func record(_ image: CGImage, index: Int, pointer: Int?, travel: Int?, verdict: String) throws {
        let name = Self.frameName(index: index, pointer: pointer, travel: travel)
        let url = directory.appendingPathComponent(name)
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
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
