import Foundation

/// The app-server asking before a command runs or a patch applies, as one agent turn sees it.
struct CodexApproval: Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        /// `inspects`: what Codex's reading of the command says it only looks at, if that is all.
        case command(String, inspects: [String]?)
        /// The patch came earlier, on the item's `item/started`; the ask names only the item.
        case fileChange
    }

    static let commandMethod = "item/commandExecution/requestApproval"
    static let fileChangeMethod = "item/fileChange/requestApproval"

    let threadID: String
    let itemID: String
    let subject: Subject
    let reason: String?

    init?(method: String, params: [String: JSONValue]) {
        guard let threadID = params["threadId"]?.stringValue,
            let itemID = params["itemId"]?.stringValue
        else { return nil }
        switch method {
        case Self.commandMethod:
            subject = .command(
                ShellWords.script(of: params["command"]?.stringValue ?? ""),
                inspects: Self.inspectedPaths(params["commandActions"], in: params["cwd"]?.stringValue))
        case Self.fileChangeMethod:
            subject = .fileChange
        default:
            return nil
        }
        self.threadID = threadID
        self.itemID = itemID
        reason = params["reason"]?.stringValue
    }

    func request(changes: [AgentApprovalRequest.FileChange]) -> AgentApprovalRequest {
        switch subject {
        case .command(let line, let paths?):
            AgentApprovalRequest(id: itemID, action: .inspection(command: line, paths: paths), reason: reason)
        case .command(let line, nil):
            AgentApprovalRequest(id: itemID, action: .command(line), reason: reason)
        case .fileChange:
            AgentApprovalRequest(id: itemID, action: .fileChanges(changes), reason: reason)
        }
    }

    /// Never `acceptForSession` or an amendment: those outlive the turn; Tinycast keeps grants.
    static func result(for decision: AgentApprovalDecision) -> [String: Any] {
        ["decision": decision.allows ? "accept" : "decline"]
    }

    /// Only when every part reads, searches or lists; a missing path is the working directory.
    static func inspectedPaths(_ actions: JSONValue?, in directory: String?) -> [String]? {
        guard let actions = actions?.arrayValue, !actions.isEmpty, let directory else { return nil }
        var paths: [String] = []
        for action in actions {
            guard let fields = action.objectValue,
                ["read", "search", "listFiles"].contains(fields["type"]?.stringValue)
            else { return nil }
            let path = fields["path"]?.stringValue ?? "."
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path) : URL(fileURLWithPath: directory).appendingPathComponent(path)
            paths.append(url.standardizedFileURL.path)
        }
        return paths
    }

    /// A `fileChange` item's patch, one entry per file.
    static func changes(in item: [String: JSONValue]) -> [AgentApprovalRequest.FileChange] {
        (item["changes"]?.arrayValue ?? []).compactMap { value in
            guard let change = value.objectValue, let path = change["path"]?.stringValue else {
                return nil
            }
            let kind = change["kind"]?.objectValue
            let parsed: AgentApprovalRequest.FileChange.Kind
            switch kind?["type"]?.stringValue {
            case "add": parsed = .add
            case "delete": parsed = .delete
            default:
                parsed = kind?["move_path"]?.stringValue.map { .move(to: $0) } ?? .update
            }
            return AgentApprovalRequest.FileChange(
                path: path, kind: parsed, diff: change["diff"]?.stringValue ?? "")
        }
    }
}
