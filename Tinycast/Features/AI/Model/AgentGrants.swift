import Foundation

/// What the reader allowed for the rest of one chat; it is never written back to a CLI.
struct AgentGrants: Equatable, Sendable {
    /// Exact command lines: allowing `npm test` says nothing about `npm publish`.
    private(set) var commands: Set<String> = []
    private(set) var editsInFolder = false
    private(set) var reads: Set<String> = []
    private(set) var tools: Set<String> = []

    /// Whether "Allow This Chat" means anything for `request`, so the card offers it only then.
    static func admits(_ request: AgentApprovalRequest, in workspace: AgentWorkspace) -> Bool {
        guard case .fileChanges(let changes) = request.action else { return true }
        return !request.deletes && changes.allSatisfy(workspace.contains)
    }

    mutating func record(_ request: AgentApprovalRequest, in workspace: AgentWorkspace) {
        guard Self.admits(request, in: workspace) else { return }
        switch request.action {
        case .command(let line), .inspection(let line, _):
            commands.insert(line)
        case .fileChanges:
            editsInFolder = true
        case .read(let path):
            reads.insert(path)
        case .tool(let name, _):
            tools.insert(name)
        }
    }

    func covers(_ request: AgentApprovalRequest, in workspace: AgentWorkspace) -> Bool {
        guard Self.admits(request, in: workspace) else { return false }
        return switch request.action {
        case .command(let line), .inspection(let line, _): commands.contains(line)
        case .fileChanges: editsInFolder
        case .read(let path): reads.contains(path)
        case .tool(let name, _): tools.contains(name)
        }
    }
}
