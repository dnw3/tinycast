import Foundation

/// One agent turn's folder and mode, its CLI session, and the reader it asks.
struct AgentSession: Sendable {
    let workspace: AgentWorkspace
    /// The CLI's own session or thread to continue; `nil` starts one, which `started` reports.
    let resume: String?
    /// Counted in the CLI's own unit, like `AIToolServerSession.rounds`; `nil` is no cap.
    let rounds: Int?
    /// Tinycast's interface language in English, which the agent writes its descriptions in.
    let language: String
    let approve: @MainActor @Sendable (AgentApprovalRequest) async -> AgentApprovalDecision
    let started: @MainActor @Sendable (String) -> Void
    /// The CLI no longer has `resume`, so the next turn must start its own.
    let lost: @MainActor @Sendable () -> Void
}
