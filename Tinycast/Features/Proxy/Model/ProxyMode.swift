import Foundation

/// What the core does with traffic: follow the rules and routes, or send all of it one way.
enum ProxyMode: String, CaseIterable, Codable, Sendable {
    case rule
    /// Everything through the default strategy, which the `GLOBAL` group is pinned to.
    case global
    /// Everything direct, while TUN and DNS stay in place, so switching back is instant.
    case direct
}
