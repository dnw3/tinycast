import Foundation

/// The latest delay test of a node against one URL.
enum ProxyDelay: Equatable, Sendable {
    case untested
    case failed
    case milliseconds(Int)

    /// At or past this a node reads as slow, the threshold every list colours by.
    static let slowMilliseconds = 150

    var isSlow: Bool {
        if case .milliseconds(let value) = self { return value >= Self.slowMilliseconds }
        return false
    }

    init(_ history: ProxyAPI.TestHistory) {
        guard let last = history.history.last else {
            self = .untested
            return
        }
        self = history.alive ? .milliseconds(last.delay) : .failed
    }
}

/// What the running core reports, joined to the profile, so a view never reads the API itself.
struct ProxySnapshot: Equatable, Sendable {
    struct Node: Equatable, Identifiable, Sendable {
        var name: String
        /// The protocol as the core names it, such as `Shadowsocks`.
        var kind: String
        var source: UUID?
        var region: ProxyRegion?
        var supportsUDP: Bool
        var latest: ProxyDelay
        var tests: [String: ProxyDelay]

        var id: String { name }

        /// Against a strategy's own test URL when it has tested the node, else the latest test.
        func delay(for url: String?) -> ProxyDelay {
            url.flatMap { tests[$0] } ?? latest
        }
    }

    struct Group: Equatable, Sendable {
        var current: String?
        var options: [String]
    }

    struct Source: Equatable, Sendable {
        var nodes: [String]
        var usage: ProxyAPI.Usage?
        var updatedAt: Date?
    }

    /// A rule set the core holds; one with no rules has not downloaded yet, or failed to.
    struct RuleSet: Equatable, Sendable {
        var rules: Int
        var updatedAt: Date?
    }

    var strategies: [UUID: Group]
    /// The option each enabled route group has now, by route id, the final route included.
    var routes: [String: String]
    var nodes: [String: Node]
    var sources: [UUID: Source]
    /// Names more than one source uses; the core can select only the first of them.
    var duplicates: Set<String>
    /// By rule-provider name.
    var ruleSets: [String: RuleSet]

    init(
        proxies: [String: ProxyAPI.Proxy], providers: [String: ProxyAPI.Provider],
        ruleProviders: [String: ProxyAPI.RuleProvider] = [:], profile: ProxyProfile
    ) {
        var nodes: [String: Node] = [:]
        var sources: [UUID: Source] = [:]
        var duplicates: Set<String> = []
        for source in profile.sources {
            guard let provider = providers[source.providerName] else { continue }
            for proxy in provider.proxies {
                guard nodes[proxy.name] == nil else {
                    duplicates.insert(proxy.name)
                    continue
                }
                nodes[proxy.name] = Node(
                    name: proxy.name, kind: proxy.type, source: source.id,
                    region: ProxyRegion.classify(proxy.name),
                    supportsUDP: proxy.udp, latest: ProxyDelay(proxy.latest),
                    tests: proxy.tests.mapValues(ProxyDelay.init))
            }
            sources[source.id] = Source(
                nodes: provider.proxies.map(\.name), usage: provider.usage, updatedAt: provider.updatedAt)
        }
        self.nodes = nodes
        self.sources = sources
        self.duplicates = duplicates

        var strategies: [UUID: Group] = [:]
        for strategy in profile.strategies {
            guard let group = proxies[strategy.name] else { continue }
            strategies[strategy.id] = Group(current: group.now, options: group.all)
        }
        self.strategies = strategies

        var routes: [String: String] = [:]
        let routeGroups =
            profile.routes.filter(\.isEnabled).map { ($0.id, $0.groupName) }
            + [(ProxyRoute.finalID, ProxyRoute.finalGroupName)]
        for (id, group) in routeGroups {
            if let current = proxies[group]?.now { routes[id] = current }
        }
        self.routes = routes
        ruleSets = ruleProviders.mapValues { RuleSet(rules: $0.ruleCount, updatedAt: $0.updatedAt) }
    }
}

extension ProxySnapshot {
    /// Where a strategy's traffic ends up now: the strategies it picks in turn, then its node.
    struct Reach: Equatable, Sendable {
        var via: [UUID]
        var node: Node?
        /// Direct or Reject, when a pick in the chain is one of them.
        var outcome: ProxyTarget?
    }

    func reach(from strategy: UUID, in profile: ProxyProfile) -> Reach {
        var reach = Reach(via: [], node: nil, outcome: nil)
        var next: UUID? = strategy
        var seen: Set<UUID> = []
        while let id = next, seen.insert(id).inserted {
            guard let option = strategies[id]?.current else { return reach }
            if let node = nodes[option] {
                reach.node = node
                return reach
            }
            switch option {
            case "DIRECT": reach.outcome = .direct
            case "REJECT", "REJECT-DROP": reach.outcome = .reject
            default: break
            }
            if reach.outcome != nil { return reach }
            next = profile.strategies.first { $0.name == option }?.id
            if let next { reach.via.append(next) }
        }
        return reach
    }

    /// The node a strategy's traffic lands on now, through whichever strategies it picks in turn.
    func node(reachedBy strategy: UUID, in profile: ProxyProfile) -> Node? {
        reach(from: strategy, in: profile).node
    }
}
