import Foundation

/// What the effect layer read about one iCloud Drive file, at one moment.
struct CleanupCloudEvidence: Equatable, Sendable {
    let isUbiquitous: Bool
    /// The local copy matches the newest version in iCloud.
    let isCurrent: Bool
    let isUploaded: Bool
    let isUploading: Bool
    let hasConflicts: Bool
    let bytes: Int64
}

/// Removing a download frees its space and keeps the file in iCloud, where Finder fetches it on
/// open; only a file iCloud already holds in full qualifies.
enum CleanupCloudPolicy {
    static let root = "Library/Mobile Documents"
    static let minimumBytes: Int64 = 20 << 20

    static func qualifies(_ evidence: CleanupCloudEvidence) -> Bool {
        evidence.isUbiquitous && evidence.isCurrent && evidence.isUploaded && !evidence.isUploading
            && !evidence.hasConflicts && evidence.bytes >= minimumBytes
    }

    static func isLocation(_ relative: [String]) -> Bool {
        let prefix = root.split(separator: "/").map(String.init)
        guard relative.count > prefix.count + 1, Array(relative.prefix(prefix.count)) == prefix else { return false }
        return !relative.dropFirst(prefix.count).contains { $0.hasPrefix(".") }
    }
}
