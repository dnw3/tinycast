import Foundation

/// A Claude turn as an agent's: its tools, its session, and every question routed to Tinycast.
enum ClaudeAgentLaunch {
    /// `mcpConfiguration` is the path of Tinycast's servers for this turn, `nil` when it has none.
    static func arguments(
        model: String, effort: String?, workspace: AgentWorkspace, session: String, resuming: Bool,
        rounds: Int?, instructions: String, mcpConfiguration: String?, handles: [String],
        managedMCPPolicy: Bool
    ) -> [String] {
        var result = [
            "-p",
            "--model", model,
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--thinking-display", "summarized",
            "--verbose",
            "--include-partial-messages",
            "--disable-slash-commands",
            "--no-chrome",
            "--tools", ClaudeAgentTool.tools(for: workspace.mode).joined(separator: ","),
            "--permission-mode", workspace.mode == .autoEdit ? "acceptEdits" : "default",
            "--permission-prompt-tool", "stdio",
            // The folder's settings may carry hooks or allow rules; the reader's hold the sign-in.
            "--setting-sources", "user",
            "--settings", settings(for: workspace.mode, handles: handles),
            "--append-system-prompt", instructions
        ]
        result += resuming ? ["--resume", session] : ["--session-id", session]
        // An admin's MCP policy makes Claude reject both flags, and then the policy decides.
        if !managedMCPPolicy {
            result += ["--strict-mcp-config", "--mcp-config", mcpConfiguration ?? #"{"mcpServers":{}}"#]
        }
        if let rounds { result += ["--max-turns", "\(rounds)"] }
        if let effort { result += ["--effort", effort] }
        return result
    }

    /// Hooks off, and an ask rule for each tool that changes things, which outranks any allow rule.
    static func settings(for mode: AgentMode, handles: [String]) -> String {
        var ask = handles.map { ClaudeMCPLaunch.toolPrefix + $0 }
        switch mode {
        case .readOnly: break
        case .ask: ask += ["Bash", "Edit", "Write"]
        case .autoEdit: ask += ["Bash"]
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["disableAllHooks": true, "permissions": ["ask": ask]],
                options: [.sortedKeys]),
            let text = String(bytes: data, encoding: .utf8)
        else { return #"{"disableAllHooks":true}"# }
        return text
    }

    /// The first turn carries the chat so far; a resumed one only what was just asked.
    static func message(for messages: [AIMessage], resuming: Bool) -> String {
        guard let index = messages.lastIndex(where: { $0.role == .user }) else { return "" }
        let latest = messages[index].text
        guard !resuming else { return latest }
        let earlier = messages[..<index].compactMap { message -> String? in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch message.role {
            case .user: return "User:\n" + text
            case .assistant: return "Assistant:\n" + text
            case .system, .tool: return nil
            }
        }
        guard !earlier.isEmpty else { return latest }
        return "The conversation so far:\n\n" + earlier.joined(separator: "\n\n")
            + "\n\nNow:\n" + latest
    }
}
