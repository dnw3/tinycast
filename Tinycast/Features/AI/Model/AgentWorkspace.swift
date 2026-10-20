import Foundation

/// Where a chat's agent works and how freely; a chat with none stays an ordinary chat.
struct AgentWorkspace: Codable, Equatable, Sendable {
    var folder: URL
    var mode: AgentMode

    /// The folder's path with a trailing separator, so `/a/bc` is never inside `/a/b`.
    var root: String {
        let path = folder.standardizedFileURL.path
        return path.hasSuffix("/") ? path : path + "/"
    }

    /// Whether `path`, resolved against the folder, stays inside it.
    func contains(_ path: String) -> Bool {
        let resolved = path.hasPrefix("/")
            ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
        let standardized = resolved.standardizedFileURL.path
        return standardized + "/" == root || standardized.hasPrefix(root)
    }

    /// A move counts as inside only when it both starts and ends there.
    func contains(_ change: AgentApprovalRequest.FileChange) -> Bool {
        contains(change.path) && contains(change.target)
    }
}
