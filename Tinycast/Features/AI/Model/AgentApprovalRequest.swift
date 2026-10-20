import Foundation

/// Something an agent asked to do that Tinycast answers before it happens.
struct AgentApprovalRequest: Identifiable, Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case command(String)
        /// A command its own CLI reads as only reading, searching or listing these absolute paths.
        case inspection(command: String, paths: [String])
        case fileChanges([FileChange])
        /// A read the agent's own rules route to the host, which means it is outside the folder.
        case read(String)
        case tool(name: String, summary: String)
    }

    struct FileChange: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case add
            case delete
            case update
            case move(to: String)
        }

        let path: String
        let kind: Kind
        /// A unified diff, or the whole new text for an added file; empty when the route sent none.
        let diff: String

        /// Where the change leaves the file: its new path for a move, its own path otherwise.
        var target: String {
            if case .move(let destination) = kind { return destination }
            return path
        }
    }

    let id: String
    let action: Action
    /// The agent's own explanation, when it gave one.
    let reason: String?

    init(id: String, action: Action, reason: String? = nil) {
        self.id = id
        self.action = action
        self.reason = reason
    }

    /// Only a read leaves the folder as it was; a tool's effect is unknown, so it counts.
    var changesSomething: Bool { inspectedPaths == nil }

    /// What a request that only looks would look at; `nil` for one that may change something.
    var inspectedPaths: [String]? {
        switch action {
        case .read(let path): [path]
        case .inspection(_, let paths): paths
        case .command, .fileChanges, .tool: nil
        }
    }

    /// Deleting is asked about every time: no mode and no chat grant lets it through unseen.
    var deletes: Bool {
        guard case .fileChanges(let changes) = action else { return false }
        return changes.contains { $0.kind == .delete }
    }
}

extension Array where Element == AgentApprovalRequest.FileChange {
    /// Each file under the `---` / `+++` header a unified diff names it with.
    var unifiedDiff: String {
        map { change in
            let before = change.kind == .add ? "/dev/null" : change.path
            let after = change.kind == .delete ? "/dev/null" : change.target
            return "--- \(before)\n+++ \(after)\n\(Self.hunks(of: change))"
        }
        .joined(separator: "\n")
    }

    /// Codex sends an added or deleted file as its plain text, which a diff marks line by line.
    private static func hunks(of change: AgentApprovalRequest.FileChange) -> String {
        let mark: String
        switch change.kind {
        case .add: mark = "+"
        case .delete: mark = "-"
        case .update, .move: return change.diff
        }
        guard !change.diff.isEmpty, !change.diff.hasPrefix("@@") else { return change.diff }
        var lines = change.diff.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines.map { mark + $0 }.joined(separator: "\n")
    }
}
