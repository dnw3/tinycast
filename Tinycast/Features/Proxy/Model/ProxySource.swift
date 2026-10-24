import Foundation

/// Where nodes come from. A source contributes nodes only, never its own groups or rules.
struct ProxySource: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// The URL is a secret, kept in the keychain under the source's id.
        case subscription
        /// A path the user chose, with `~` for the home directory.
        case file(path: String)
    }

    var id: UUID
    var name: String
    var kind: Kind
    var isEnabled: Bool
    /// Include, exclude and renames match the names the source itself uses, before the prefix.
    var include: String
    var exclude: String
    var renames: [ProxyRename]
    var prefix: String

    static let defaultExclude = "(?i)过期|剩余|到期|官网|流量|重置|expire|traffic"

    /// The core's provider name: stable across renames and free of characters the config reserves.
    var providerName: String { "src-" + id.uuidString.prefix(8).lowercased() }

    /// Where the core keeps the source's nodes, relative to its own directory.
    var providerPath: String { "providers/\(providerName).yaml" }

    static func subscription(id: UUID, name: String) -> ProxySource {
        ProxySource(
            id: id, name: name, kind: .subscription, isEnabled: true, include: "", exclude: defaultExclude,
            renames: [], prefix: "")
    }

    static func file(id: UUID, name: String, path: String) -> ProxySource {
        ProxySource(
            id: id, name: name, kind: .file(path: path), isEnabled: true, include: "", exclude: "",
            renames: [], prefix: "")
    }
}

struct ProxyRename: Codable, Equatable, Sendable {
    var pattern: String
    var replacement: String
}
