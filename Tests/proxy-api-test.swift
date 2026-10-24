import CryptoKit
import Foundation

@main
@MainActor
struct ProxyAPITests {
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

    /// Feeds `text` in pieces of `size` bytes, as a socket might deliver it.
    static func parse(_ text: String, pieces size: Int, close: Bool = false) -> [ProxyHTTP.Event]? {
        var parser = ProxyHTTP.ResponseParser()
        var events: [ProxyHTTP.Event] = []
        let bytes = Array(text.utf8)
        do {
            for start in stride(from: 0, to: bytes.count, by: size) {
                events += try parser.consume(bytes[start..<min(start + size, bytes.count)])
            }
            if close { events += try parser.finish() }
        } catch {
            return nil
        }
        return events
    }

    static func body(_ events: [ProxyHTTP.Event]?) -> String? {
        guard let events, events.last == .end else { return nil }
        var data = Data()
        for case .body(let chunk) in events { data.append(chunk) }
        return String(bytes: data, encoding: .utf8)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) -> Value? {
        try? JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    static let provider = #"""
        {"name": "src-00000001", "type": "Proxy", "vehicleType": "HTTP", "proxies": [{"alive": true,
        "dialer-proxy": "", "extra": {"http://127.0.0.1:41100/generate_204": {"alive": true, "history": [{"time":
        "2026-10-22T00:32:14.1043+08:00", "delay": 7}]}}, "history": [{"time": "2026-10-22T00:32:14.1043+08:00",
        "delay": 9}], "id": "f61bd6be", "name": "🇭🇰 香港 01", "provider-name": "src-00000001", "type":
        "Shadowsocks", "udp": false}, {"alive": false, "history": [{"time": "2026-10-22T00:32:15+08:00", "delay": 0}],
        "name": "🇺🇸 美国 01", "provider-name": "src-00000001", "type": "Trojan", "udp": true}, {"name": "日本 01",
        "type": "Vmess", "history": null}], "testUrl": "", "expectedStatus": "*",
        "updatedAt": "2026-10-22T00:32:14.098231+08:00",
        "subscriptionInfo": {"Upload": 1024, "Download": 2048, "Total": 1073741824, "Expire": 1893456000}}
        """#

    static let proxies = #"""
        {"proxies": {"默认代理": {"alive": true, "all": ["自动最快", "🇭🇰 香港 01", "🇺🇸 美国 01"],
        "hidden": false, "history": [], "name": "默认代理", "now": "自动最快", "provider-name": "", "testUrl": "",
        "type": "Selector", "udp": true}, "自动最快": {"all": ["🇭🇰 香港 01", "🇺🇸 美国 01"], "name": "自动最快",
        "now": "🇭🇰 香港 01", "type": "URLTest", "testUrl": "https://www.gstatic.com/generate_204"},
        "route/ai": {"all": ["默认代理", "DIRECT"], "hidden": true, "name": "route/ai", "now": "DIRECT",
        "type": "Selector"}, "route/final": {"all": ["默认代理", "DIRECT"], "hidden": true, "name": "route/final",
        "now": "默认代理", "type": "Selector"}, "DIRECT": {"name": "DIRECT", "type": "Direct", "udp": true,
        "history": []}}}
        """#

    // MARK: - HTTP

    static func testRequests() {
        let get = String(bytes: ProxyHTTP.Request.get("/version").bytes, encoding: .utf8)
        expect(
            get == "GET /version HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
            "a GET closes its connection")
        let put = String(
            bytes: ProxyHTTP.Request.put("/proxies/a", json: Data("{}".utf8)).bytes, encoding: .utf8)
        expect(
            put == "PUT /proxies/a HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
                + "Content-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
            "a PUT carries its JSON body")
        let empty = String(bytes: ProxyHTTP.Request.put("/providers/proxies/a").bytes, encoding: .utf8)
        expect(empty?.contains("Content-Length: 0\r\n") == true, "an empty PUT says so")

        expect(ProxyHTTP.segment("route/ai") == "route%2Fai", "a slash in a name stays in one segment")
        expect(
            ProxyHTTP.segment("🇭🇰 香港 01").contains("%20") && ProxyHTTP.segment("a-b_c.d~e") == "a-b_c.d~e",
            "spaces and any script are encoded, unreserved characters are not")
        expect(
            ProxyHTTP.query([("url", "https://x.test/a?b=c"), ("timeout", "5000")])
                == "url=https%3A%2F%2Fx.test%2Fa%3Fb%3Dc&timeout=5000",
            "query values are encoded whole")
    }

    static func testResponses() {
        let fixed =
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 34\r\n\r\n"
            + #"{"meta":true,"version":"v1.19.32"}"#
        for size in [1, 3, 7, 4096] {
            let events = parse(fixed, pieces: size)
            expect(
                body(events) == #"{"meta":true,"version":"v1.19.32"}"#, "a sized body in \(size)-byte pieces")
            if case .head(let head) = events?.first {
                expect(head.status == 200 && head.headers["content-type"] == "application/json", "the head")
            } else {
                expect(false, "the head comes first")
            }
        }

        let chunked =
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
            + "12\r\n{\"up\":1,\"down\":2}\n\r\n" + "5;ext=1\r\nhello\r\n" + "0\r\nX-Trailer: 1\r\n\r\n"
        for size in [1, 2, 5, 4096] {
            expect(
                body(parse(chunked, pieces: size)) == "{\"up\":1,\"down\":2}\nhello",
                "chunks in \(size)-byte pieces")
        }

        let noContent = parse("HTTP/1.1 204 No Content\r\nDate: x\r\n\r\n", pieces: 4096)
        expect(noContent?.last == .end && noContent?.count == 2, "204 has no body and ends at once")
        let untilClose = parse("HTTP/1.1 200 OK\r\n\r\nall of it", pieces: 3, close: true)
        expect(body(untilClose) == "all of it", "a body without a length runs until the close")
        expect(
            parse("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nshort", pieces: 4, close: true) == nil,
            "a close before the length is truncated")
        expect(
            parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n", pieces: 4) == nil,
            "a chunk size that is not hex is malformed")
        expect(parse("garbage\r\n\r\n", pieces: 4) == nil, "a status line that is not HTTP is malformed")
        expect(parse(String(repeating: "a", count: 70_000), pieces: 8192) == nil, "a runaway head is refused")
        let error =
            "HTTP/1.1 400 Bad Request\r\nContent-Length: 46\r\n\r\n"
            + #"{"message":"Selector update error: no proxy"}"#
        if case .head(let head) = parse(error, pieces: 4096)?.first {
            expect(head.status == 400, "a rejection keeps its status")
        } else {
            expect(false, "a rejection has a head")
        }
    }

    static func testLines() {
        var splitter = ProxyHTTP.LineSplitter()
        var lines = splitter.consume(Data("{\"up\":1}\n{\"up\"".utf8))
        lines += splitter.consume(Data(":2}\r\n\n{\"up\":3}".utf8))
        expect(
            lines.compactMap { String(bytes: $0, encoding: .utf8) } == ["{\"up\":1}", "{\"up\":2}"],
            "records split on newlines across reads, without empty lines or carriage returns")
        lines = splitter.consume(Data("\n".utf8))
        expect(
            lines.compactMap { String(bytes: $0, encoding: .utf8) } == ["{\"up\":3}"],
            "the rest arrives later")
    }

    // MARK: - Payloads

    static func testPayloads() {
        let decoded = decode(ProxyAPI.Provider.self, provider)
        expect(decoded?.vehicleType == "HTTP" && decoded?.proxies.count == 3, "a provider and its nodes")
        expect(
            decoded?.usage
                == ProxyAPI.Usage(upload: 1024, download: 2048, total: 1_073_741_824, expire: 1_893_456_000),
            "subscription usage")
        let updated = decoded?.updatedAt?.timeIntervalSince1970 ?? 0
        expect(abs(updated - 1_792_600_334.098231) < 0.000_01, "microsecond timestamps")
        let node = decoded?.proxies.first
        expect(
            node?.providerName == "src-00000001" && node?.type == "Shadowsocks" && node?.udp == false,
            "a node")
        expect(node?.latest.history.last?.delay == 9, "a node's latest test")
        expect(node?.tests["http://127.0.0.1:41100/generate_204"]?.history.last?.delay == 7, "tests by URL")
        expect(
            decoded?.proxies.last?.latest.history == [] && decoded?.proxies.last?.tests == [:],
            "null and missing histories decode as empty")

        let compatible = decode(
            ProxyAPI.Provider.self,
            #"{"name": "默认代理", "type": "Proxy", "vehicleType": "Compatible", "updatedAt": "0001-01-01T00:00:00Z"}"#
        )
        expect(
            compatible?.updatedAt == nil && compatible?.proxies == [], "Go's zero time means never updated")

        let groups = decode(ProxyAPI.Proxies.self, proxies)?.proxies
        expect(groups?["默认代理"]?.now == "自动最快" && groups?["默认代理"]?.all.count == 3, "a group's pick")
        expect(groups?["route/ai"]?.hidden == true && groups?["默认代理"]?.hidden == false, "hidden groups")
        expect(
            groups?["默认代理"]?.testURL == nil && groups?["自动最快"]?.testURL != nil, "an empty test URL is none")
        expect(groups?["DIRECT"]?.now == nil && groups?["DIRECT"]?.all == [], "built-ins have no options")

        let rules = decode(
            ProxyAPI.RuleProviders.self,
            #"""
            {"providers": {"geoip-cn": {"behavior": "IPCIDR", "format": "MrsRule", "name": "geoip-cn",
            "ruleCount": 1, "type": "Rule", "vehicleType": "HTTP", "updatedAt": "2026-10-22T00:32:14.120248+08:00"}}}
            """#)
        expect(rules?.providers["geoip-cn"]?.ruleCount == 1, "rule providers count their rules")
        let traffic = decode(ProxyAPI.Traffic.self, #"{"up":0,"down":5,"upTotal":2337,"downTotal":5741}"#)
        expect(
            traffic == ProxyAPI.Traffic(up: 0, down: 5, upTotal: 2337, downTotal: 5741), "a traffic record")
        expect(
            decode(ProxyAPI.Message.self, #"{"message":"Resource not found"}"#)?.message
                == "Resource not found",
            "the core's error message")
        expect(ProxyAPI.date("not a date") == nil, "an unreadable date is none")
    }

    // MARK: - Snapshot

    static func testSnapshot() {
        var profile = ProxyProfile.starter(defaultName: "默认代理", fastestName: "自动最快") { UUID() }
        var other = ProxySource.subscription(id: uuid(2), name: "B")
        other.isEnabled = true
        profile.sources = [ProxySource.subscription(id: uuid(1), name: "A"), other]
        profile.routes = [ProxyRoute.category(.ai, to: .direct)]
        guard let first = decode(ProxyAPI.Provider.self, provider),
            let groups = decode(ProxyAPI.Proxies.self, proxies)?.proxies
        else {
            expect(false, "fixtures decode")
            return
        }
        var second = first
        second.name = "src-00000002"
        second.proxies = [first.proxies[0]]
        second.usage = nil
        let snapshot = ProxySnapshot(
            proxies: groups, providers: ["src-00000001": first, "src-00000002": second, "默认代理": first],
            profile: profile)
        let hongKong = snapshot.nodes["🇭🇰 香港 01"]
        expect(
            hongKong?.source == uuid(1) && hongKong?.region == .hongKong, "a node knows its source and region"
        )
        expect(
            hongKong?.delay(for: "http://127.0.0.1:41100/generate_204") == .milliseconds(7),
            "a strategy's URL")
        expect(hongKong?.delay(for: "https://elsewhere.test") == .milliseconds(9), "else the latest test")
        expect(hongKong?.delay(for: nil) == .milliseconds(9), "no URL means the latest test")
        expect(snapshot.nodes["🇺🇸 美国 01"]?.latest == .failed, "a failed test")
        expect(snapshot.nodes["日本 01"]?.latest == .untested, "a node never tested")
        expect(snapshot.duplicates == ["🇭🇰 香港 01"], "a name two sources share is reported")
        expect(
            snapshot.sources[uuid(1)]?.nodes.count == 3 && snapshot.sources[uuid(2)]?.nodes.count == 1,
            "each source lists its own nodes, duplicates included")
        expect(snapshot.sources[uuid(1)]?.usage?.total == 1_073_741_824, "usage by source")
        expect(snapshot.nodes.count == 3, "a provider no source owns is ignored")
        let primary = profile.strategies[0].id
        expect(snapshot.strategies[primary]?.current == "自动最快", "strategies by id")
        expect(snapshot.routes == ["ai": "DIRECT", "final": "默认代理"], "routes by id, the final one included")
        expect(
            snapshot.node(reachedBy: primary, in: profile)?.name == "🇭🇰 香港 01",
            "a strategy reaches the node its picks lead to")
        var looped = profile
        looped.strategies[0].name = "自动最快"
        expect(snapshot.node(reachedBy: primary, in: looped) == nil, "a pick that leads back stops")
    }

    // MARK: - Restarts and checks

    static func testRestartPolicy() {
        var policy = ProxyRestartPolicy()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let delays = (0..<5).map { policy.delay(afterExitAt: start.addingTimeInterval(Double($0) * 10)) }
        expect(
            delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), nil], "doubling, then giving up")
        var spread = ProxyRestartPolicy()
        let late = (0..<6).map { spread.delay(afterExitAt: start.addingTimeInterval(Double($0) * 200)) }
        expect(late.allSatisfy { $0 != nil }, "exits spread over time never exhaust it")
        policy.reset()
        expect(policy.delay(afterExitAt: start) == .seconds(1), "a reset starts over")
    }

    static func testCheckOutput() {
        let error = """
            time="2026-10-22T00:39:02.79+08:00" level=info msg="Start initial configuration in progress"
            time="2026-10-22T00:39:02.79+08:00" level=error msg="proxy group[0]: A: 'missing' not found \\"x\\""
            configuration file /tmp/bad.json test failed
            """
        expect(
            ProxyCoreRunner.reason(fromCheckOutput: error) == "proxy group[0]: A: 'missing' not found \"x\"",
            "the first error, unescaped")
        let panic =
            "panic: regexp2: Compile(`a++`): error parsing regexp: invalid nested repetition operator\n"
            + "goroutine 1 [running]:"
        expect(
            ProxyCoreRunner.reason(fromCheckOutput: panic)?.hasPrefix("regexp2: Compile(`a++`)") == true,
            "a panic's message")
        expect(
            ProxyCoreRunner.reason(fromCheckOutput: "configuration file x test is successful") == nil,
            "a passing check has no reason")
    }

    // MARK: - Core releases

    static func releaseJSON(
        tag: String = "v1.19.33", draft: Bool = false, prerelease: Bool = false, digest: String? = nil,
        url: String? = nil, arm64: Bool = true
    ) -> Data {
        let arm = "mihomo-darwin-arm64-\(tag).gz"
        let intel = "mihomo-darwin-amd64-compatible-\(tag).gz"
        let base = "https://github.com/MetaCubeX/mihomo/releases/download/\(tag)/"
        var assets: [[String: Any]] = [
            [
                "name": "mihomo-darwin-amd64-v1-\(tag).gz", "size": 1,
                "digest": "sha256:" + String(repeating: "1", count: 64),
                "browser_download_url": base + "mihomo-darwin-amd64-v1-\(tag).gz"
            ],
            [
                "name": intel, "size": 2, "digest": "sha256:" + String(repeating: "B", count: 64),
                "browser_download_url": base + intel
            ]
        ]
        if arm64 {
            var asset: [String: Any] = [
                "name": arm, "size": 20_756_622, "browser_download_url": url ?? base + arm
            ]
            asset["digest"] = digest ?? "sha256:" + String(repeating: "a", count: 64)
            assets.append(asset)
        }
        let release: [String: Any] = [
            "tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": assets,
            "body": "notes", "published_at": "2026-10-21T16:56:13Z"
        ]
        return (try? JSONSerialization.data(withJSONObject: release)) ?? Data()
    }

    static func parsed(
        _ data: Data, _ architecture: ReleaseArchitecture = .appleSilicon
    )
        -> Result<ProxyCoreRelease, ProxyCoreUpdateFailure>
    {
        Result { () throws(ProxyCoreUpdateFailure) in
            try ProxyCoreRelease.parse(data, architecture: architecture)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func testCoreReleases() {
        expect(
            ProxyCoreRelease.assetName(tag: "v1.19.32", architecture: .appleSilicon)
                == "mihomo-darwin-arm64-v1.19.32.gz"
                && ProxyCoreRelease.assetName(tag: "v1.19.32", architecture: .intel)
                    == "mihomo-darwin-amd64-compatible-v1.19.32.gz",
            "asset names match Scripts/fetch-mihomo.sh")

        let release = try? parsed(releaseJSON()).get()
        expect(release?.tag == "v1.19.33" && release?.version == AppVersion("1.19.33"), "the tag and version")
        expect(
            release?.assetURL.absoluteString
                == "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-darwin-arm64-v1.19.33.gz",
            "Apple silicon takes the arm64 build")
        expect(release?.assetSize == 20_756_622, "the archive size")
        expect(release?.sha256 == String(repeating: "a", count: 64), "the digest without its prefix")
        let intel = try? parsed(releaseJSON(), .intel).get()
        expect(
            intel?.assetURL.lastPathComponent == "mihomo-darwin-amd64-compatible-v1.19.33.gz"
                && intel?.sha256 == String(repeating: "b", count: 64),
            "Intel takes the build for any x86-64 CPU, its digest lowercased")

        expect(parsed(releaseJSON(draft: true)) == .failure(.noRelease), "a draft is not a release")
        expect(parsed(releaseJSON(prerelease: true)) == .failure(.noRelease), "nor is a prerelease")
        expect(parsed(releaseJSON(tag: "Prerelease-Alpha")) == .failure(.noRelease), "nor the alpha tag")
        expect(parsed(Data("not json".utf8)) == .failure(.noRelease), "nor an unreadable body")
        expect(parsed(releaseJSON(arm64: false)) == .failure(.noAsset), "no build for this Mac")
        expect(parsed(releaseJSON(url: "ftp://example.com/x.gz")) == .failure(.noAsset), "a non-web download")
        expect(parsed(releaseJSON(digest: "")) == .failure(.unverifiable), "no published digest")
        expect(
            parsed(releaseJSON(digest: "sha512:" + String(repeating: "a", count: 64)))
                == .failure(.unverifiable),
            "another algorithm")
        expect(
            parsed(releaseJSON(digest: "sha256:" + String(repeating: "g", count: 64)))
                == .failure(.unverifiable),
            "a digest that is not hex")
        expect(
            parsed(releaseJSON(digest: "sha256:" + String(repeating: "a", count: 63)))
                == .failure(.unverifiable),
            "a short digest")

        let archive = Data("an archive".utf8)
        let good = ProxyCoreRelease(
            version: AppVersion("1.19.33")!, tag: "v1.19.33", assetURL: URL(filePath: "/x.gz"),
            assetSize: Int64(archive.count), sha256: sha256(archive))
        expect((try? good.verify(archive)) != nil, "an archive matching its digest verifies")
        var tampered = good
        tampered.sha256 = String(repeating: "0", count: 64)
        let refused: ProxyCoreUpdateFailure?
        do {
            try tampered.verify(archive)
            refused = nil
        } catch {
            refused = error
        }
        expect(refused == .checksumMismatch, "a mismatched digest is refused")
    }

    static func testCoreChoice() {
        let line =
            "Mihomo Meta v1.19.32 darwin arm64 with go1.26.8 Wed Sep 30 17:00:14 UTC 2026\nUse tags: with_gvisor\n"
        expect(
            ProxyCore.Identity(versionOutput: line)
                == ProxyCore.Identity(tag: "v1.19.32", architecture: "arm64"),
            "the identity from -v")
        expect(
            ProxyCore.Identity.expected(tag: "v1.19.32", architecture: .appleSilicon)
                == ProxyCore.Identity(tag: "v1.19.32", architecture: "arm64")
                && ProxyCore.Identity.expected(tag: "v1.19.32", architecture: .intel).architecture == "amd64",
            "what an official build for each Mac reports")
        expect(ProxyCore.Identity(versionOutput: "Clash v1.0 linux arm64") == nil, "another program")
        expect(ProxyCore.Identity(versionOutput: "Mihomo Meta v1.19.32") == nil, "a truncated line")
        expect(ProxyCore.Identity(versionOutput: "Mihomo Meta v1 linux arm64 x") == nil, "another platform")

        func core(_ version: String?, bundled: Bool = false) -> ProxyCore {
            ProxyCore(
                executable: URL(filePath: bundled ? "/app/mihomo" : "/releases/\(version ?? "x")/mihomo"),
                version: version.flatMap(AppVersion.init), isBundled: bundled)
        }
        let shipped = core("v1.19.32", bundled: true)
        let none = ProxyCore.choose(bundled: shipped, downloads: [])
        expect(
            none.chosen == shipped && none.retired.isEmpty, "with nothing downloaded the bundled core runs")
        let newer = ProxyCore.choose(bundled: shipped, downloads: [core("v1.19.33")])
        expect(newer.chosen == core("v1.19.33") && newer.retired.isEmpty, "a newer download runs")
        let tie = ProxyCore.choose(bundled: core("v1.19.33", bundled: true), downloads: [core("v1.19.33")])
        expect(
            tie.chosen?.isBundled == true && tie.retired == [core("v1.19.33")],
            "a tie goes to the signed bundled core, retiring the download")
        let stale = ProxyCore.choose(
            bundled: core("v1.19.40", bundled: true), downloads: [core("v1.19.33"), core("v1.19.35")])
        expect(
            stale.chosen?.isBundled == true
                && Set(stale.retired.compactMap(\.tag)) == ["v1.19.33", "v1.19.35"],
            "an app update with a newer core retires every download")
        let several = ProxyCore.choose(
            bundled: shipped, downloads: [core("v1.19.34"), core("v1.19.40"), core("v1.19.33")])
        expect(
            several.chosen == core("v1.19.40")
                && Set(several.retired.compactMap(\.tag)) == ["v1.19.33", "v1.19.34"],
            "only the newest download is kept")
        let unknown = ProxyCore.choose(bundled: core(nil, bundled: true), downloads: [core("v1.19.33")])
        expect(unknown.chosen == core("v1.19.33"), "a bundled core that cannot say its version loses")
        let missing = ProxyCore.choose(bundled: nil, downloads: [core("v1.19.33")])
        expect(missing.chosen == core("v1.19.33"), "a build without a core runs its download")
        expect(ProxyCore.choose(bundled: nil, downloads: []).chosen == nil, "and with neither, nothing")
    }

    static func main() {
        testRequests()
        testResponses()
        testLines()
        testPayloads()
        testSnapshot()
        testRestartPolicy()
        testCheckOutput()
        testCoreReleases()
        testCoreChoice()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
