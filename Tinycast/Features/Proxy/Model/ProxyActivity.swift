import Foundation

/// One open connection as the activity list shows it: what it matched, and where it went out.
struct ProxyActivity: Equatable, Identifiable, Sendable {
    enum Match: Equatable, Sendable {
        case rule(UUID)
        /// A route by id; `ProxyRoute.finalID` is the remaining traffic.
        case route(String)
        /// Global or direct mode, which skips every rule and route.
        case mode
        /// The core's own traffic, such as a rule-set download or a delay test, which no rule sees.
        case core
        /// A rule the profile no longer holds, such as one from before the last reload.
        case unknown
    }

    var id: String
    /// The name the app asked for, or the address when it asked for none.
    var host: String
    var process: String
    var match: Match
    /// Nil when the strategy at the end of the chain is not in the profile.
    var target: ProxyTarget?
    /// The node the traffic left through; nil for Direct and Reject.
    var node: String?
    var upload: Int64
    var download: Int64
    var start: Date?

    init(_ connection: ProxyAPI.Connection, profile: ProxyProfile) {
        id = connection.id
        host = connection.host.isEmpty ? connection.destinationIP : connection.host
        process = connection.process
        upload = connection.upload
        download = connection.download
        start = connection.start
        match =
            connection.inbound == "Inner"
            ? .core : Self.matching(rule: connection.rule, payload: connection.rulePayload, in: profile)
        let wrappers = connection.chains.reversed().drop { $0 == "GLOBAL" || $0.hasPrefix("route/") }
        let outermost = wrappers.first
        switch outermost {
        case "DIRECT": target = .direct
        case "REJECT", "REJECT-DROP": target = .reject
        default: target = profile.strategies.first { $0.name == outermost }.map { .strategy($0.id) }
        }
        let first = connection.chains.first
        node = target?.strategyID != nil && first != outermost ? first : nil
    }

    /// The core's rule types for the kinds a user rule can have.
    static func ruleType(of kind: ProxyUserRule.Kind) -> String {
        switch kind {
        case .domain: "Domain"
        case .domainSuffix: "DomainSuffix"
        case .domainKeyword: "DomainKeyword"
        case .ipCIDR: "IPCIDR"
        case .processName: "ProcessName"
        }
    }

    /// The rule or route the core names by its rule type and payload, as it reports them.
    static func matching(rule: String, payload: String, in profile: ProxyProfile) -> Match {
        switch rule {
        case "": return .mode
        case "Match": return .route(ProxyRoute.finalID)
        case "RuleSet":
            let route = profile.routes.first { route in
                route.isEnabled && route.ruleSets.contains { $0.name == payload }
            }
            return route.map { .route($0.id) } ?? .unknown
        default:
            let found = profile.rules.first { candidate in
                candidate.isEnabled && ruleType(of: candidate.kind) == rule && candidate.value == payload
            }
            return found.map { .rule($0.id) } ?? .unknown
        }
    }
}
