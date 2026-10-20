import Foundation

/// A chat's session inside a CLI, worth continuing only on the same route in the same folder.
struct AgentThread: Codable, Equatable, Sendable {
    let route: String
    let folder: String
    let id: String

    func continues(route: String, in workspace: AgentWorkspace) -> Bool {
        self.route == route && folder == workspace.folder.standardizedFileURL.path
    }
}
