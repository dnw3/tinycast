import Foundation

/// What a config needs from outside the profile.
struct ProxyBuildEnvironment: Sendable {
    enum Mode: Sendable {
        /// The helper's root core takes over all traffic through a TUN device.
        case tun
        /// Tinycast's own core listens on the mixed port only.
        case portOnly
    }

    var mode: Mode
    /// By source id. A subscription missing here is left out and reported, never guessed.
    var subscriptionURLs: [UUID: String]
    var ruleCatalogBase = ProxyRuleSet.catalogBase
    var proxyMode = ProxyMode.rule
}

/// A built config, and what the caller does around applying it.
struct ProxyConfig: Equatable, Sendable {
    struct Selection: Equatable, Sendable {
        var group: String
        var option: String
    }

    /// Copied in by the caller first, as the core reads providers only from its own directory.
    struct File: Equatable, Sendable {
        var source: UUID
        var path: String
    }

    var document: ProxyJSON
    /// Route options in one fixed order and no mode, so equal keys mean picks alone need applying.
    var reloadKey: ProxyJSON
    /// Set again after every load, since the core restores older picks from its own cache.
    var selections: [Selection]
    var files: [File]
    var skippedSources: [UUID]
}

struct ProxyInvalidProfile: Error, Equatable {
    var problems: [ProxyProblem]
}

/// Builds the mihomo config; it never emits a controller, a secret, an external UI or a script.
enum ProxyConfigBuilder {
    static let fakeIPRange = "198.18.0.1/16"
    static let ruleUpdateInterval = 86_400
    /// Named outright: the core merges a source's test filters, where an empty one adds nothing.
    static let everyNode = ".*"

    static let fakeIPFilter: [String] = [
        "*.lan", "*.local", "*.localdomain", "+.home.arpa", "localhost.ptlogin2.qq.com",
        "localhost.sec.qq.com",
        "time.*.com", "time.*.gov", "time.*.edu.cn", "time.*.apple.com", "time-ios.apple.com",
        "time-macos.apple.com", "ntp.*.com", "+.ntp.org", "+.ntp.org.cn", "+.msftconnecttest.com",
        "+.msftncsi.com", "+.push.apple.com", "+.stun.*.*", "+.stun.*.*.*", "+.stun.*.*.*.*",
        "+.srv.nintendo.net", "+.stun.playstation.net", "xbox.*.microsoft.com", "+.xboxlive.com"
    ]

