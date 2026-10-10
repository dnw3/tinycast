import Darwin
import Foundation

final class CaptureSource: Sendable {
    let directory: URL
    private let lease: Int32

    init(directory: URL) throws {
        self.directory = directory
        let descriptor = open(
            directory.appendingPathComponent(".lease").path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CaptureRasterError.invalidTile }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw CaptureRasterError.invalidTile
        }
        lease = descriptor
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
        close(lease)
    }
}
