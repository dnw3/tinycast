import Foundation

/// The reader's answer to one `AgentApprovalRequest`.
enum AgentApprovalDecision: Equatable, Sendable {
    case allow
    /// Allowed, and the same kind of request is allowed for the rest of the chat.
    case allowForChat
    case deny
    /// Refused, and what the reader typed instead goes to the agent as the reason.
    case redirect(String)

    var allows: Bool {
        switch self {
        case .allow, .allowForChat: true
        case .deny, .redirect: false
        }
    }
}
