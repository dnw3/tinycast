import Foundation

extension ProxyStrategy.Kind {
    var title: String {
        switch self {
        case .select: String(localized: "Manual")
        case .urlTest: String(localized: "Auto Select")
        case .fallback: String(localized: "Fallback")
        case .loadBalance: String(localized: "Load Balance")
        }
    }

    var explanation: String {
        switch self {
        case .select: String(localized: "You pick the node; it stays until you pick another.")
        case .urlTest: String(localized: "Tests delays regularly and uses the fastest node.")
        case .fallback: String(localized: "Uses the first option that answers, in order.")
        case .loadBalance: String(localized: "Spreads connections across the options, one site to one node.")
        }
    }
}

extension ProxyTarget {
    /// A strategy's own name, or what Direct and Reject are called.
    func title(in profile: ProxyProfile) -> String {
        switch self {
        case .direct: String(localized: "Direct")
        case .reject: String(localized: "Reject")
        case .strategy(let id): profile.strategy(id)?.name ?? String(localized: "Missing Strategy")
        }
    }

    static var directSubtitle: String { String(localized: "Bypasses the proxy") }
    static var rejectSubtitle: String { String(localized: "Drops the connection") }
}

extension ProxyUserRule.Kind {
    var title: String {
        switch self {
        case .domain: String(localized: "Domain")
        case .domainSuffix: String(localized: "Domain Suffix")
        case .domainKeyword: String(localized: "Domain Keyword")
        case .ipCIDR: String(localized: "IP Range")
        case .processName: String(localized: "Process Name")
        }
    }

    /// A whole sentence per kind, since a title cannot be lowercased into one in every language.
    var invalidValueMessage: String {
        switch self {
        case .domain: String(localized: "Not a valid domain")
        case .domainSuffix: String(localized: "Not a valid domain suffix")
        case .domainKeyword: String(localized: "Not a valid domain keyword")
        case .ipCIDR: String(localized: "Not a valid IP range")
        case .processName: String(localized: "Not a valid process name")
        }
    }

    var prompt: String {
        switch self {
        case .domain: "api.example.com"
        case .domainSuffix: "example.com"
        case .domainKeyword: "example"
        case .ipCIDR: "10.0.0.0/8"
        case .processName: "Telegram"
        }
    }
}

extension ProxyDelay {
    /// `42 ms`, `Timed Out`, or nothing for a node never tested.
    var label: String? {
        switch self {
        case .untested: nil
        case .failed: String(localized: "Timed Out")
        case .milliseconds(let value): String(localized: "\(value) ms")
        }
    }
}

/// How a strategy's options and users read in one line, shared by the window and the editor.
enum ProxyStrategySummary {
    static func pool(of strategy: ProxyStrategy, in profile: ProxyProfile) -> String {
        guard let pool = strategy.pool else {
            return String(localized: "\(strategy.members.count) options")
        }
        var parts: [String] = []
        if let sources = pool.sources {
            let names = profile.sources.filter { sources.contains($0.id) }.map(\.name)
            parts.append(names.isEmpty ? String(localized: "No sources") : names.formatted(.list(type: .and)))
        }
        if !pool.regions.isEmpty { parts.append(pool.regions.map(\.title).formatted(.list(type: .or))) }
        if !pool.pattern.isEmpty { parts.append(String(localized: "Custom pattern")) }
        return parts.isEmpty ? String(localized: "All nodes") : parts.joined(separator: " · ")
    }

    /// Routes, the remaining traffic, rules and other strategies that send traffic its way.
    static func users(of id: UUID, in profile: ProxyProfile) -> [String] {
        let target = ProxyTarget.strategy(id)
        var users = profile.routes.filter { $0.isEnabled && $0.target == target }.map(\.title)
        if profile.finalTarget == target { users.append(ProxyRoute.finalTitle) }
        let rules = profile.rules.filter { $0.isEnabled && $0.target == target }.count
        if rules > 0 { users.append(String(localized: "\(rules) rules")) }
        users += profile.strategies.filter { $0.members.contains(target) }.map(\.name)
        return users
    }
}
