import Darwin
import Foundation

struct CaptureQuickSave: Sendable {
    let destination: URL
    let staging: URL

    nonisolated init(directory: URL, createDirectory: Bool, format: CaptureExportOptions.Format,
                     now: Date, id: UUID = UUID()) throws {
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileWriteInvalidFileName) }
        let timestamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        destination = directory.appendingPathComponent("Screenshot-\(timestamp)-\(id).\(format.rawValue)")
        staging = directory.appendingPathComponent(".tinycast-\(UUID()).\(format.rawValue)")
    }

    nonisolated func publish() throws {
        try Task.checkCancellation()
        guard renamex_np(staging.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    nonisolated func discard() { try? FileManager.default.removeItem(at: staging) }
}
