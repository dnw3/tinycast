import Foundation

/// Before anyone is asked: a request goes through, is refused, or waits for the reader.
enum AgentApprovalPolicy {
    enum Verdict: Equatable, Sendable {
        case allow
        case ask
        case deny
    }

    static func verdict(
        for request: AgentApprovalRequest, in workspace: AgentWorkspace, grants: AgentGrants
    ) -> Verdict {
        if case .readOnly = workspace.mode, request.changesSomething { return .deny }
        if let paths = request.inspectedPaths, paths.allSatisfy(workspace.contains) { return .allow }
        if grants.covers(request, in: workspace) { return .allow }
        if case .autoEdit = workspace.mode, case .fileChanges(let changes) = request.action,
            !request.deletes, changes.allSatisfy(workspace.contains)
        {
            return .allow
        }
        return .ask
    }
}
