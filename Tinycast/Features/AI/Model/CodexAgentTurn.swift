import Foundation

/// An agent turn's sandbox and approval rules in the app-server's terms, and its rows.
enum CodexAgentTurn {
    /// `on-request` would let a sandboxed command run unasked; armed servers ask even in Read Only.
    static func approvalPolicy(for mode: AgentMode, armed: Bool) -> String {
        mode == .readOnly && !armed ? "never" : "untrusted"
    }

    static func threadSandbox(for mode: AgentMode) -> String {
        mode == .readOnly ? "read-only" : "workspace-write"
    }

    /// The network stays off either way: a command reaching it is a channel nobody approved.
    static func sandboxPolicy(for workspace: AgentWorkspace) -> JSONValue {
        switch workspace.mode {
        case .readOnly:
            .object(["type": .string("readOnly"), "networkAccess": .bool(false)])
        case .ask, .autoEdit:
            .object([
                "type": .string("workspaceWrite"),
                "writableRoots": .array([.string(workspace.folder.standardizedFileURL.path)]),
                "networkAccess": .bool(false),
                "excludeTmpdirEnvVar": .bool(false),
                "excludeSlashTmp": .bool(false)
            ])
        }
    }

    /// The row a `commandExecution` or `fileChange` item starts; every other item has none here.
    static func toolCall(for item: [String: JSONValue]) -> AIStreamEvent? {
        guard let id = item["id"]?.stringValue else { return nil }
        switch item["type"]?.stringValue {
        case "commandExecution":
            let script = ShellWords.script(of: item["command"]?.stringValue ?? "")
            return .toolCall(
                id: id, origin: "", title: ClaudeAgentTool.oneLine(script), kind: .command,
                detail: ChatToolDetail(input: script))
        case "fileChange":
            let changes = CodexApproval.changes(in: item)
            let names = changes.map { ($0.path as NSString).lastPathComponent }
            return .toolCall(
                id: id, origin: "", title: ListFormatter.localizedString(byJoining: names), kind: .edit,
                detail: ChatToolDetail(input: changes.unifiedDiff))
        default:
            return nil
        }
    }

    static func toolResult(for item: [String: JSONValue]) -> AIStreamEvent? {
        guard let id = item["id"]?.stringValue,
            ["commandExecution", "fileChange"].contains(item["type"]?.stringValue)
        else { return nil }
        return .toolResult(
            id: id, isError: item["status"]?.stringValue != "completed",
            output: item["aggregatedOutput"]?.stringValue, exitCode: item["exitCode"]?.intValue)
    }
}
