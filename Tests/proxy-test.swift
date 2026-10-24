import Foundation

@main
@MainActor
struct ProxyTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    // MARK: - Fixtures

    static func uuid(_ n: Int) -> UUID {
        UUID(uuid: (0, 0, UInt8(n / 256), UInt8(n % 256), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    static func starter() -> ProxyProfile {
        var next = 100
        return ProxyProfile.starter(defaultName: "默认代理", fastestName: "自动最快") {
            next += 1
            return uuid(next)
        }
    }

    static func build(
        _ profile: ProxyProfile, mode: ProxyBuildEnvironment.Mode = .tun, proxyMode: ProxyMode = .rule
    ) -> ProxyConfig? {
        let urls = Dictionary(
            uniqueKeysWithValues: profile.sources.map { ($0.id, "https://sub.test/\($0.name)") })
        return try? ProxyConfigBuilder.build(
            profile, environment: ProxyBuildEnvironment(mode: mode, subscriptionURLs: urls, proxyMode: proxyMode))
    }

    static func group(_ config: ProxyConfig?, _ name: String) -> ProxyJSON? {
        config?.document["proxy-groups"]?.array?.first { $0["name"]?.string == name }
    }

    static func strings(_ value: ProxyJSON?) -> [String] {
        value?.array?.compactMap(\.string) ?? []
    }

    static func problems(_ profile: ProxyProfile) -> [ProxyProblem.Kind] {
        profile.problems.map(\.kind)
    }

    static func strategy(_ n: Int, _ name: String, _ kind: ProxyStrategy.Kind = .select) -> ProxyStrategy {
        ProxyStrategy(id: uuid(n), name: name, kind: kind)
    }

    static func rule(
        _ n: Int, _ kind: ProxyUserRule.Kind, _ value: String, _ target: ProxyTarget
    ) -> ProxyUserRule {
        ProxyUserRule(id: uuid(n), kind: kind, value: value, target: target, isEnabled: true)
    }

    /// Three sources, one disabled and one missing its URL, with strategies over all of them.
    static func mixed() -> ProxyProfile {
        var profile = starter()
        var b = ProxySource.subscription(id: uuid(2), name: "B")
        b.prefix = "B·"
        b.renames = [ProxyRename(pattern: "香港", replacement: "HK")]
        var disabled = ProxySource.subscription(id: uuid(4), name: "D")
        disabled.isEnabled = false
        profile.sources = [
            ProxySource.subscription(id: uuid(1), name: "A"), b,
            ProxySource.file(id: uuid(3), name: "C", path: "~/nodes.yaml"), disabled,
            ProxySource.subscription(id: uuid(5), name: "E")
        ]
        var hongKong = strategy(10, "香港优选", .urlTest)
        hongKong.pool?.regions = [.hongKong]
        var stable = strategy(11, "稳定优先", .fallback)
        stable.members = [.strategy(uuid(10)), .strategy(profile.strategies[1].id)]
        stable.pool = nil
        var onlyB = strategy(12, "B 专用")
        onlyB.pool = ProxyStrategy.Pool(sources: [uuid(2)], regions: [], pattern: "IPLC", exclude: "(?i)test")
        var empty = strategy(13, "空")
        empty.pool?.sources = [uuid(4)]
        var balance = strategy(14, "均衡", .loadBalance)
        balance.pool?.regions = [.japan, .singapore]
        profile.strategies += [hongKong, stable, onlyB, empty, balance]
        profile.strategies[0].selected = "自动最快"
        if let ai = profile.routes.firstIndex(where: { $0.id == "ai" }) {
            profile.routes[ai].target = .strategy(uuid(10))
        }
        let company = ProxyRuleSet(
            name: "custom-00000020-1", behavior: .classical, format: .text,
            location: .url("https://rules.test/company.list"), resolves: false)
        profile.routes.append(
            ProxyRoute(
                id: "custom-00000020", kind: .custom(name: "公司", ruleSets: [company]), target: .direct,
                isEnabled: true))
        var disabledRule = rule(33, .domain, "off.test", .reject)
        disabledRule.isEnabled = false
        profile.rules = [
            rule(30, .domainSuffix, "example.com", .direct), rule(31, .ipCIDR, "10.0.0.0/8", .reject),
            rule(32, .processName, "Telegram", .strategy(uuid(11))), disabledRule
        ]
        return profile
    }

    // MARK: - Regions

    static func testRegionClassification() {
        let cases: [(String, ProxyRegion?)] = [
            ("🇭🇰 香港 01", .hongKong), ("HK-01", .hongKong), ("Hong Kong 03", .hongKong),
            ("HongKong", .hongKong),
            ("美国 洛杉矶", .unitedStates), ("USA 02", .unitedStates), ("US-CA 01", .unitedStates),
            ("🇺🇸 美国 | 香港中转", .unitedStates), ("日本东京01", .japan), ("SG 01", .singapore),
            ("RUS-01", .russia), ("CAN 01", .canada), ("Canada", .canada), ("台湾 02", .taiwan),
            ("hk-01", nil), ("can-01", nil), ("Bonus", nil), ("Plus 01", nil), ("剩余流量 100GB", nil),
            ("Contact us", nil), ("Made IN USA", .unitedStates),
            ("印度尼西亚 01", .indonesia), ("印尼 雅加达", .indonesia), ("印度 孟买", .india), ("IND-02", .india),
            ("Indiana 01", nil), ("罗马尼亚 01", .romania), ("罗马 01", .italy), ("内蒙古 BGP", nil),
            ("蒙古 01", .mongolia), ("都柏林 01", .ireland), ("柏林 01", .germany), ("🇩🇪 Berlin", .germany),
            ("回国 上海 01", .mainlandChina), ("🇨🇳 台湾 01", .taiwan), ("🇨🇳 01", nil), ("CN2 GIA 美国", .unitedStates),
            ("沪港 IPLC", .hongKong), ("4TH Node", nil), ("马来西亚 01", .malaysia), ("Viet Nam 02", .vietnam),
            ("São Paulo", .brazil), ("Sao Paulo 2", .brazil), ("阿联酋 迪拜", .unitedArabEmirates),
            ("UAE 01", .unitedArabEmirates), ("New Mexico 01", nil), ("Mexico City", .mexico),
            ("🇰🇷 首尔", .korea), ("TPE 01", .taiwan), ("IEPL 新加坡", .singapore), ("IEPL-01", nil),
            ("Türkiye 01", .turkey), ("🇺🇦 Kyiv", .ukraine), ("澳门 01", .macau), ("澳洲 悉尼", .australia),
            ("新西兰 01", .newZealand), ("新西伯利亚", .russia), ("Zürich", .switzerland), ("瑞典 01", .sweden)
        ]
        for (name, region) in cases {
            expect(
                ProxyRegion.classify(name) == region, "\(name) classifies as \(String(describing: region))")
        }
        let compiled = ProxyRegion.allCases.allSatisfy {
            (try? NSRegularExpression(pattern: $0.filter)) != nil
        }
        expect(compiled, "every region filter compiles")
        expect(ProxyRegion.classify("🇹🇼 01") == .taiwan, "a flag alone still names Taiwan")
        expect(ProxyRegion.taiwan.flag == nil, "Taiwan shows no flag, which China-region Macs cannot draw")
        expect(ProxyRegion.taiwan.flagEmoji == "🇹🇼", "though it still spells one for a view to draw")
        expect(
            ProxyRegion.allCases.filter { $0.flag == nil } == [.taiwan], "every other region keeps its flag")
        expect(ProxyRegion.hongKong.flag == "🇭🇰" && ProxyRegion.unitedKingdom.flag == "🇬🇧", "flags spell the code")
        expect(ProxyRegion.unitedKingdom.regionCode == "GB", "the UK's saved code is not its ISO one")
        expect(ProxyRegion(rawValue: "uk") == .unitedKingdom, "a saved region still decodes")
        expect(ProxyRegion.allCases.count == 79, "the table names 79 regions")
        expect(
            !ProxyRegion.mainlandChina.filter.contains("🇨🇳") && !ProxyRegion.peru.filter.contains("(?<![A-Za-z])"),
            "no flag for the mainland, and no code group where a region has no code")
        let pattern = try? NSRegularExpression(pattern: ProxyRegion.peru.filter)
        expect(
            pattern?.firstMatch(in: "Lima 01", range: NSRange(location: 0, length: 7)) == nil,
            "a region without codes does not match every name")
    }

    // MARK: - Node files

    static func testNodeFileOutline() {
        let config = """
            mixed-port: 7890
            allow-lan: false
            dns:
              enable: true
              nameserver:
                - 223.5.5.5
            proxies:
              - {name: 'HK 01', type: ss, server: a.test, port: 1, cipher: aes-128-gcm, password: x}
              - name: JP 01
                type: trojan
                server: b.test
                port: 443
                password: y
            proxy-groups:
              - name: Auto
                type: url-test
                proxies:
                  - HK 01
                  - JP 01
              - {name: Pick, type: select, proxies: [Auto, DIRECT]}
            rule-providers:
              reject:
                type: http
                behavior: domain
                url: "https://rules.test/reject.txt"
            rules:
            - DOMAIN-SUFFIX,example.com,DIRECT
            - RULE-SET,reject,REJECT
            - MATCH,Pick
            """
        let outline = ProxyNodeFileOutline(text: config)
        expect(outline.nodes == 2, "block and flow entries are both nodes")
        expect(outline.proxyGroups == 2, "a group's own member list is not counted as groups")
        expect(outline.rules == 3, "rules listed at the key's own indentation count")
        expect(outline.ruleProviders == 1, "a rule provider's fields are not providers themselves")
        expect(outline.otherKeys == ["mixed-port", "allow-lan", "dns"], "other keys in file order")
        expect(outline.hasUnusedContent, "groups and rules go unused")

        let links = ProxyNodeFileOutline(
            text: "# mine\nss://YWVzLTEyOC1nY206eA@a.test:1#HK\r\ntrojan://y@b.test:443#JP\n\n")
        expect(links.nodes == 2 && !links.hasUnusedContent, "a file of share links holds only nodes")

        let template = ProxyNodeFileOutline(text: "# Nodes\nproxies:\n  # - name: Home\n  #   type: ss\n")
        expect(template.nodes == 0 && !template.hasUnusedContent, "commented-out entries are no nodes")

        let providers = ProxyNodeFileOutline(
            text: "proxy-providers:\n  airport:\n    type: http\n    url: https://sub.test\n")
        expect(providers.nodes == 0 && providers.proxyProviders == 1, "a provider's nodes are not the file's")
    }

    // MARK: - Coding

    static func testCodingRoundTrip() {
        let profile = mixed()
        let decoded = (try? JSONEncoder().encode(profile)).flatMap {
            try? JSONDecoder().decode(ProxyProfile.self, from: $0)
        }
        expect(decoded == profile, "a profile survives encoding")

        let targets: [ProxyTarget] = [.direct, .reject, .strategy(uuid(7))]
        let encoded = (try? JSONEncoder().encode(targets)).flatMap { String(bytes: $0, encoding: .utf8) }
        expect(
            encoded == #"["direct","reject","strategy:00000007-0000-0000-0000-000000000000"]"#,
            "targets encode as short strings")
        let sparse = try? JSONDecoder().decode(ProxyGeneral.self, from: Data(#"{"mixedPort":7000}"#.utf8))
        var expected = ProxyGeneral()
        expected.mixedPort = 7000
        expect(sparse == expected, "settings an older file lacks keep their defaults")
        let unknown = try? JSONDecoder().decode([ProxyTarget].self, from: Data(#"["proxy"]"#.utf8))
        expect(unknown == nil, "an unknown target does not decode")
    }

    // MARK: - Recommended routes

    static func testStarterAndRecommendedRoutes() {
        var profile = starter()
        let primary = profile.strategies[0]
        let fastest = profile.strategies[1]
        expect(profile.defaultStrategy == primary.id, "the default strategy is the first one")
        expect(primary.kind == .select && primary.members == [.strategy(fastest.id)], "默认代理 lists 自动最快 first")
        expect(primary.pool == .everything && fastest.pool == .everything, "both start with every node")
        expect(fastest.kind == .urlTest, "自动最快 tests delay")
        expect(profile.problems.isEmpty, "the starter profile is valid")
        expect(profile.followsRecommendedRoutes, "the starter follows the recommended routes")
        expect(
            profile.routes.map(\.id) == [
                "ads", "lan", "ai", "streaming", "telegram", "github", "apple", "foreign", "china"
            ],
            "recommended routes match in the documented order")
        expect(profile.finalTarget == .strategy(primary.id), "other traffic goes to the default strategy")

        let custom = ProxyRoute(
            id: "custom-1", kind: .custom(name: "x", ruleSets: [.geosite("netflix")]), target: .direct,
            isEnabled: true)
        profile.addRoute(custom)
        expect(profile.routes[3].id == "custom-1", "a new route goes ahead of a route already holding its set")
        profile.addRoute(.category(.netflix, to: .direct))
        expect(profile.routes[3].id == "netflix", "and so does a library category")
        let unshared = ProxyRoute(
            id: "custom-2", kind: .custom(name: "y", ruleSets: [.geosite("bilibili")]), target: .direct,
            isEnabled: true)
        profile.addRoute(unshared)
        expect(profile.routes[9].id == "custom-2", "a route sharing nothing goes ahead of the broad overseas one")
        profile.routes.removeAll { $0.id == "custom-2" }
        expect(!profile.followsRecommendedRoutes, "an added route is a change")

        profile.routes.swapAt(2, 4)
        profile.routes[5].target = .direct
        profile.routes[6].isEnabled = false
        profile.finalTarget = .direct
        profile.restoreRecommendedRoutes()
        expect(
            profile.routes.map(\.id) == [
                "custom-1", "netflix", "ads", "lan", "ai", "streaming", "telegram", "github", "apple", "foreign",
                "china"
            ],
            "restoring puts the recommended routes back in order, the user's own ahead")
        expect(
            profile.routes.filter(\.isEnabled).count == profile.routes.count
                && profile.finalTarget == .strategy(primary.id)
                && profile.routes.first { $0.id == "streaming" }?.target == .strategy(primary.id),
            "and back on, with their targets")
        var noBroad = starter()
        noBroad.routes.removeAll { $0.id == "foreign" || $0.id == "china" }
        noBroad.addRoute(unshared)
        expect(noBroad.routes.last?.id == "custom-2", "with no broad or shared route, a new one goes last")
    }

    // MARK: - Validation

    static func testNames() {
        for (name, kind) in [
            ("direct", ProxyProblem.Kind.reservedName), ("Compatible", .reservedName),
            ("route/x", .reservedName),
            ("A,B", .unsafeText), ("A#B", .unsafeText), ("a&b", .unsafeText), ("a=b", .unsafeText),
            (" 香港", .unsafeText), ("香港 ", .unsafeText), ("a\nb", .unsafeText), ("", .emptyName)
        ] {
            var profile = starter()
            profile.strategies[1].name = name
            expect(problems(profile) == [kind], "\(name.debugDescription) is \(kind)")
        }
        var profile = starter()
        profile.strategies.append(strategy(50, "默认代理"))
        expect(
            profile.problems == [ProxyProblem(subject: .strategy(uuid(50)), kind: .duplicateName)],
            "a later duplicate")
        profile.strategies[2].name = "默认代理".uppercased() + "X"
        expect(profile.problems.isEmpty, "distinct names pass")
        profile.strategies[2].name = "auto"
        profile.strategies[1].name = "AUTO"
        expect(problems(profile) == [.duplicateName], "names are unique regardless of case")
    }

    static func testReferencesAndCycles() {
        var profile = starter()
        let missing = ProxyTarget.strategy(uuid(99))
        profile.routes[2].target = missing
        profile.finalTarget = missing
        profile.rules = [rule(30, .domain, "a.test", missing)]
        profile.strategies[1].members = [missing]
        let subjects = profile.problems.filter { $0.kind == .missingStrategy }.map(\.subject)
        expect(
            subjects == [.strategy(profile.strategies[1].id), .route("ai"), .finalRoute, .rule(uuid(30))],
            "every dangling strategy reference is reported where it is")

        profile = starter()
        profile.defaultStrategy = uuid(99)
        expect(
            profile.problems == [ProxyProblem(subject: .general, kind: .missingStrategy)], "a missing default"
        )

        profile = starter()
        let primary = profile.strategies[0].id
        let fastest = profile.strategies[1].id
        profile.strategies[1].members = [.strategy(primary)]
        let cyclic = profile.problems.filter { $0.kind == .memberCycle }.map(\.subject)
        expect(cyclic == [.strategy(primary), .strategy(fastest)], "both strategies in a cycle are reported")
        profile.strategies[1].members = [.strategy(fastest)]
        expect(problems(profile) == [.memberCycle], "a strategy cannot be its own member")

        profile = starter()
        profile.strategies[1].pool = nil
        expect(problems(profile) == [.noOptions], "a strategy without members or pool has no options")
    }

    static func testPatternsAndSettings() {
        var profile = starter()
        var source = ProxySource.subscription(id: uuid(1), name: "A")
        source.include = "("
        source.renames = [ProxyRename(pattern: "a`b", replacement: "x")]
        profile.sources = [source]
        profile.strategies[1].pool?.pattern = "["
        expect(
            problems(profile) == [.invalidPattern("("), .invalidPattern("a`b"), .invalidPattern("[")],
            "patterns must compile and never contain a backtick")

        profile = starter()
        profile.sources = [ProxySource.subscription(id: uuid(1), name: " ")]
        expect(problems(profile) == [.emptyName], "a source needs a name")

        profile = starter()
        profile.strategies[1].testURL = "ftp://x"
        profile.strategies[1].testInterval = 0
        expect(
            problems(profile) == [.invalidURL, .invalidValue], "a tested strategy needs a URL and an interval"
        )
        profile.strategies[1].kind = .select
        expect(profile.problems.isEmpty, "a select strategy is never tested")

        profile = starter()
        profile.general.mixedPort = 0
        profile.general.domesticDNS = []
        expect(problems(profile) == [.invalidDNS, .invalidPort], "ports and DNS servers are checked")
        profile.general.mixedPort = 65_535
        profile.general.domesticDNS = ["223.5.5.5"]
        profile.general.foreignDNS = ["https://dns.test/q, x"]
        expect(problems(profile) == [.invalidDNS], "a DNS server cannot hold a comma or space")

        profile = starter()
        profile.routes.append(
            ProxyRoute(
                id: "custom-1", kind: .custom(name: "x", ruleSets: []), target: .direct, isEnabled: true))
        profile.routes.append(
            ProxyRoute(
                id: "custom-2",
                kind: .custom(
                    name: "y",
                    ruleSets: [
                        ProxyRuleSet(
                            name: "custom-2-1", behavior: .domain, format: .text, location: .url("ftp://x"),
                            resolves: false)
                    ]), target: .direct, isEnabled: true))
        profile.routes.append(.category(.lan, to: .direct))
        expect(
            problems(profile) == [.noOptions, .invalidURL, .duplicateName],
            "custom routes need rule sets with web URLs, and route ids are unique")

        profile = starter()
        profile.rules = [rule(30, .domain, "Example.com", .direct)]
        expect(problems(profile) == [.invalidValue], "a stored rule value is always normalized")
    }

    // MARK: - My rules

    static func testRuleNormalization() {
        let cases: [(ProxyUserRule.Kind, String, String?)] = [
            (.domain, "https://user@OpenAI.com:8443/chat?x#y", "openai.com"), (.domain, "例子.中国", "例子.中国"),
            (.domain, "a..b", nil), (.domain, "*.google.com", nil), (.domain, "a b.com", nil),
            (.domainSuffix, ".google.com", "google.com"), (.domainSuffix, "*.google.com", "google.com"),
            (.domainSuffix, "+.google.com", "google.com"), (.domainKeyword, " Google ", "google"),
            (.domainKeyword, "a b", nil), (.domainKeyword, "a,b", nil),
            (.ipCIDR, "1.2.3.4", "1.2.3.4/32"), (.ipCIDR, "10.1.2.3/8", "10.0.0.0/8"),
            (.ipCIDR, "2001:DB8::1", "2001:db8::1/128"), (.ipCIDR, "2001:db8::1/32", "2001:db8::/32"),
            (.ipCIDR, "10.0.0.0/33", nil), (.ipCIDR, "1.2.3.4/032", nil), (.ipCIDR, "1.2.3.4/-1", nil),
            (.ipCIDR, "1.2.3", nil), (.ipCIDR, "example.com", nil),
            (.processName, " Google Chrome ", "Google Chrome"), (.processName, "a=b", nil),
            (.processName, "", nil)
        ]
        for (kind, input, output) in cases {
            expect(ProxyUserRule.normalize(input, as: kind) == output, "\(kind) \(input.debugDescription)")
        }
        for (input, host) in [
            ("[2001:db8::1]:443", "2001:db8::1"), ("2001:db8::1", "2001:db8::1"),
            ("Example.com:80", "example.com"),
            ("http://a.test/x:y", "a.test")
        ] {
            expect(ProxyUserRule.host(from: input) == host, "host of \(input)")
        }
    }

    static func testRuleCandidates() {
        func pairs(_ input: String) -> [String] {
            ProxyUserRule.candidates(for: input).map { "\($0.kind.keyword),\($0.value)" }
        }
        expect(
            pairs("https://chat.openai.com/c/1?x=2")
                == [
                    "DOMAIN-SUFFIX,openai.com", "DOMAIN-SUFFIX,chat.openai.com", "DOMAIN,chat.openai.com",
                    "DOMAIN-KEYWORD,openai"
                ],
            "a page offers its site, its host and a keyword, broadest first")
        expect(
            pairs("example.com") == [
                "DOMAIN-SUFFIX,example.com", "DOMAIN,example.com", "DOMAIN-KEYWORD,example"
            ],
            "a bare domain is not offered twice")
        expect(
            pairs("news.bbc.co.uk").first == "DOMAIN-SUFFIX,bbc.co.uk",
            "a second-level ending keeps its registered name")
        expect(pairs("10.1.2.3") == ["IP-CIDR,10.1.2.3/32"], "an address is only an address range")
        expect(pairs("10.1.2.3/8") == ["IP-CIDR,10.0.0.0/8"], "a range is masked")
        expect(
            pairs("Telegram") == ["PROCESS-NAME,Telegram", "DOMAIN-KEYWORD,telegram"], "a bare word is an app"
        )
        expect(pairs("Google Chrome") == ["PROCESS-NAME,Google Chrome"], "a name with spaces is only an app")
        expect(pairs("  ").isEmpty && pairs("a,b").isEmpty, "nothing usable offers nothing")
        for (kind, value) in ProxyUserRule.candidates(for: "https://a.b.example.org") {
            expect(ProxyUserRule.normalize(value, as: kind) == value, "\(value) is already normalized")
        }
    }

    static func testLauncherHints() {
        for query in ["proxy", "Prox", "VPN", "代理", " 节点 ", "mihomo"] {
            expect(ProxyLauncherHint.asksForProxy(query), "“\(query)” asks for the proxy")
        }
        for query in ["", "pro", "vp", "代", "proxyman", "chrome"] {
            expect(!ProxyLauncherHint.asksForProxy(query), "“\(query)” does not")
        }
        let link = "https://sub.example.com/api/v1/client/subscribe?token=abc123"
        expect(ProxyLauncherHint.subscriptionLink(in: " \(link)\n") == link, "a subscription link is offered")
        expect(
            ProxyLauncherHint.subscriptionLink(in: "https://news.example.com/2026/10/story") == nil,
            "an ordinary page is not")
        expect(ProxyLauncherHint.subscriptionLink(in: "token sub https://a.test/sub") == nil, "nor prose")
        expect(ProxyLauncherHint.subscriptionLink(in: "ftp://a.test/sub") == nil, "nor another scheme")
        expect(ProxyLauncherHint.masked(link) == "sub.example.com/api/••••", "the secret part is hidden")
        expect(
            ProxyLauncherHint.masked("https://a.test/0123456789abcdef") == "a.test/••••",
            "a long first segment may be the secret itself")
    }

    static func testRuleMatching() {
        var disabled = rule(1, .domain, "www.google.com", .reject)
        disabled.isEnabled = false
        let rules = [
            disabled, rule(2, .domainSuffix, "google.com", .direct), rule(3, .domainKeyword, "ads", .reject),
            rule(4, .ipCIDR, "10.0.0.0/8", .direct), rule(5, .ipCIDR, "2001:db8::/32", .direct),
            rule(6, .domain, "openai.com", .direct), rule(7, .processName, "Telegram", .direct)
        ]
        let cases: [(String, Int?)] = [
            ("www.google.com", 2), ("google.com", 2), ("badgoogle.com", nil), ("ads.example.com", 3),
            ("google-ads.com", 3), ("10.1.2.3", 4), ("11.0.0.1", nil), ("2001:db8::5", 5),
            ("2001:db9::5", nil),
            ("https://OpenAI.com/x", 6), ("api.openai.com", nil), ("Telegram", nil)
        ]
        for (input, expected) in cases {
            let match = ProxyRuleMatch.firstMatch(in: rules, for: input)
            expect(match?.id == expected.map(uuid), "\(input) matches rule \(String(describing: expected))")
        }
    }

    // MARK: - Builder

    static func testProviders() {
        let config = build(mixed())
        let providers = config?.document["proxy-providers"]?.object ?? [:]
        let (a, b, c) = ("src-00000001", "src-00000002", "src-00000003")
        expect(Set(providers.keys) == [a, b, c, "src-00000005"], "every enabled source becomes a provider")
        expect(config?.skippedSources == [], "every subscription in the fixture has a URL")

        expect(providers[a]?["type"]?.string == "http", "a subscription is an http provider")
        expect(providers[a]?["url"]?.string == "https://sub.test/A", "with its URL")
        expect(providers[a]?["path"]?.string == "providers/\(a).yaml", "cached inside the core's directory")
        expect(providers[a]?["interval"]?.int == 43_200, "updated every twelve hours")
        expect(
            providers[a]?["exclude-filter"]?.string == ProxySource.defaultExclude, "info nodes are excluded")
        expect(providers[a]?["proxy"]?.string == "DIRECT", "fetched directly, whatever the rules say")
        expect(providers[a]?["override"] == nil, "and unrenamed")

        var manual = mixed()
        manual.general.updatesSubscriptionsThroughProxy = true
        manual.general.subscriptionUpdateInterval = 0
        let manualProviders = build(manual)?.document["proxy-providers"]?.object ?? [:]
        expect(manualProviders[b]?["proxy"]?.string == "默认代理", "updated through the default strategy")
        expect(manualProviders[b]?["interval"] == nil, "a manual subscription has no interval")
        expect(providers[b]?["override"]?["additional-prefix"]?.string == "B·", "the prefix is an override")
        let rename = providers[b]?["override"]?["proxy-name"]?.array?.first
        expect(
            rename?["pattern"]?.string == "香港" && rename?["target"]?.string == "HK", "renames are overrides")

        expect(providers[c]?["type"]?.string == "file" && providers[c]?["url"] == nil, "a file source")

        let check = providers[a]?["health-check"]
        expect(
            check?["enable"]?.bool == true && check?["lazy"]?.bool == true
                && check?["url"]?.string == ProxyStrategy.defaultTestURL,
            "every source tests all its nodes at the default URL, while traffic goes through them")
        expect(check?["interval"]?.int == ProxyStrategy.defaultTestInterval, "every five minutes by default")
        var eager = mixed()
        eager.strategies[2].testInterval = 60
        eager.strategies[1].pool?.sources = [uuid(1)]
        eager.strategies[2].pool?.sources = [uuid(1)]
        eager.strategies[6].pool?.sources = [uuid(1)]
        let eagerProviders = build(eager)?.document["proxy-providers"]?.object ?? [:]
        expect(
            eagerProviders[a]?["health-check"]?["interval"]?.int == 60,
            "the most eager automatic strategy on a source sets its pace")
        expect(
            eagerProviders[c]?["health-check"]?["interval"]?.int == ProxyStrategy.defaultTestInterval,
            "a source only picked from by hand keeps the default")
        expect(
            config?.files == [ProxyConfig.File(source: uuid(3), path: "providers/\(c).yaml")], "files to copy"
        )

        var profile = mixed()
        let withoutURL = try? ProxyConfigBuilder.build(
            profile,
            environment: ProxyBuildEnvironment(mode: .tun, subscriptionURLs: [uuid(1): "https://sub.test/A"]))
        expect(withoutURL?.skippedSources == [uuid(2), uuid(5)], "a subscription without a URL is reported")
        profile.sources[0].isEnabled = false
        expect(build(profile)?.document["proxy-providers"]?[a] == nil, "a disabled source is left out")
    }

    static func testStrategyGroups() {
        let config = build(mixed())
        let names = config?.document["proxy-groups"]?.array?.compactMap { $0["name"]?.string } ?? []
        expect(
            Array(names.prefix(7)) == ["默认代理", "自动最快", "香港优选", "稳定优先", "B 专用", "空", "均衡"],
            "strategies come first, in order")
        expect(names.last == "route/final", "the final route group comes last")

        let primary = group(config, "默认代理")
        expect(primary?["type"]?.string == "select", "默认代理 is a select group")
        expect(strings(primary?["proxies"]) == ["自动最快"], "its member comes first")
        expect(
            primary?["use"]?.array?.count == 4 && primary?["filter"]?.string == ProxyConfigBuilder.everyNode,
            "it takes every node, saying so, since the core merges the test filters of a source")
        expect(primary?["url"] == nil && primary?["interval"] == nil, "a select group is never tested")

        let fastest = group(config, "自动最快")
        expect(fastest?["type"]?.string == "url-test" && fastest?["proxies"] == nil, "自动最快 tests every node")
        expect(fastest?["url"]?.string == ProxyStrategy.defaultTestURL, "against the default URL")
        expect(fastest?["interval"]?.int == 300 && fastest?["tolerance"]?.int == 50, "every five minutes")

        let hongKong = group(config, "香港优选")
        expect(
            hongKong?["filter"]?.string == "^.*(?:(?:\(ProxyRegion.hongKong.filter)))",
            "a region pool filters")

        let stable = group(config, "稳定优先")
        expect(strings(stable?["proxies"]) == ["香港优选", "自动最快"] && stable?["use"] == nil, "members only")
        expect(stable?["type"]?.string == "fallback" && stable?["tolerance"] == nil, "a fallback group")

        let onlyB = group(config, "B 专用")
        expect(onlyB?["use"]?.array?.count == 1, "a pool can take one source")
        expect(onlyB?["filter"]?.string == "^(?!.*(?:(?i)test)).*(?:(?:IPLC))", "excluding by lookahead")
        expect(onlyB?["exclude-filter"] == nil, "never with exclude-filter, which also drops members")

        expect(
            strings(group(config, "空")?["proxies"]) == ["REJECT"],
            "an empty pool rejects; COMPATIBLE is direct")
        let strategyGroups = (config?.document["proxy-groups"]?.array ?? []).filter { $0["hidden"] == nil }
        expect(
            strategyGroups.count == 7
                && strategyGroups.allSatisfy { $0["empty-fallback"]?.string == "REJECT" },
            "a strategy whose sources are empty rejects rather than going direct")
        expect(group(config, "空")?["use"] == nil, "with no providers")

        let balance = group(config, "均衡")
        expect(
            balance?["strategy"]?.string == "consistent-hashing", "load balancing keeps a site on one node")
        let filter = balance?["filter"]?.string ?? ""
        expect(!filter.contains("`"), "several regions stay one filter")
        let expression = try? NSRegularExpression(pattern: filter)
        for (name, matches) in [("🇯🇵 东京 01", true), ("SG 02", true), ("香港 01", false), ("sg 02", false)] {
            let range = NSRange(name.startIndex..., in: name)
            expect(
                (expression?.firstMatch(in: name, range: range) != nil) == matches, "\(name) in a JP/SG pool")
        }
        for group in config?.document["proxy-groups"]?.array ?? [] {
            guard let filter = group["filter"]?.string else { continue }
            expect((try? NSRegularExpression(pattern: filter)) != nil, "\(filter) compiles")
        }
    }

    static func testPoolPreview() {
        let profile = mixed()
        let names = ["香港 01", "HK IPLC 02", "🇯🇵 东京 01", "SG IPLC test", "Thanks 03"]
        expect(
            profile.strategy(uuid(10))?.pool?.admitted(names) == ["香港 01", "HK IPLC 02"],
            "a region pool previews the nodes the core would keep")
        expect(
            profile.strategy(uuid(12))?.pool?.admitted(names) == ["HK IPLC 02"],
            "a pattern keeps its matches and the exclusion drops the rest")
        expect(ProxyStrategy.Pool.everything.admitted(names) == names, "an open pool keeps every node")
        var broken = ProxyStrategy.Pool.everything
        broken.pattern = "("
        expect(broken.admitted(names).isEmpty, "a pattern that cannot compile keeps nothing")
        expect(
            profile.sources[0].providerPath == "providers/src-00000001.yaml",
            "a source's cached nodes live where the provider says")
    }

    static func testRouteGroupsAndSelections() {
        let config = build(mixed())
        let ai = group(config, "route/ai")
        expect(
            ai?["hidden"]?.bool == true && ai?["type"]?.string == "select", "a route group is a hidden select"
        )
        expect(
            strings(ai?["proxies"])
                == ["香港优选", "默认代理", "自动最快", "稳定优先", "B 专用", "空", "均衡", "DIRECT", "REJECT"],
            "the chosen target first, then every other option")
        expect(strings(group(config, "route/ads")?["proxies"]).first == "REJECT", "ads are rejected")
        expect(strings(group(config, "route/lan")?["proxies"]).first == "DIRECT", "LAN goes direct")
        expect(
            strings(group(config, "route/custom-00000020")?["proxies"]).first == "DIRECT", "custom routes too"
        )
        expect(strings(group(config, "route/final")?["proxies"]).first == "默认代理", "the rest is proxied")

        let selections = config?.selections ?? []
        expect(selections.first == ProxyConfig.Selection(group: "默认代理", option: "自动最快"), "a hand pick")
        expect(selections.contains(ProxyConfig.Selection(group: "route/ai", option: "香港优选")), "each route")
        expect(
            selections.dropLast().last == ProxyConfig.Selection(group: "route/final", option: "默认代理"),
            "and the final")

        var profile = mixed()
        profile.routes[0].isEnabled = false
        expect(group(build(profile), "route/ads") == nil, "a disabled route has no group")
    }

    static func testRules() {
        let config = build(mixed())
        let rules = strings(config?.document["rules"])
        expect(
            Array(rules.prefix(3)) == [
                "DOMAIN-SUFFIX,example.com,DIRECT", "IP-CIDR,10.0.0.0/8,REJECT,no-resolve",
                "PROCESS-NAME,Telegram,稳定优先"
            ], "my rules come first, in order, without the disabled one")
        expect(rules.contains("RULE-SET,geosite-category-ads-all,route/ads"), "ads by domain")
        expect(rules.contains("RULE-SET,geoip-private,route/lan,no-resolve"), "address sets skip DNS")
        expect(rules.contains("RULE-SET,geoip-cn,route/china"), "except China's, which resolves")
        expect(
            rules.contains("RULE-SET,custom-00000020-1,route/custom-00000020,no-resolve"),
            "custom classical sets")
        expect(rules.last == "MATCH,route/final", "everything else goes to the final route")
        let china = rules.firstIndex(of: "RULE-SET,geosite-cn,route/china") ?? 0
        let foreign = rules.firstIndex(of: "RULE-SET,geosite-geolocation-!cn,route/foreign") ?? 0
        expect(foreign < china, "routes match in order")

        let providers = config?.document["rule-providers"]?.object ?? [:]
        let ruleSets = mixed().routes.flatMap(\.ruleSets).map(\.name)
        expect(Set(providers.keys) == Set(ruleSets), "one provider per rule set")
        let cn = providers["geoip-cn"]
        expect(cn?["url"]?.string == ProxyRuleSet.catalogBase + "/geoip/cn.mrs", "from the catalog")
        expect(cn?["path"]?.string == "rules/geoip-cn.mrs", "cached in the core's directory")
        expect(cn?["behavior"]?.string == "ipcidr" && cn?["format"]?.string == "mrs", "a binary address set")
        expect(cn?["proxy"]?.string == "默认代理" && cn?["interval"]?.int == 86_400, "daily, through the proxy")
        let company = providers["custom-00000020-1"]
        expect(company?["url"]?.string == "https://rules.test/company.list", "a custom set keeps its URL")
        expect(company?["path"]?.string == "rules/custom-00000020-1.list", "text sets end in .list")

        let mirrored = try? ProxyConfigBuilder.build(
            starter(),
            environment: ProxyBuildEnvironment(
                mode: .tun, subscriptionURLs: [:], ruleCatalogBase: "https://mirror.test"))
        let mirror = mirrored?.document["rule-providers"]?["geosite-cn"]?["url"]?.string
        expect(mirror == "https://mirror.test/geosite/cn.mrs", "the catalog base can be replaced")
    }

    static func testDNSAndTUN() {
        let tun = build(mixed())?.document
        let dns = tun?["dns"]
        expect(dns?["enable"]?.bool == true && dns?["enhanced-mode"]?.string == "fake-ip", "fake-IP DNS")
        expect(dns?["fake-ip-range"]?.string == ProxyConfigBuilder.fakeIPRange, "in the benchmark range")
        expect(strings(dns?["nameserver"]) == ["223.5.5.5", "119.29.29.29"], "domestic servers by default")
        expect(
            strings(dns?["proxy-server-nameserver"]) == strings(dns?["nameserver"]),
            "node names resolve at home")
        expect(
            strings(dns?["direct-nameserver"]) == strings(dns?["nameserver"])
                && dns?["direct-nameserver-follow-policy"]?.bool == false,
            "a direct dial resolves at home even for a domain the policy sends abroad")
        let policy = dns?["nameserver-policy"]?["rule-set:geosite-geolocation-!cn"]
        expect(
            strings(policy) == [
                "https://1.1.1.1/dns-query#%E9%BB%98%E8%AE%A4%E4%BB%A3%E7%90%86",
                "https://8.8.8.8/dns-query#%E9%BB%98%E8%AE%A4%E4%BB%A3%E7%90%86"
            ], "foreign domains resolve through the default strategy")
        expect(
            tun?["tun"]?["enable"]?.bool == true && tun?["tun"]?["auto-route"]?.bool == true, "TUN takes over"
        )
        expect(strings(tun?["tun"]?["dns-hijack"]) == ["any:53", "tcp://any:53"], "and hijacks DNS")
        expect(
            tun?["mixed-port"]?.int == 7897 && tun?["allow-lan"]?.bool == false, "the mixed port stays local")
        for key in [
            "external-controller", "external-controller-unix", "secret", "external-ui", "external-ui-url"
        ] {
            expect(tun?[key] == nil, "never \(key)")
        }

        expect(build(mixed(), mode: .portOnly)?.document["tun"] == nil, "port-only mode has no TUN")

        var profile = starter()
        profile.general.dnsMode = .realIP
        profile.general.domesticDNS = ["https://dns.alidns.com/dns-query", "119.29.29.29"]
        profile.general.foreignDNS = ["tls://8.8.8.8#DIRECT"]
        let real = build(profile)?.document["dns"]
        expect(real?["enhanced-mode"]?.string == "redir-host" && real?["fake-ip-range"] == nil, "real-IP DNS")
        expect(strings(real?["default-nameserver"]) == ["119.29.29.29"], "plain addresses bootstrap the rest")
        var ported = starter()
        ported.general.domesticDNS = ["udp://223.5.5.5:53", "tls://dns.alidns.com", "[2400:3200::1]:53"]
        expect(
            strings(build(ported)?.document["dns"]?["default-nameserver"]) == [
                "udp://223.5.5.5:53", "[2400:3200::1]:53"
            ],
            "an address with a port or a plain scheme bootstraps too")
        expect(
            strings(real?["nameserver-policy"]?["rule-set:geosite-geolocation-!cn"]) == [
                "tls://8.8.8.8#DIRECT"
            ],
            "a server that names its own route keeps it")
        profile.routes.removeAll { $0.id == "foreign" }
        expect(build(profile)?.document["dns"]?["nameserver-policy"] == nil, "no foreign route, no policy")
    }

    static func testDeterminismAndFailure() {
        let first = try? build(mixed())?.document.encoded()
        let second = try? build(mixed())?.document.encoded()
        expect(first != nil && first == second, "one profile always builds the same bytes")
        let text = first.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        expect(text.hasPrefix(#"{"allow-lan":false,"dns":{"#), "keys are sorted")
        expect(text.contains("https://sub.test/A") && !text.contains(#"\/"#), "slashes are not escaped")

        var profile = mixed()
        profile.strategies[1].name = "DIRECT"
        do {
            _ = try ProxyConfigBuilder.build(
                profile, environment: ProxyBuildEnvironment(mode: .tun, subscriptionURLs: [:]))
            expect(false, "an invalid profile does not build")
        } catch {
            expect(
                error.problems == profile.problems && !error.problems.isEmpty,
                "the build reports its problems")
        }
    }

    // MARK: - Modes

    static func testModes() {
        let rule = build(mixed())
        let global = build(mixed(), proxyMode: .global)
        let direct = build(mixed(), proxyMode: .direct)
        expect(rule?.document["mode"]?.string == "rule", "rule mode by default")
        expect(global?.document["mode"]?.string == "global", "the mode is written into the config")
        expect(direct?.document["mode"]?.string == "direct", "direct too")
        expect(
            rule?.reloadKey == global?.reloadKey && global?.reloadKey == direct?.reloadKey,
            "switching modes needs no reload")
        expect(
            rule?.selections.last == ProxyConfig.Selection(group: "GLOBAL", option: "默认代理"),
            "GLOBAL is pinned to the default strategy")
        for mode in ProxyMode.allCases {
            let data = try? JSONEncoder().encode(mode)
            expect(data.flatMap { try? JSONDecoder().decode(ProxyMode.self, from: $0) } == mode, "\(mode) codes")
        }
    }

    // MARK: - Rule catalog

    static func testRuleCatalog() {
        let listed = ProxyRuleCatalog.Section.allCases.flatMap(\.categories)
        expect(listed.count == ProxyRouteCategory.allCases.count, "each category is listed once")
        expect(Set(listed) == Set(ProxyRouteCategory.allCases), "every category is in a section")
        expect(ProxyRouteCategory.allCases.count == 86, "86 categories")
        expect(ProxyRuleCatalog.geosites.count > 1500 && ProxyRuleCatalog.geoips.count > 200, "the catalog list")
        for category in ProxyRouteCategory.allCases {
            for ruleSet in category.ruleSets {
                expect(ProxyRuleCatalog.ruleSet(named: ruleSet.catalogName) != nil, "\(ruleSet.catalogName) exists")
            }
        }
        let title: (ProxyRouteCategory) -> String = { $0.brand ?? $0.rawValue }
        expect(ProxyRuleCatalog.categories(matching: "奈飞", title: title) == [.netflix], "a Chinese alias")
        let chatGPT = ProxyRuleCatalog.categories(matching: "ChatGPT", title: title)
        expect(chatGPT.contains(.openai) && chatGPT.contains(.ai), "an alias finds the product and its category")
        expect(ProxyRuleCatalog.categories(matching: "geosite:twitter", title: title) == [.x], "a rule set name")
        expect(ProxyRuleCatalog.categories(matching: " ", title: title).count == 86, "nothing typed lists all")
        expect(
            ProxyRuleCatalog.ruleSets(matching: "geosite:openai", limit: 3).first?.catalogName == "geosite:openai",
            "an exact name comes first")
        expect(ProxyRuleCatalog.ruleSets(matching: "cn", limit: 5).count == 5, "results stop at the limit")
        expect(ProxyRuleCatalog.ruleSet(named: "GeoIP:CN")?.behavior == .ipcidr, "a geoip name, in any case")
        expect(ProxyRuleCatalog.ruleSet(named: "geosite:no-such-set") == nil, "an unknown name")
        expect(ProxyRuleCatalog.ruleSet(named: "netflix") == nil, "a bare name")
        let linked = ProxyRuleSet(
            name: "custom-1-1", behavior: .domain, format: .yaml, location: .url("https://a.test/x/Netflix.yaml?t=1"),
            resolves: false)
        expect(linked.catalogName == "Netflix.yaml" && linked.isLinked, "a link names its file")
        expect(ProxyRouteCategory.netflix.ruleSets.map(\.catalogName) == ["geosite:netflix", "geoip:netflix"], "names")
    }

    // MARK: - Rule-set links

    static func detect(_ text: String, link: String = "https://example.test/rules/List.txt", complete: Bool = true)
        -> ProxyRuleSetDetection
    {
        ProxyRuleSetDetection.detect(link: link, sample: Data(text.utf8), isComplete: complete)
    }

    static func testRuleSetDetection() {
        expect(
            ProxyRuleSetDetection.normalize(
                " https://github.com/blackmatrix7/ios_rule_script/blob/master/rule/Clash/Netflix/Netflix.yaml ")
                == "https://github.com/blackmatrix7/ios_rule_script/raw/master/rule/Clash/Netflix/Netflix.yaml",
            "a GitHub page becomes its file")
        expect(
            ProxyRuleSetDetection.normalize("https://raw.githubusercontent.com/a/b/main/x.yaml")
                == "https://raw.githubusercontent.com/a/b/main/x.yaml", "a raw link stays")

        let loyal = detect("payload:\n  - '+.google.com'\n  - 'example.org'\n")
        expect(loyal.format == .yaml && loyal.behavior == .domain && loyal.entries == 2, "Loyalsoldier domains")
        expect(loyal.name == "List", "the name is the file's")
        let cidr = detect("payload:\n  - '1.0.1.0/24'\n  - '2400:3200::/32'\n")
        expect(cidr.format == .yaml && cidr.behavior == .ipcidr, "Loyalsoldier's address list")
        let apps = detect("payload:\n  - PROCESS-NAME,v2ray\n")
        expect(apps.behavior == .classical, "Loyalsoldier's applications")
        let blackmatrix = detect(
            "# NAME: Netflix\n# AUTHOR: blackmatrix7\npayload:\n  - DOMAIN-SUFFIX,netflix.com\n  - IP-CIDR,23.246.0.0/18,no-resolve\n",
            link: "https://github.com/blackmatrix7/ios_rule_script/blob/master/rule/Clash/Netflix/Netflix.yaml")
        expect(blackmatrix.format == .yaml && blackmatrix.behavior == .classical, "blackmatrix7's Clash YAML")
        expect(blackmatrix.link.contains("/raw/master/") && blackmatrix.name == "Netflix", "its link and name")
        let list = detect("# NAME: Netflix\nDOMAIN-SUFFIX,netflix.com\nIP-CIDR,23.246.0.0/18,no-resolve\n")
        expect(list.format == .text && list.behavior == .classical, "a classical list")
        let sukka = detect("# $ meta_title Sukka's Ruleset\n.example.com\nexample.org\n")
        expect(sukka.format == .text && sukka.behavior == .domain && sukka.entries == 2, "SukkaW's domain set")
        let addresses = detect("1.1.1.0/24\n2001:db8::/32\n10.0.0.1\n")
        expect(addresses.behavior == .ipcidr, "a list of ranges")
        let bom = detect("\u{FEFF}payload:\n- a.com\n")
        expect(bom.format == .yaml && bom.entries == 1, "a byte order mark is skipped")
        let cut = detect("payload:\n  - '+.a.com'\n  - '+.b.c", complete: false)
        expect(cut.entries == 1, "a line cut by the sample is left out")

        let zstd = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x01])
        let geoip = ProxyRuleSetDetection.detect(
            link: "https://github.com/MetaCubeX/meta-rules-dat/raw/meta/geo/geoip/cn.mrs", sample: zstd,
            isComplete: true)
        expect(geoip.format == .mrs && geoip.behavior == .ipcidr && geoip.entries == nil, "an mrs address set")
        let geosite = ProxyRuleSetDetection.detect(
            link: "https://example.test/geosite/cn.mrs", sample: zstd, isComplete: true)
        expect(geosite.behavior == .domain, "an mrs domain set")
        let lan = ProxyRuleSetDetection.detect(link: "https://example.test/lancidr.mrs", sample: zstd, isComplete: true)
        expect(lan.behavior == .ipcidr, "a cidr name is addresses")

        expect(ProxyRuleSetDetection.guess(link: "https://a.test/x.mrs").format == .mrs, "a guess from .mrs")
        expect(ProxyRuleSetDetection.guess(link: "https://a.test/x.yml").format == .yaml, "and .yml")
        let plain = ProxyRuleSetDetection.guess(link: "https://a.test/x.list")
        expect(plain.format == .text && plain.behavior == .domain && plain.name == "x", "a plain guess")
        expect(ProxyRuleSetDetection.behavior(of: []) == .domain, "an empty sample reads as domains")
    }

    // MARK: - Flow

    static func testFlow() {
        var profile = starter()
        let primary = ProxyTarget.strategy(profile.defaultStrategy)
        let flow = ProxyFlow(profile: profile, mode: .rule)
        expect(
            flow.rows.map(\.source) == [
                "ai", "streaming", "telegram", "github", "foreign", "final", "lan", "apple", "china", "ads"
            ].map { .route($0) },
            "routes group by target: strategies, then Direct, then Reject")
        expect(flow.targets == [primary, .direct, .reject], "targets in that order")

        profile.rules = [rule(1, .domain, "a.test", .direct), rule(2, .domain, "b.test", primary)]
        profile.routes[0].isEnabled = false
        let ruled = ProxyFlow(profile: profile, mode: .rule)
        expect(
            ruled.rows.first == ProxyFlow.Row(source: .rules(count: 2), targets: [.direct, primary]),
            "the rules lead, with each target they use")
        expect(!ruled.rows.contains { $0.source == .route("ads") }, "a disabled route is left out")
        expect(!ruled.targets.contains(.reject), "and so is the target only it used")

        let global = ProxyFlow(profile: profile, mode: .global)
        expect(global.rows.allSatisfy { $0.targets == [primary] } && global.targets == [primary], "global")
        let direct = ProxyFlow(profile: profile, mode: .direct)
        expect(direct.rows.allSatisfy { $0.targets == [.direct] } && direct.targets == [.direct], "direct")

        let layout = flow.layout(rowHeight: 27, groupGap: 10, top: 32, targetSpacing: 46)
        expect(layout.rows.first == 45.5, "the first row's centre")
        expect(layout.rows[6] - layout.rows[5] == 37, "a gap between groups")
        expect(layout.rows[1] - layout.rows[0] == 27, "none inside one")
        let strategy = layout.targets[primary] ?? 0
        expect(strategy == (layout.rows[0] + layout.rows[5]) / 2, "a target sits by the middle of its rows")
        let sorted = flow.targets.compactMap { layout.targets[$0] }.sorted()
        expect(zip(sorted, sorted.dropFirst()).allSatisfy { $1 - $0 >= 46 }, "targets keep their spacing")
        expect(layout.height >= (layout.rows.last ?? 0) + 13.5, "the map fits its last row")
    }

    // MARK: - Activity

    static func connection(
        _ chains: [String], rule: String, payload: String, host: String = "www.google.com", port: String = #""443""#,
        inbound: String = "HTTP"
    ) -> ProxyAPI.Connection? {
        let chainList = chains.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
            {"id": "c1", "metadata": {"network": "tcp", "type": "\(inbound)", "sourceIP": "127.0.0.1",
            "destinationIP": "142.250.1.1", "sourcePort": "54321", "destinationPort": \(port),
            "host": "\(host)", "sniffHost": "", "process": "Safari", "processPath": "/x"},
            "upload": 10, "download": 20, "start": "2026-10-24T01:02:03.123456789+08:00",
            "chains": [\(chainList)], "providerChains": [], "rule": "\(rule)", "rulePayload": "\(payload)"}
            """
        return try? JSONDecoder().decode(ProxyAPI.Connection.self, from: Data(json.utf8))
    }

    static func testActivity() {
        var profile = starter()
        profile.addRoute(.category(.google, to: .strategy(profile.strategies[1].id)))
        profile.rules = [rule(1, .domainSuffix, "example.com", .reject)]
        let fastest = profile.strategies[1]
        guard let proxied = connection(["🇭🇰 香港 01", "自动最快", "route/google"], rule: "RuleSet", payload: "geosite-google")
        else {
            expect(false, "a connection decodes")
            return
        }
        expect(proxied.destinationPort == 443 && proxied.start != nil && proxied.upload == 10, "its fields")
        let activity = ProxyActivity(proxied, profile: profile)
        expect(activity.match == .route("google"), "a rule set names its route")
        expect(activity.target == .strategy(fastest.id) && activity.node == "🇭🇰 香港 01", "the strategy and node")
        expect(activity.host == "www.google.com" && activity.process == "Safari", "the host and app")

        let direct = connection(["DIRECT", "route/china"], rule: "RuleSet", payload: "geosite-cn").map {
            ProxyActivity($0, profile: profile)
        }
        expect(direct?.match == .route("china") && direct?.target == .direct && direct?.node == nil, "direct")
        let rejected = connection(["REJECT", "route/ads"], rule: "RuleSet", payload: "geosite-category-ads-all")
            .map { ProxyActivity($0, profile: profile) }
        expect(rejected?.target == .reject, "rejected")
        let ruled = connection(["REJECT"], rule: "DomainSuffix", payload: "example.com").map {
            ProxyActivity($0, profile: profile)
        }
        expect(ruled?.match == .rule(uuid(1)) && ruled?.target == .reject, "a rule of the user's")
        let rest = connection(["节点", "自动最快", "默认代理", "route/final"], rule: "Match", payload: "").map {
            ProxyActivity($0, profile: profile)
        }
        expect(rest?.match == .route(ProxyRoute.finalID), "the remaining traffic")
        expect(rest?.target == .strategy(profile.defaultStrategy) && rest?.node == "节点", "the outermost strategy")
        let global = connection(["节点", "自动最快", "默认代理", "GLOBAL"], rule: "", payload: "").map {
            ProxyActivity($0, profile: profile)
        }
        expect(global?.match == .mode && global?.target == .strategy(profile.defaultStrategy), "global mode")
        let inner = connection(["节点", "默认代理"], rule: "", payload: "", host: "github.com", inbound: "Inner").map {
            ProxyActivity($0, profile: profile)
        }
        expect(
            inner?.match == .core && inner?.target == .strategy(profile.defaultStrategy),
            "the core's own download is its own, not a mode or a rule")
        let bare = connection(["DIRECT"], rule: "IPCIDR", payload: "10.0.0.0/8", host: "", port: "443").map {
            ProxyActivity($0, profile: profile)
        }
        expect(bare?.host == "142.250.1.1" && bare?.match == .unknown, "a bare address, an unknown rule")
        let snapshot = try? JSONDecoder().decode(ProxyAPI.Connections.self, from: Data(#"{"connections": null}"#.utf8))
        expect(snapshot?.connections == [], "no connections decodes as none")
    }

    // MARK: - Probe

    static func testProbe() {
        let openAI = ProxyProbe.Destination("https://chat.openai.com/c/123")
        expect(openAI?.host == "chat.openai.com" && openAI?.port == 443, "a URL's host, on HTTPS")
        expect(ProxyProbe.Destination("http://example.com")?.port == 80, "plain HTTP")
        expect(ProxyProbe.Destination("example.com:8443")?.port == 8443, "an explicit port")
        expect(ProxyProbe.Destination("[2001:db8::1]:443")?.address == "[2001:db8::1]:443", "an IPv6 address")
        expect(ProxyProbe.Destination("  ") == nil, "nothing typed")
        guard let destination = openAI else { return }
        let matched =
            "[TCP] 127.0.0.1:54321(Tinycast, uid=501) --> chat.openai.com:443 match RuleSet(geosite-category-ai-!cn) using route/ai[🇭🇰 香港 01]"
        expect(
            ProxyProbe.outcome(of: matched, sourcePort: 54321, destination: destination)
                == .matched(rule: "RuleSet", payload: "geosite-category-ai-!cn", exit: "🇭🇰 香港 01"),
            "a matched connection")
        expect(ProxyProbe.outcome(of: matched, sourcePort: 5432, destination: destination) == nil, "another port")
        expect(ProxyProbe.outcome(of: matched, sourcePort: 4321, destination: destination) == nil, "a port's tail")
        let other = ProxyProbe.Destination("example.com")!
        expect(ProxyProbe.outcome(of: matched, sourcePort: 54321, destination: other) == nil, "another site")
        expect(
            ProxyProbe.outcome(
                of: "[TCP] 127.0.0.1:54321 --> chat.openai.com:443 match Match using route/final[DIRECT]",
                sourcePort: 54321, destination: destination) == .matched(rule: "Match", payload: "", exit: "DIRECT"),
            "the remaining traffic")
        expect(
            ProxyProbe.outcome(
                of: "[TCP] 127.0.0.1:54321(Tinycast) --> chat.openai.com:443 using GLOBAL", sourcePort: 54321,
                destination: destination) == .mode(exit: "GLOBAL"),
            "global mode")
        expect(
            ProxyProbe.outcome(
                of:
                    "[TCP] dial route/ai (match RuleSet/geosite-openai) 127.0.0.1:54321(Tinycast) --> chat.openai.com:443 error: connect failed",
                sourcePort: 54321, destination: destination)
                == .failed(rule: "RuleSet", payload: "geosite-openai", reason: "connect failed"),
            "a node that did not connect")
    }

    // MARK: - Node names

    static func testNodeNames() {
        let noted = ProxyNodeName("香港01：通用客户端暂时保持兼容")
        expect(noted.title == "香港01" && noted.note == "通用客户端暂时保持兼容", "a full-width colon starts a note")
        let barred = ProxyNodeName("🇭🇰 HK 01 | 0.5x")
        expect(barred.title == "HK 01" && barred.note == "0.5x", "a bar starts one too, after the flag")
        expect(ProxyNodeName("US: Los Angeles 01").note == nil, "a head without a number is not a name")
        let long = ProxyNodeName("Hong Kong Premium IPLC 01 - 0.5x")
        expect(long.note == nil && long.title == "Hong Kong Premium IPLC 01 - 0.5x", "nor is a long head")
        expect(ProxyNodeName("台湾动态ip").note == nil, "no separator, no note")
        expect(ProxyNodeName("香港01：").note == nil, "an empty note is none")
    }

    // MARK: - Site test paths

    static func testProbeHighlight() {
        var profile = starter()
        let primary = ProxyTarget.strategy(profile.defaultStrategy)
        guard let destination = ProxyProbe.Destination("chat.openai.com"),
            let ai = profile.routes.first(where: { $0.id == "ai" }), let set = ai.ruleSets.first?.name
        else {
            expect(false, "the starter routes AI")
            return
        }
        let routed = ProxyProbe(
            destination: destination, outcome: .matched(rule: "RuleSet", payload: set, exit: "香港 01"))
        expect(
            routed.highlight(in: profile, mode: .rule)
                == ProxyFlow.Highlight(source: .route("ai"), target: ai.target, exit: "香港 01"),
            "a route's row, its target and the node the test left through")
        let rest = ProxyProbe(destination: destination, outcome: .matched(rule: "Match", payload: "", exit: "DIRECT"))
        expect(rest.highlight(in: profile, mode: .rule)?.source == .route(ProxyRoute.finalID), "the remaining traffic")
        profile.rules = [rule(1, .domain, "chat.openai.com", .direct)]
        let ruled = ProxyProbe(
            destination: destination, outcome: .matched(rule: "Domain", payload: "chat.openai.com", exit: "DIRECT"))
        expect(
            ruled.highlight(in: profile, mode: .rule)
                == ProxyFlow.Highlight(source: .rules(count: 1), target: .direct, exit: "DIRECT"),
            "a rule of the user's lights the rules row, toward that rule's target")
        let forced = ProxyProbe(destination: destination, outcome: .mode(exit: "GLOBAL"))
        expect(
            forced.highlight(in: profile, mode: .global) == ProxyFlow.Highlight(source: nil, target: primary),
            "global mode lights every row into the default strategy")
        expect(forced.highlight(in: profile, mode: .direct)?.target == .direct, "direct mode, into Direct")
        let failed = ProxyProbe(
            destination: destination, outcome: .failed(rule: "RuleSet", payload: set, reason: "timeout"))
        expect(failed.highlight(in: profile, mode: .rule)?.failed == true, "a failure marks the path")
        let unknown = ProxyProbe(
            destination: destination, outcome: .matched(rule: "RuleSet", payload: "gone", exit: "DIRECT"))
        expect(unknown.highlight(in: profile, mode: .rule) == nil, "a rule set no route holds lights nothing")
    }

    static func main() {
        testRegionClassification()
        testNodeFileOutline()
        testCodingRoundTrip()
        testStarterAndRecommendedRoutes()
        testNames()
        testReferencesAndCycles()
        testPatternsAndSettings()
        testRuleNormalization()
        testRuleCandidates()
        testLauncherHints()
        testRuleMatching()
        testProviders()
        testStrategyGroups()
        testPoolPreview()
        testRouteGroupsAndSelections()
        testRules()
        testDNSAndTUN()
        testDeterminismAndFailure()
        testModes()
        testRuleCatalog()
        testRuleSetDetection()
        testFlow()
        testActivity()
        testProbe()
        testNodeNames()
        testProbeHighlight()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