    static func build(
        _ profile: ProxyProfile, environment: ProxyBuildEnvironment
    ) throws(ProxyInvalidProfile) -> ProxyConfig {
        let problems = profile.problems
        guard problems.isEmpty else { throw ProxyInvalidProfile(problems: problems) }

        let names = Dictionary(
            profile.strategies.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func name(of target: ProxyTarget) -> String {
            switch target {
            case .direct: "DIRECT"
            case .reject: "REJECT"
            case .strategy(let id): names[id] ?? "REJECT"
            }
        }
        let defaultName = name(of: .strategy(profile.defaultStrategy))

        var providers: [String: ProxyJSON] = [:]
        var included: [ProxySource] = []
        var files: [ProxyConfig.File] = []
        var skipped: [UUID] = []
        for source in profile.sources where source.isEnabled {
            let path = source.providerPath
            var provider: [String: ProxyJSON] = [
                "path": .string(path), "health-check": healthCheck(of: source, in: profile)
            ]
            switch source.kind {
            case .subscription:
                guard let url = environment.subscriptionURLs[source.id] else {
                    skipped.append(source.id)
                    continue
                }
                provider["type"] = "http"
                provider["url"] = .string(url)
                let interval = profile.general.subscriptionUpdateInterval
                if interval > 0 { provider["interval"] = .int(interval) }
                // With no proxy named, the core routes the download by the rules like any traffic.
                let throughProxy = profile.general.updatesSubscriptionsThroughProxy
                provider["proxy"] = .string(throughProxy ? defaultName : "DIRECT")
            case .file:
                provider["type"] = "file"
                files.append(ProxyConfig.File(source: source.id, path: path))
            }
            if !source.include.isEmpty { provider["filter"] = .string(source.include) }
            if !source.exclude.isEmpty { provider["exclude-filter"] = .string(source.exclude) }
            var override: [String: ProxyJSON] = [:]
            if !source.renames.isEmpty {
                override["proxy-name"] = .array(
                    source.renames.map { ["pattern": .string($0.pattern), "target": .string($0.replacement)] }
                )
            }
            if !source.prefix.isEmpty { override["additional-prefix"] = .string(source.prefix) }
            if !override.isEmpty { provider["override"] = .object(override) }
            providers[source.providerName] = .object(provider)
            included.append(source)
        }

        var groups: [ProxyJSON] = []
        var selections: [ProxyConfig.Selection] = []
        for strategy in profile.strategies {
            var group: [String: ProxyJSON] = [
                "name": .string(strategy.name), "type": .string(strategy.kind.rawValue),
                "empty-fallback": "REJECT"
            ]
            var proxies = strategy.members.map(name(of:))
            if let pool = strategy.pool {
                let use = included.filter { pool.sources?.contains($0.id) ?? true }.map(\.providerName)
                if !use.isEmpty {
                    group["use"] = .array(use.map(ProxyJSON.string))
                    group["filter"] = .string(pool.filter ?? everyNode)
                }
            }
            if proxies.isEmpty && group["use"] == nil { proxies = ["REJECT"] }
            if !proxies.isEmpty { group["proxies"] = .array(proxies.map(ProxyJSON.string)) }
            if strategy.kind != .select {
                group["url"] = .string(strategy.testURL)
                group["interval"] = .int(strategy.testInterval)
            }
            if strategy.kind == .urlTest { group["tolerance"] = .int(strategy.tolerance) }
            if strategy.kind == .loadBalance { group["strategy"] = "consistent-hashing" }
            if strategy.kind == .select, let selected = strategy.selected {
                selections.append(ProxyConfig.Selection(group: strategy.name, option: selected))
            }
            groups.append(.object(group))
        }

        let options = profile.strategies.map(\.name) + ["DIRECT", "REJECT"]
        let routes = profile.routes.filter(\.isEnabled)
        let routeGroups =
            routes.map { ($0.groupName, $0.target) } + [(ProxyRoute.finalGroupName, profile.finalTarget)]
        var canonicalGroups = groups
        for (group, target) in routeGroups {
            let chosen = name(of: target)
            func routeGroup(_ options: [String]) -> ProxyJSON {
                [
                    "name": .string(group), "type": "select", "hidden": true,
                    "proxies": .array(options.map(ProxyJSON.string))
                ]
            }
            groups.append(routeGroup([chosen] + options.filter { $0 != chosen }))
            canonicalGroups.append(routeGroup(options))
            selections.append(ProxyConfig.Selection(group: group, option: chosen))
        }

        var rules: [ProxyJSON] = profile.rules.filter(\.isEnabled).map { rule in
            let fields = [rule.kind.keyword, rule.value, name(of: rule.target)]
            return .string((fields + (rule.kind == .ipCIDR ? ["no-resolve"] : [])).joined(separator: ","))
        }
        var ruleProviders: [String: ProxyJSON] = [:]
        for route in routes {
            for ruleSet in route.ruleSets {
                ruleProviders[ruleSet.name] = [
                    "type": "http", "behavior": .string(ruleSet.behavior.rawValue),
                    "format": .string(ruleSet.format.rawValue),
                    "url": .string(ruleSet.url(catalogBase: environment.ruleCatalogBase)),
                    "path": .string("rules/\(ruleSet.name).\(ruleSet.format.fileExtension)"),
                    "interval": .int(ruleUpdateInterval), "proxy": .string(defaultName)
                ]
                let resolves = ruleSet.resolves || ruleSet.behavior == .domain
                rules.append(
                    .string("RULE-SET,\(ruleSet.name),\(route.groupName)" + (resolves ? "" : ",no-resolve")))
            }
        }
        rules.append(.string("MATCH," + ProxyRoute.finalGroupName))
        // GLOBAL is the core's own group of every strategy; global mode sends all traffic to it.
        selections.append(ProxyConfig.Selection(group: "GLOBAL", option: defaultName))

        var document: [String: ProxyJSON] = [
            "mode": .string(environment.proxyMode.rawValue), "log-level": "warning", "ipv6": false,
            "mixed-port": .int(profile.general.mixedPort), "allow-lan": .bool(profile.general.allowsLAN),
            "unified-delay": true, "tcp-concurrent": true, "find-process-mode": "strict",
            "profile": ["store-selected": true, "store-fake-ip": true],
            "sniffer": sniffer,
            "dns": dns(
                profile.general,
                foreignThrough: routes.contains { $0.kind == .category(.foreign) } ? defaultName : nil),
            "proxy-providers": .object(providers), "proxy-groups": .array(groups),
            "rule-providers": .object(ruleProviders), "rules": .array(rules)
        ]
        if environment.mode == .tun {
            document["tun"] = [
                "enable": true, "auto-route": true, "auto-detect-interface": true,
                "dns-hijack": ["any:53", "tcp://any:53"]
            ]
        }
        var reloadKey = document
        reloadKey["proxy-groups"] = .array(canonicalGroups)
        reloadKey["mode"] = nil
        return ProxyConfig(
            document: .object(document), reloadKey: .object(reloadKey), selections: selections, files: files,
            skippedSources: skipped)
    }

    /// Every node at the default URL, as often as the most eager automatic strategy on it asks.
    private static func healthCheck(of source: ProxySource, in profile: ProxyProfile) -> ProxyJSON {
        let intervals = profile.strategies.compactMap { strategy -> Int? in
            guard strategy.kind != .select, let pool = strategy.pool,
                pool.sources?.contains(source.id) ?? true
            else { return nil }
            return strategy.testInterval
        }
        return [
            "enable": true, "url": .string(ProxyStrategy.defaultTestURL), "lazy": true,
            "interval": .int(intervals.min() ?? ProxyStrategy.defaultTestInterval)
        ]
    }

    private static func dns(_ general: ProxyGeneral, foreignThrough strategy: String?) -> ProxyJSON {
        let domestic = general.domesticDNS.map(ProxyJSON.string)
        let plain = general.domesticDNS.filter(isAddressed)
        // A direct dial resolves at home whatever the policy says, so direct routes get local CDNs.
        var dns: [String: ProxyJSON] = [
            "enable": true, "ipv6": false, "enhanced-mode": .string(general.dnsMode.rawValue),
            "nameserver": .array(domestic), "proxy-server-nameserver": .array(domestic),
            "direct-nameserver": .array(domestic), "direct-nameserver-follow-policy": false,
            "default-nameserver": .array(
                (plain.isEmpty ? ProxyGeneral().domesticDNS : plain).map(ProxyJSON.string))
        ]
        if general.dnsMode == .fakeIP {
            dns["fake-ip-range"] = .string(fakeIPRange)
            dns["fake-ip-filter"] = .array(fakeIPFilter.map(ProxyJSON.string))
        }
        if let strategy, !general.foreignDNS.isEmpty {
            let unreserved = CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            let fragment =
                "#" + (strategy.addingPercentEncoding(withAllowedCharacters: unreserved) ?? strategy)
            let servers = general.foreignDNS.map { $0.contains("#") ? $0 : $0 + fragment }
            let foreign = "rule-set:" + ProxyRouteCategory.foreign.ruleSets.map(\.name).joined(separator: ",")
            dns["nameserver-policy"] = .object([foreign: .array(servers.map(ProxyJSON.string))])
        }
        return .object(dns)
    }

    /// Plain DNS given by address, the only kind the core can reach before it can resolve a name.
    private static func isAddressed(_ server: String) -> Bool {
        let address = ["udp://", "tcp://"].reduce(Substring(server)) {
            $0.hasPrefix($1) ? $0.dropFirst($1.count) : $0
        }
        return !address.contains("://") && ProxyCIDR.address(ProxyUserRule.host(from: String(address))) != nil
    }

    private static let sniffer: ProxyJSON = [
        "enable": true, "parse-pure-ip": true,
        "sniff": [
            "HTTP": ["ports": [80, "8080-8880"], "override-destination": true],
            "TLS": ["ports": [443, 8443]],
            "QUIC": ["ports": [443, 8443]]
        ],
        "skip-domain": ["Mijia Cloud", "+.push.apple.com"]
    ]
}
