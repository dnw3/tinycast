import Foundation

/// Claude Code's built-in tools, as an agent turn offers them and as their requests read.
enum ClaudeAgentTool {
    /// `Task` and the web tools stay out: a subagent or fetch is a channel nobody approved.
    static func tools(for mode: AgentMode) -> [String] {
        switch mode {
        case .readOnly: ["Read", "Glob", "Grep"]
        case .ask, .autoEdit: ["Read", "Glob", "Grep", "Edit", "Write", "Bash", "TodoWrite"]
        }
    }

    static func approval(
        id: String, name: String, input: JSONValue, fileExists: (String) -> Bool
    ) -> AgentApprovalRequest {
        let fields = input.objectValue ?? [:]
        let text = { (key: String) in fields[key]?.stringValue ?? "" }
        switch name {
        case "Bash":
            return AgentApprovalRequest(
                id: id, action: .command(text("command")), reason: fields["description"]?.stringValue)
        case "Edit":
            let change = AgentApprovalRequest.FileChange(
                path: text("file_path"), kind: .update,
                diff: diff(removing: text("old_string"), adding: text("new_string")))
            return AgentApprovalRequest(id: id, action: .fileChanges([change]))
        case "Write":
            let path = text("file_path")
            let change = AgentApprovalRequest.FileChange(
                path: path, kind: fileExists(path) ? .update : .add,
                diff: diff(removing: "", adding: text("content")))
            return AgentApprovalRequest(id: id, action: .fileChanges([change]))
        case "Read", "Glob", "Grep":
            let path = fields["file_path"]?.stringValue ?? fields["path"]?.stringValue ?? text("pattern")
            return AgentApprovalRequest(id: id, action: .read(path))
        default:
            return AgentApprovalRequest(id: id, action: .tool(name: name, summary: summary(of: input)))
        }
    }

    /// What a transcript row calls the step; `TodoWrite` is the agent's own notes and gets none.
    static func row(name: String, input: JSONValue) -> (kind: ChatToolUse.Kind, title: String)? {
        let field = fields(of: input)
        let file = { (key: String) in field(key).map { ($0 as NSString).lastPathComponent } }
        let row: (kind: ChatToolUse.Kind, title: String?)
        switch name {
        case "Read": row = (.read, file("file_path"))
        case "Glob", "Grep": row = (.search, field("pattern"))
        case "Edit", "Write": row = (.edit, file("file_path"))
        case "NotebookEdit": row = (.edit, file("notebook_path"))
        case "Bash": row = (.command, field("command").map(oneLine))
        case "TodoWrite": return nil
        default: row = (.other, nil)
        }
        // A tool this does not know, or a field a newer CLI renamed, is named by the tool itself.
        return (row.kind, row.title ?? name)
    }

    /// The whole of what a step was given; any shape this does not know keeps its raw input.
    static func detail(name: String, input: JSONValue) -> ChatToolDetail {
        let field = fields(of: input)
        let edit = { (path: String?, old: String?, new: String?) -> ChatToolDetail? in
            guard let path, let new else { return nil }
            let change = AgentApprovalRequest.FileChange(
                path: path, kind: .update, diff: diff(removing: old ?? "", adding: new))
            return ChatToolDetail(input: [change].unifiedDiff)
        }
        let shaped: ChatToolDetail? =
            switch name {
            case "Bash": field("command").map { ChatToolDetail(input: $0, explanation: field("description")) }
            case "Read": field("file_path").map { ChatToolDetail(input: $0) }
            case "Glob", "Grep":
                field("pattern").map {
                    ChatToolDetail(input: [$0, field("path")].compactMap(\.self).joined(separator: "\n"))
                }
            case "Edit": edit(field("file_path"), field("old_string"), field("new_string"))
            case "Write": edit(field("file_path"), nil, field("content"))
            case "NotebookEdit": edit(field("notebook_path"), nil, field("new_source"))
            default: nil
            }
        return shaped ?? ChatToolDetail(input: input.jsonText)
    }

    /// A string field that is there and not empty; anything else reads as missing.
    private static func fields(of input: JSONValue) -> (String) -> String? {
        let fields = input.objectValue ?? [:]
        return { key in fields[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
    }

    /// Bash reports a failure as "Exit code N" above the output; the number is the exit code.
    static func result(_ text: String, isError: Bool) -> (output: String, exitCode: Int?) {
        let prefix = "Exit code "
        let line = text.prefix { !$0.isNewline }
        guard isError, line.hasPrefix(prefix), let code = Int(line.dropFirst(prefix.count)) else {
            return (text, nil)
        }
        return (String(text.dropFirst(line.count).dropFirst()), code)
    }

    static let titleLimit = 80

    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let more = line.count > titleLimit || line.count < text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return more ? String(line.prefix(titleLimit)) + "…" : line
    }

    /// Enough of a diff to judge an edit by: the old text out and the new text in.
    static func diff(removing old: String, adding new: String) -> String {
        let lines = { (text: String, mark: String) -> [String] in
            text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map { mark + $0 }
        }
        return (lines(old, "-") + lines(new, "+")).joined(separator: "\n")
    }

    static let summaryLimit = 400

    private static func summary(of input: JSONValue) -> String {
        let text = input.jsonText
        return text.count > summaryLimit ? String(text.prefix(summaryLimit)) + "…" : text
    }
}
