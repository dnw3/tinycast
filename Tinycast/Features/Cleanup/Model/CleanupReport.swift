import Darwin
import Foundation

enum CleanupFailure: Error, Equatable, Sendable {
    case permissionDenied
    case inUse
    case readOnly
    case refused(CleanupRefusal)
    case running(String)
    case cancelled
    case other(Int32)
    /// The tool's cleanup exited non-zero; carries the tail of what it printed.
    case toolFailed(String)
    case toolMissing

    /// Nil for ENOENT: an item already gone is done, not failed.
    static func from(errno code: Int32) -> CleanupFailure? {
        switch code {
        case ENOENT, ENOTDIR: return nil
        case EACCES, EPERM: return .permissionDenied
        case EBUSY, ETXTBSY: return .inUse
        case EROFS: return .readOnly
        case ECANCELED: return .cancelled
        default: return .other(code)
        }
    }
}

/// Our own tally is the headline; the volume reading is only a hint, since snapshots hold blocks.
struct CleanupReport: Equatable, Sendable {
    struct Failure: Equatable, Sendable {
        let name: String
        let path: String
        let reason: CleanupFailure
    }

    private(set) var deletedBytes: Int64 = 0
    private(set) var trashedBytes: Int64 = 0
    private(set) var deletedCount = 0
    private(set) var trashedCount = 0
    private(set) var evictedBytes: Int64 = 0
    private(set) var evictedCount = 0
    private(set) var failures: [Failure] = []
    /// Fall in `volumeAvailableCapacity` across the run; nil when either reading failed.
    var volumeGain: Int64?

    var removedBytes: Int64 { deletedBytes + trashedBytes + evictedBytes }
    var removedCount: Int { deletedCount + trashedCount + evictedCount }
    var hasFailures: Bool { !failures.isEmpty }

    mutating func recordDeleted(bytes: Int64) {
        deletedBytes += bytes
        deletedCount += 1
    }

    mutating func recordTrashed(bytes: Int64) {
        trashedBytes += bytes
        trashedCount += 1
    }

    mutating func recordEvicted(bytes: Int64) {
        evictedBytes += bytes
        evictedCount += 1
    }

    mutating func recordFailure(name: String, path: String, reason: CleanupFailure) {
        failures.append(Failure(name: name, path: path, reason: reason))
    }

    /// Readings move by tens of megabytes on their own, so small differences say nothing.
    static let volumeNoiseFloor: Int64 = 64 << 20

    /// True when the disk gave back far less than was deleted, which local snapshots explain.
    var isHeldBySnapshots: Bool {
        guard let volumeGain, deletedBytes >= 4 * Self.volumeNoiseFloor else { return false }
        return volumeGain < deletedBytes / 2
    }
}
