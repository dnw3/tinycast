import Foundation

/// How freely a chat's agent may act inside its folder.
enum AgentMode: String, Codable, CaseIterable, Sendable {
    case readOnly
    case ask
    case autoEdit
}
