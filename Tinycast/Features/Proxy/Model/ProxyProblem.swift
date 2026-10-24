import Foundation

/// Something that keeps a profile from becoming a config, attached to the row that has to change.
struct ProxyProblem: Equatable, Sendable {
    enum Subject: Hashable, Sendable {
        case general
        case source(UUID)
        case strategy(UUID)
        case route(String)
        case finalRoute
        case rule(UUID)
    }

    enum Kind: Equatable, Sendable {
        case emptyName
        case duplicateName
        case reservedName
        case unsafeText
        case missingStrategy
        case memberCycle
        case noOptions
        case invalidPattern(String)
        case invalidValue
        case invalidURL
        case invalidDNS
        case invalidPort
    }

    var subject: Subject
    var kind: Kind
}

enum ProxyText {
    static let reservedNames: Set<String> = [
        "DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"
    ]

    /// Free of commas, which split rules, and of `#`, `&` and `=`, which split DNS fragments.
    static func isSafe(_ text: String) -> Bool {
        !text.unicodeScalars.contains {
            ",#&=".unicodeScalars.contains($0) || $0.properties.generalCategory == .control
        }
    }

    /// The core's own names in any letter case, and the prefix the route groups use.
    static func isReserved(_ name: String) -> Bool {
        reservedNames.contains(name.uppercased()) || name.hasPrefix("route/")
    }

    static func isSafeName(_ name: String) -> Bool {
        isSafe(name) && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// mihomo splits a filter on backticks, so one would turn a single pattern into several.
    static func isValidPattern(_ pattern: String) -> Bool {
        !pattern.contains("`") && (try? NSRegularExpression(pattern: pattern)) != nil
    }

    static func isWebURL(_ text: String) -> Bool {
        guard let url = URLComponents(string: text), let host = url.host, !host.isEmpty else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }
}

extension ProxyProfile {
    var problems: [ProxyProblem] {
        var problems: [ProxyProblem] = []
        func add(_ subject: ProxyProblem.Subject, _ kind: ProxyProblem.Kind) {
            problems.append(ProxyProblem(subject: subject, kind: kind))
        }
        func check(_ target: ProxyTarget, _ subject: ProxyProblem.Subject) {
            if let id = target.strategyID, strategy(id) == nil { add(subject, .missingStrategy) }
        }
        func check(pattern: String, _ subject: ProxyProblem.Subject) {
            if !pattern.isEmpty, !ProxyText.isValidPattern(pattern) { add(subject, .invalidPattern(pattern)) }
        }

        for source in sources {
            if source.name.trimmingCharacters(in: .whitespaces).isEmpty {
                add(.source(source.id), .emptyName)
            }
            for pattern in [source.include, source.exclude] + source.renames.map(\.pattern) {
                check(pattern: pattern, .source(source.id))
            }
        }

        if strategy(defaultStrategy) == nil { add(.general, .missingStrategy) }
        var seenNames: Set<String> = []
        let cyclic = strategiesInCycles
        for strategy in strategies {
            let subject = ProxyProblem.Subject.strategy(strategy.id)
            if strategy.name.isEmpty {
                add(subject, .emptyName)
            } else if !ProxyText.isSafeName(strategy.name) {
                add(subject, .unsafeText)
            } else if ProxyText.isReserved(strategy.name) {
                add(subject, .reservedName)
            } else if !seenNames.insert(strategy.name.lowercased()).inserted {
                add(subject, .duplicateName)
            }
            strategy.members.forEach { check($0, subject) }
            if cyclic.contains(strategy.id) { add(subject, .memberCycle) }
            if strategy.members.isEmpty && strategy.pool == nil { add(subject, .noOptions) }
            if let pool = strategy.pool {
                check(pattern: pool.pattern, subject)
                check(pattern: pool.exclude, subject)
            }
            if strategy.kind != .select {
                if !ProxyText.isWebURL(strategy.testURL) { add(subject, .invalidURL) }
                if strategy.testInterval <= 0 || strategy.tolerance < 0 { add(subject, .invalidValue) }
            }
        }

        var seenRoutes: Set<String> = []
        for route in routes {
            let subject = ProxyProblem.Subject.route(route.id)
            if !seenRoutes.insert(route.id).inserted { add(subject, .duplicateName) }
            check(route.target, subject)
            guard case .custom(let name, let ruleSets) = route.kind else { continue }
            if name.trimmingCharacters(in: .whitespaces).isEmpty { add(subject, .emptyName) }
            if ruleSets.isEmpty { add(subject, .noOptions) }
            for ruleSet in ruleSets {
                if !ProxyText.isSafeName(ruleSet.name) || ruleSet.name.isEmpty { add(subject, .unsafeText) }
                if case .url(let url) = ruleSet.location, !ProxyText.isWebURL(url) {
                    add(subject, .invalidURL)
                }
            }
        }
        check(finalTarget, .finalRoute)

        for rule in rules {
            check(rule.target, .rule(rule.id))
            if ProxyUserRule.normalize(rule.value, as: rule.kind) != rule.value {
                add(.rule(rule.id), .invalidValue)
            }
        }

        let servers = general.domesticDNS + general.foreignDNS
        let unusable = servers.contains { $0.isEmpty || $0.contains { $0.isWhitespace || $0 == "," } }
        if general.domesticDNS.isEmpty || unusable { add(.general, .invalidDNS) }
        if !(1...65535).contains(general.mixedPort) { add(.general, .invalidPort) }
        return problems
    }

    /// Strategies that reach themselves through their members, which the core refuses to load.
    private var strategiesInCycles: Set<UUID> {
        let edges = Dictionary(
            strategies.map { ($0.id, $0.members.compactMap(\.strategyID)) },
            uniquingKeysWith: { first, _ in first })
        return Set(
            edges.keys.filter { start in
                var stack = edges[start] ?? []
                var seen: Set<UUID> = []
                while let id = stack.popLast() {
                    if id == start { return true }
                    if seen.insert(id).inserted { stack += edges[id] ?? [] }
                }
                return false
            })
    }
}
