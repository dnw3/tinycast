import CryptoKit
import Foundation
import Synchronization

/// Drives the shipped `ProxyManager` against the real core; run it with `Scripts/proxy-smoke.sh`.
@main
@MainActor
struct ProxySmoke {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
            print("ok    \(message)")
        } else {
            failures += 1
            print("FAIL  \(message)")
        }
    }

    static func check(
        _ message: @autoclosure () -> String, within timeout: Duration, _ condition: () -> Bool
    ) async {
        let met = await waitFor(timeout, condition)
        expect(met, message())
    }

    static func waitFor(_ timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// A plain HTTP request through the core's mixed port.
    static func fetch(_ url: String, port: Int) async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: 1, kCFNetworkProxiesHTTPProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPPort: port
        ]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let url = URL(string: url), let (data, response) = try? await session.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    static func currentMode(_ api: ProxyAPIService) async -> String? {
        guard let data = try? await api.send(.get("/configs")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["mode"] as? String
    }

    static func corePID(_ store: ProxyStore) -> String? {
        try? String(contentsOf: store.coreDirectory.appending(path: "core.pid"), encoding: .utf8)
    }

    /// Serves `archive` as release `tag` the way GitHub's API describes one, digest included.
    static func publish(_ tag: String, archive: Data, in www: URL, base: String, digest: String? = nil) {
        let name = ProxyCoreRelease.assetName(tag: tag, architecture: .current)
        try? archive.write(to: www.appending(path: name))
        let sha256 = digest ?? SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        let asset: [String: Any] = [
            "name": name, "size": archive.count, "digest": "sha256:" + sha256,
            "browser_download_url": base + "/" + name
        ]
        let release: [String: Any] = ["tag_name": tag, "draft": false, "prerelease": false, "assets": [asset]]
        try? JSONSerialization.data(withJSONObject: release).write(to: www.appending(path: "release.json"))
    }

    static func offered(_ manager: ProxyManager) -> String? {
        if case .available(let release) = manager.coreUpdate { return release.tag }
        return nil
    }

    /// Passes the install checks as release `tag`, then exits as soon as it is started for real.
    static func brokenCore(_ tag: String) -> Data {
        let machine = ProxyCore.Identity.expected(tag: tag, architecture: .current).architecture
        let script = """
            #!/bin/sh
            case "$1" in
                -v) echo "Mihomo Meta \(tag) darwin \(machine) with go1.0 broken"; exit 0 ;;
                -t) exit 0 ;;
            esac
            exit 3
            """
        return (try? Zlib.gzip(Data(script.utf8))) ?? Data()
    }

    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        guard let work = environment["SMOKE_WORK"], let base = environment["SMOKE_BASE"],
            let target = environment["SMOKE_TARGET"], let dns = environment["SMOKE_DNS"],
            let mixed = environment["SMOKE_MIXED"].flatMap(Int.init), let nodes = environment["SMOKE_NODES"],
            let version = environment["SMOKE_VERSION"], let archive = environment["SMOKE_ARCHIVE"],
            let pinnedCore = environment["SMOKE_CORE"]
        else {
            print("run through Scripts/proxy-smoke.sh")
            exit(2)
        }
        let secrets = KeychainSecretStore(
            scope: "proxy-smoke-\(UUID().uuidString)", bundleIdentifier: "com.tinycast.harness")
        let store = ProxyStore(directory: URL(filePath: work).appending(path: "Proxy"), secrets: secrets)
        let manager = ProxyManager(
            store: store, runtimeDirectory: URL(filePath: work).appending(path: "run"),
            ruleCatalogBase: base + "/geo", coreFeed: URL(string: base + "/release.json")!)
        let www = URL(filePath: work).appending(path: "www")
        let releases = store.releasesDirectory
        let a = ProxySource.subscription(id: UUID(), name: "机场 A")
        var b = ProxySource.subscription(id: UUID(), name: "机场 B")
        b.prefix = "B·"
        b.renames = [ProxyRename(pattern: "香港", replacement: "HK")]
        let c = ProxySource.file(id: UUID(), name: "自建", path: nodes)
        defer {
            try? secrets.removeSecret(for: a.id)
            try? secrets.removeSecret(for: b.id)
        }
        let testURL = "http://\(target)/generate_204"
        let hongKong = UUID()
        do {
            try store.setSubscriptionURL(base + "/sub-a.yaml", for: a.id)
            try store.setSubscriptionURL(base + "/sub-b.txt", for: b.id)
            try manager.update { profile in
                profile.isEnabled = true
                profile.sources = [a, b, c]
                profile.general.mixedPort = mixed
                profile.general.domesticDNS = [dns]
                profile.general.foreignDNS = ["tcp://" + dns]
                for index in profile.strategies.indices { profile.strategies[index].testURL = testURL }
                var strategy = ProxyStrategy(id: hongKong, name: "香港优选", kind: .urlTest, tint: .orange)
                strategy.pool?.regions = [.hongKong]
                strategy.testURL = testURL
                profile.strategies.append(strategy)
                if let ai = profile.routes.firstIndex(where: { $0.id == "ai" }) {
                    profile.routes[ai].target = .strategy(hongKong)
                }
            }
        } catch {
            print("could not prepare the profile: \(error)")
            exit(1)
        }

        manager.connect()
        await check("a build without a core says so", within: .seconds(5)) {
            manager.status == .failed(.coreMissing)
        }
        guard let official = try? Data(contentsOf: URL(filePath: archive)) else {
            print("no archive at \(archive)")
            exit(1)
        }
        publish(version, archive: official, in: www, base: base)
        manager.checkForCoreUpdate()
        await check("the feed offers the pinned release", within: .seconds(10)) {
            offered(manager) == version
        }
        manager.installCoreUpdate()
        await check("which installs and connects, status \(manager.status)", within: .seconds(60)) {
            manager.isRunning
        }
        guard manager.isRunning else { exit(1) }
        expect(
            manager.activeCore?.isBundled == false && manager.activeCore?.tag == version
                && FileManager.default.isExecutableFile(
                    atPath: releases.appending(path: "\(version)/mihomo").path),
            "on the verified download")
        expect(store.wantsConnection, "the intent to stay connected is saved")
        let logs = Mutex<[String]>([])
        let api = ProxyAPIService.unixSocket(at: URL(filePath: work).appending(path: "run/core.sock").path)
        let logTask = Task.detached {
            for try await line in api.lines(.get("/logs?level=info")) {
                let text = String(bytes: line, encoding: .utf8) ?? ""
                logs.withLock { $0.append(text) }
            }
        }
        defer { logTask.cancel() }

        await check("every node loads", within: .seconds(10)) { manager.snapshot?.nodes.count == 6 }
        let snapshot = manager.snapshot
        let tun = try? ProxyConfigBuilder.build(
            store.profile,
            environment: ProxyBuildEnvironment(
                mode: .tun, subscriptionURLs: store.subscriptionURLs(), ruleCatalogBase: base + "/geo")
        ).document.encoded()
        var tunAccepted = false
        if let tun {
            tunAccepted = (try? await ProxyCoreRunner.check(tun, core: URL(filePath: pinnedCore))) != nil
        }
        expect(tunAccepted, "the core accepts the TUN config the helper will run")
        expect(snapshot?.nodes["B·HK 02"]?.source == b.id, "renamed and prefixed nodes keep their source")
        expect(snapshot?.nodes["剩余流量：100 GB"] == nil, "information nodes are excluded")
        expect(snapshot?.strategies[hongKong]?.options == ["🇭🇰 香港 01", "B·HK 02"], "a region strategy")
        expect(snapshot?.sources[a.id]?.usage?.total == 1_073_741_824, "subscription usage")
        expect(snapshot?.routes["ai"] == "香港优选", "the AI route starts on its strategy")
        expect(manager.coreVersion == version, "the downloaded core answers")
        let ruleSets = store.profile.routes.filter(\.isEnabled).flatMap(\.ruleSets).map(\.name)
        expect(
            !ruleSets.isEmpty && ruleSets.allSatisfy { (snapshot?.ruleSets[$0]?.rules ?? 0) > 0 },
            "every route's rule set downloads")
        let updated = await manager.updateRuleSets()
        expect(updated && manager.notice == nil, "and downloads again on request")

        let targetPort = target.split(separator: ":").last.map(String.init) ?? ""
        // Not openai.com: HSTS preload makes URLSession switch to HTTPS before the proxy sees it.
        let ai = await fetch("http://ai.test:\(targetPort)/ai", port: mixed)
        expect(ai == "ok ai.test:\(targetPort) /ai\n", "AI traffic flows through the Hong Kong strategy")
        let china = await fetch("http://baidu.com:\(targetPort)/cn", port: mixed)
        expect(china == "ok baidu.com:\(targetPort) /cn\n", "Chinese traffic flows direct")
        let logged = { (host: String, route: String) in
            logs.withLock { $0.contains { $0.contains(host) && $0.contains(route) } }
        }
        await check("the core logged AI traffic leaving through a Hong Kong node", within: .seconds(3)) {
            logged("ai.test:", "using route/ai[🇭🇰 香港 01]") || logged("ai.test:", "using route/ai[B·HK 02]")
        }
        await check("and Chinese traffic going direct", within: .seconds(3)) {
            logged("baidu.com:", "RuleSet(geosite-cn) using route/china[DIRECT]")
        }

        let pid = corePID(store)
        let reloads = { logs.withLock { $0.filter { $0.contains("Start initial configuration") }.count } }
        let reloadsBefore = reloads()
        do {
            try manager.route("ai", to: .direct)
            try manager.select("🇭🇰 香港 01", in: store.profile.strategies[0].id)
        } catch {
            expect(false, "route and select save: \(error)")
        }
        await manager.refresh()
        await check("a route switch applies", within: .seconds(5)) {
            manager.snapshot?.routes["ai"] == "DIRECT"
        }
        let primary = store.profile.strategies[0].id
        await check("a node pick applies", within: .seconds(5)) {
            manager.snapshot?.strategies[primary]?.current == "🇭🇰 香港 01"
        }
        try? await Task.sleep(for: .milliseconds(300))
        expect(reloads() == reloadsBefore && corePID(store) == pid, "neither reloads nor restarts the core")
        await manager.refresh()
        await manager.refresh()
        let groups = try? await api.proxies()
        expect(groups?["route/ai"]?.now == "DIRECT", "a later refresh keeps the route switch in the core")
        expect(
            groups?[store.profile.strategies[0].name]?.now == "🇭🇰 香港 01",
            "and keeps the node pick in the core")

        do {
            try manager.update { $0.sources[1].isEnabled = false }
        } catch {
            expect(false, "a source can be disabled: \(error)")
        }
        await check("a disabled source's nodes go", within: .seconds(10)) {
            manager.snapshot?.nodes["B·HK 02"] == nil
        }
        expect(reloads() > reloadsBefore && corePID(store) == pid, "through a reload of the running core")
        expect(manager.snapshot?.routes["ai"] == "DIRECT", "picks survive the reload")

        do {
            try manager.update { $0.strategies[hongKong.strategyIndex(in: $0)].pool?.pattern = "a++" }
        } catch {
            expect(false, "a pattern can be saved: \(error)")
        }
        await check("a pattern the core refuses is reported", within: .seconds(10)) { manager.notice != nil }
        if case .rejected(let reason) = manager.notice {
            expect(reason.contains("regexp2"), "in the core's words: \(reason)")
        } else {
            expect(false, "as a rejection, not \(String(describing: manager.notice))")
        }
        expect(manager.isRunning && corePID(store) == pid, "and the core keeps its last config")
        manager.dismissNotice()
        try? manager.update { $0.strategies[hongKong.strategyIndex(in: $0)].pool?.pattern = "" }

        let reloadsBeforeGlobal = reloads()
        manager.setMode(.global)
        var mode = await currentMode(api)
        for _ in 0..<50 where mode != "global" {
            try? await Task.sleep(for: .milliseconds(100))
            mode = await currentMode(api)
        }
        expect(mode == "global" && store.mode == .global, "global mode switches the core's mode and is saved")
        let global = try? await api.proxies()["GLOBAL"]?.now
        expect(global == store.profile.strategies[0].name, "to the default strategy, not \(global ?? "none")")
        let globalChina = await fetch("http://baidu.com:\(targetPort)/global", port: mixed)
        expect(globalChina == "ok baidu.com:\(targetPort) /global\n", "traffic still flows")
        await check("and ignores the routes", within: .seconds(3)) { logged("baidu.com:", "using GLOBAL") }
        manager.setMode(.direct)
        mode = await currentMode(api)
        for _ in 0..<50 where mode != "direct" {
            try? await Task.sleep(for: .milliseconds(100))
            mode = await currentMode(api)
        }
        expect(mode == "direct", "direct mode switches the core's mode")
        let directAI = await fetch("http://ai.test:\(targetPort)/direct", port: mixed)
        expect(directAI == "ok ai.test:\(targetPort) /direct\n", "traffic flows without a node")
        await check("and skips the routes", within: .seconds(3)) { logged("ai.test:", "using DIRECT") }
        manager.setMode(.rule)
        mode = await currentMode(api)
        for _ in 0..<50 where mode != "rule" {
            try? await Task.sleep(for: .milliseconds(100))
            mode = await currentMode(api)
        }
        expect(
            mode == "rule" && reloads() == reloadsBeforeGlobal, "rule mode restores the routes in place")

        if let destination = ProxyProbe.Destination("ai.test:\(targetPort)") {
            let outcome = try? await ProxyProbeRunner.run(destination, api: api, port: mixed)
            if case .matched(let rule, let payload, let exit) = outcome {
                expect(rule == "RuleSet" && payload == "geosite-category-ai-!cn", "a test finds the AI route")
                let pick = manager.snapshot?.routes["ai"]
                expect(pick == "DIRECT" ? exit == "DIRECT" : exit != "DIRECT", "and where it went out: \(exit)")
            } else {
                expect(false, "a test reads the core's log, not \(String(describing: outcome))")
            }
        }
        if let destination = ProxyProbe.Destination("baidu.com:\(targetPort)") {
            let outcome = try? await ProxyProbeRunner.run(destination, api: api, port: mixed)
            expect(
                outcome == .matched(rule: "RuleSet", payload: "geosite-cn", exit: "DIRECT"),
                "a mainland site goes direct: \(String(describing: outcome))")
        }
        let open = try? await api.connections()
        expect(open != nil, "the open connections decode")
        var sample: ProxyAPI.Traffic?
        do {
            for try await traffic in api.traffic() {
                sample = traffic
                break
            }
        } catch {}
        expect(sample != nil, "the traffic stream reports a second")

        let nodesFile = URL(filePath: nodes)
        if let text = try? String(contentsOf: nodesFile, encoding: .utf8),
            let base = text.split(separator: "\n").first?.split(separator: "#").first,
            let name = "自建 02".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        {
            try? (text + base + "#" + name + "\n").write(to: nodesFile, atomically: true, encoding: .utf8)
        }
        let reloadsBeforeFile = reloads()
        manager.reloadFile(at: nodesFile)
        await check("an edited node file is read again", within: .seconds(10)) {
            manager.snapshot?.nodes["自建 02"] != nil
        }
        expect(reloads() == reloadsBeforeFile && corePID(store) == pid, "without reloading the core")
        let readable = (try? String(contentsOf: nodesFile, encoding: .utf8)) ?? ""
        try? "not a node\n".write(to: nodesFile, atomically: true, encoding: .utf8)
        manager.reloadFile(at: nodesFile)
        await check("a node file the core cannot read is reported", within: .seconds(10)) {
            manager.notice != nil
        }
        if case .sourceUpdate(c.id, let reason?) = manager.notice {
            expect(
                !reason.isEmpty && manager.snapshot?.nodes["自建 02"] != nil,
                "with why, keeping its nodes: \(reason)")
        } else {
            expect(false, "as that source's failure, not \(String(describing: manager.notice))")
        }
        manager.dismissNotice()
        try? readable.write(to: nodesFile, atomically: true, encoding: .utf8)
        manager.reloadFile(at: nodesFile)

        let cached = store.coreDirectory.appending(path: a.providerPath)
        let wasCached = FileManager.default.fileExists(atPath: cached.path)
        manager.discardCachedNodes(of: a)
        expect(
            wasCached && !FileManager.default.fileExists(atPath: cached.path),
            "a changed link's cached nodes are discarded")

        if let pid, let number = pid_t(pid) {
            kill(number, SIGKILL)
        }
        await check("a killed core is noticed", within: .seconds(5)) {
            if case .failed(.coreExited) = manager.status { return true }
            return manager.isRunning && corePID(store) != pid
        }
        await check("and restarted, status \(manager.status)", within: .seconds(15)) {
            manager.isRunning && corePID(store) != pid && corePID(store) != nil
        }
        await check("with its picks restored", within: .seconds(10)) {
            manager.snapshot?.routes["ai"] == "DIRECT"
        }

        manager.dismissNotice()
        let runningPID = corePID(store)
        publish("v99.0.0", archive: brokenCore("v99.0.0"), in: www, base: base)
        manager.checkForCoreUpdate()
        await check("a newer release is offered", within: .seconds(10)) { offered(manager) == "v99.0.0" }
        manager.installCoreUpdate()
        await check("one that cannot start is reported", within: .seconds(30)) {
            manager.notice == .coreDidNotStart(tag: "v99.0.0")
        }
        await check("and the previous core runs again, status \(manager.status)", within: .seconds(20)) {
            manager.isRunning && manager.activeCore?.tag == version
        }
        expect(
            !FileManager.default.fileExists(atPath: releases.appending(path: "v99.0.0").path)
                && FileManager.default.fileExists(atPath: releases.appending(path: version).path),
            "with the broken release removed and the previous one kept")
        await check("its picks restored", within: .seconds(10)) { manager.snapshot?.routes["ai"] == "DIRECT" }

        manager.dismissNotice()
        let rolledBackPID = corePID(store)
        expect(rolledBackPID != runningPID, "the core was restarted for the attempt")
        publish(
            "v99.0.1", archive: brokenCore("v99.0.1"), in: www, base: base,
            digest: String(repeating: "0", count: 64))
        manager.checkForCoreUpdate()
        await check("another release is offered", within: .seconds(10)) { offered(manager) == "v99.0.1" }
        manager.installCoreUpdate()
        await check("a download that fails its digest is refused", within: .seconds(30)) {
            manager.notice == .coreUpdate(.checksumMismatch)
        }
        expect(
            manager.isRunning && corePID(store) == rolledBackPID && offered(manager) == "v99.0.1",
            "leaving the running core alone and the release on offer")

        manager.dismissNotice()
        let helpers = Bundle.main.bundleURL.appending(path: "Contents/Helpers/mihomo")
        try? FileManager.default.copyItem(at: URL(filePath: pinnedCore), to: helpers)
        expect(manager.hasBundledCore, "the app now carries a core")
        manager.restoreBundledCore()
        await check("restoring the bundled core restarts on it", within: .seconds(20)) {
            manager.isRunning && manager.activeCore?.isBundled == true
        }
        expect(
            manager.coreVersion == version && !FileManager.default.fileExists(atPath: releases.path),
            "and removes every download")

        let restartedPID = corePID(store).flatMap { pid_t($0) }
        manager.disconnect()
        await check("disconnects", within: .seconds(10)) { manager.status == .off }
        expect(restartedPID.map { kill($0, 0) != 0 } ?? false, "and the core process is gone")
        expect(!store.wantsConnection && corePID(store) == nil, "leaving nothing to restore at login")

        try? store.update { $0.general.connectsAtLogin = false }
        try? store.setWantsConnection(true)
        let relaunched = ProxyManager(
            store: store, runtimeDirectory: URL(filePath: work).appending(path: "run"),
            ruleCatalogBase: base + "/geo", coreFeed: URL(string: base + "/release.json")!)
        relaunched.start()
        await check("a launch that does not connect drops the old intent", within: .seconds(5)) {
            !store.wantsConnection && relaunched.status == .off
        }

        print("\(passes) passed, \(failures) failed")
        exit(failures > 0 ? 1 : 0)
    }
}

extension UUID {
    fileprivate func strategyIndex(in profile: ProxyProfile) -> Int {
        profile.strategies.firstIndex { $0.id == self } ?? 0
    }
}
