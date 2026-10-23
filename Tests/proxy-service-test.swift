import CryptoKit
import Foundation
import Synchronization

/// A controller stand-in on a Unix socket: canned answers, and a record of what arrived.
final class FakeController: Sendable {
    struct Received: Equatable, Sendable {
        var method: String
        var target: String
        var body: String
    }

    let path: String
    private let listener: Int32
    private let received = Mutex<[Received]>([])
    private let closedEarly = Mutex(0)

    init() {
        path = FileManager.default.temporaryDirectory.path + "/tc-proxy-\(getpid()).sock"
        unlink(path)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        listen(listener, 16)
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                Thread.detachNewThread { self.serve(client) }
            }
        }
    }

    var requests: [Received] { received.withLock { $0 } }
    var connectionsClosedByClient: Int { closedEarly.withLock { $0 } }

    func stop() {
        shutdown(listener, SHUT_RDWR)
        close(listener)
        unlink(path)
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.firstRange(of: Array("\r\n\r\n".utf8)) == nil {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            data += buffer[..<count]
        }
        guard let end = data.firstRange(of: Array("\r\n\r\n".utf8)),
            let head = String(bytes: data[..<end.lowerBound], encoding: .utf8)
        else { return }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        let length =
            lines.compactMap { line -> Int? in
                line.lowercased().hasPrefix("content-length:")
                    ? Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) : nil
            }.first ?? 0
        var body = Array(data[end.upperBound...])
        while body.count < length {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            body += buffer[..<count]
        }
        let request = Received(
            method: String(parts[0]), target: String(parts[1]),
            body: String(bytes: body, encoding: .utf8) ?? "")
        received.withLock { $0.append(request) }
        respond(to: request, on: client)
    }

    private func respond(to request: Received, on client: Int32) {
        func send(_ text: String) {
            _ = text.utf8CString.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count - 1) }
        }
        func json(_ status: String, _ body: String) {
            send(
                "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            )
        }
        func waitForClose() {
            var byte: UInt8 = 0
            if read(client, &byte, 1) <= 0 { closedEarly.withLock { $0 += 1 } }
        }
        switch (request.method, request.target.split(separator: "?").first.map(String.init) ?? "") {
        case ("GET", "/version"): json("200 OK", #"{"meta":true,"version":"v1.19.32"}"#)
        case ("PUT", "/proxies/route%2Fai"), ("PUT", "/configs"): send("HTTP/1.1 204 No Content\r\n\r\n")
        case ("PUT", "/proxies/missing"): json("404 Not Found", #"{"message":"Resource not found"}"#)
        case ("GET", "/group/%E9%BB%98%E8%AE%A4/delay"): json("200 OK", #"{"a":12,"b":40}"#)
        case ("GET", "/proxies"): json("200 OK", "{not json")
        case ("PUT", "/providers/rules/geosite-cn"): send("HTTP/1.1 204 No Content\r\n\r\n")
        case ("PUT", "/providers/rules/geoip-cn"):
            json("503 Service Unavailable", #"{"message":"download failed"}"#)
        case ("GET", "/logs"):
            send("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
            for (type, payload) in [("warning", "a node timed out"), ("error", "a rule set failed")] {
                let line = #"{"type":"\#(type)","payload":"\#(payload)"}"# + "\n"
                send(String(line.utf8.count, radix: 16) + "\r\n" + line + "\r\n")
            }
            waitForClose()
        case ("GET", "/traffic"):
            send("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
            for up in 1...3 {
                let line = #"{"up":\#(up),"down":0}"# + "\n"
                send(String(line.utf8.count, radix: 16) + "\r\n" + line + "\r\n")
                usleep(20_000)
            }
            waitForClose()
        case ("GET", "/hang"): waitForClose()
        default: json("404 Not Found", #"{"message":"Resource not found"}"#)
        }
    }
}

@main
@MainActor
struct ProxyServiceTests {
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

    static func failure(of operation: () async throws -> Void) async -> (any Error)? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - API over a socket

    static func testRequests(_ server: FakeController, _ api: ProxyAPIService) async {
        let version = try? await api.version()
        expect(version == "v1.19.32", "a sized JSON answer")

        let selected = await failure { try await api.select("香港优选", in: "route/ai") }
        expect(selected == nil, "a 204 is a success")
        let select = server.requests.last
        expect(
            select?.method == "PUT" && select?.target == "/proxies/route%2Fai",
            "the group name stays one segment")
        expect(select?.body == #"{"name":"香港优选"}"#, "the option as JSON")

        let missing =
            await failure { try await api.select("DIRECT", in: "missing") } as? ProxyAPIService.Failure
        expect(
            missing == .rejected(status: 404, message: "Resource not found"),
            "a rejection carries the message")

        let reloaded = await failure { try await api.reload(Data(#"{"mode":"rule"}"#.utf8)) }
        expect(reloaded == nil, "a reload succeeds")
        let reload = server.requests.last
        expect(reload?.target == "/configs?force=true", "a reload is forced, so ports and LAN changes apply")
        let payload = reload.flatMap {
            try? JSONSerialization.jsonObject(with: Data($0.body.utf8)) as? [String: String]
        }
        expect(payload == ["path": "", "payload": #"{"mode":"rule"}"#], "the config travels as a payload")

        let delays = try? await api.testGroup("默认", url: "https://x.test/204", timeout: .seconds(3))
        expect(delays == ["a": 12, "b": 40], "a group's delays")
        expect(
            server.requests.last?.target
                == "/group/%E9%BB%98%E8%AE%A4/delay?url=https%3A%2F%2Fx.test%2F204&timeout=3000",
            "the test URL and timeout are query values")

        let malformed = await failure { _ = try await api.proxies() } as? ProxyAPIService.Failure
        expect(malformed == .malformed, "an undecodable answer is malformed")

        let updated = await failure { try await api.updateRuleProvider("geosite-cn") }
        expect(updated == nil, "a rule set update succeeds")
        let update = server.requests.last
        expect(
            update?.method == "PUT" && update?.target == "/providers/rules/geosite-cn",
            "a rule set is updated by name")
        let refused = await failure { try await api.updateRuleProvider("geoip-cn") } as? ProxyAPIService.Failure
        expect(
            refused == .rejected(status: 503, message: "download failed"),
            "a failed rule set update carries the core's reason")
    }

    static func testStreams(_ server: FakeController, _ api: ProxyAPIService) async {
        let closedBefore = server.connectionsClosedByClient
        var records: [Int64] = []
        do {
            for try await traffic in api.traffic() {
                records.append(traffic.up)
                if records.count == 3 { break }
            }
        } catch {
            expect(false, "the stream failed: \(error)")
        }
        expect(records == [1, 2, 3], "chunked records arrive one by one")
        for _ in 0..<50 where server.connectionsClosedByClient == closedBefore {
            try? await Task.sleep(for: .milliseconds(20))
        }
        expect(server.connectionsClosedByClient == closedBefore + 1, "leaving the loop closes the connection")

        var logs: [ProxyAPI.LogRecord] = []
        do {
            for try await record in api.logs(level: "warning") {
                logs.append(record)
                if logs.count == 2 { break }
            }
        } catch {
            expect(false, "the log stream failed: \(error)")
        }
        expect(
            logs == [
                ProxyAPI.LogRecord(type: "warning", payload: "a node timed out"),
                ProxyAPI.LogRecord(type: "error", payload: "a rule set failed")
            ],
            "log records arrive with their level")
        expect(
            server.requests.last { $0.target.hasPrefix("/logs") }?.target == "/logs?level=warning",
            "the log stream asks for its level")
    }

    static func testDeadlines(_ server: FakeController, _ api: ProxyAPIService) async {
        let clock = ContinuousClock()
        var started = clock.now
        let timedOut = await failure { _ = try await api.send(.get("/hang"), timeout: .milliseconds(300)) }
        expect(timedOut as? ProxyAPIService.Failure == .timedOut, "a silent core times out")
        expect(clock.now - started < .seconds(2), "within its deadline")

        let closedBefore = server.connectionsClosedByClient
        started = clock.now
        let task = Task { try await api.send(.get("/hang"), timeout: .seconds(30)) }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let cancelled = await failure { _ = try await task.value }
        expect(cancelled is CancellationError, "cancelling a call ends it as cancelled")
        expect(clock.now - started < .seconds(2), "at once, though the read was blocked")
        for _ in 0..<50 where server.connectionsClosedByClient == closedBefore {
            try? await Task.sleep(for: .milliseconds(20))
        }
        expect(server.connectionsClosedByClient > closedBefore, "and its connection is closed")

        let nowhere = ProxyAPIService.unixSocket(at: server.path + ".missing")
        let unreachable = await failure { _ = try await nowhere.version() } as? ProxyAPIService.Failure
        expect(unreachable == .unreachable, "a missing socket is unreachable")
        let long = "/tmp/" + String(repeating: "a", count: 120)
        do {
            _ = try ProxySocket.connect(path: long)
            expect(false, "an overlong socket path is refused")
        } catch {
            expect(
                error == .unreachable(ENAMETOOLONG), "an overlong socket path is refused before connecting")
        }
    }

    // MARK: - Store

    static func testStore() {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "tc-proxy-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = KeychainSecretStore(
            scope: "proxy-test-\(UUID().uuidString)", bundleIdentifier: "com.tinycast.harness")

        let store = ProxyStore(directory: directory, secrets: secrets)
        expect(
            !store.recoveredDamagedFile && !store.wantsConnection,
            "a first run starts from the starter profile")
        expect(
            store.profile.strategies.count == 2 && store.profile.followsRecommendedRoutes && store.mode == .rule,
            "the starter, by the rules")
        let source = ProxySource.subscription(id: UUID(), name: "机场")
        do {
            try store.update { $0.sources = [source] }
            try store.setWantsConnection(true)
            try store.setMode(.global)
            try store.setSubscriptionURL("https://sub.test/token", for: source.id)
        } catch {
            expect(false, "the store saves: \(error)")
        }
        let reopened = ProxyStore(directory: directory, secrets: secrets)
        expect(
            reopened.profile == store.profile && reopened.wantsConnection, "the profile and intent survive")
        expect(reopened.mode == .global, "the mode survives a restart")
        expect(
            reopened.subscriptionURLs() == [source.id: "https://sub.test/token"],
            "links come from the keychain")
        let saved =
            (try? String(contentsOf: directory.appending(path: "profile.json"), encoding: .utf8)) ?? ""
        expect(saved.contains("机场") && !saved.contains("sub.test"), "the file never holds a link")
        try? store.update { $0.sources[0].isEnabled = false }
        expect(store.subscriptionURLs().isEmpty, "a disabled source's link is not read")
        try? store.removeSubscriptionURL(for: source.id)
        expect(store.subscriptionURL(for: source.id) == nil, "a removed link is gone")

        let file = directory.appending(path: "profile.json")
        if var document = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] {
            document["mode"] = nil
            try? JSONSerialization.data(withJSONObject: document).write(to: file)
        }
        let older = ProxyStore(directory: directory, secrets: secrets)
        expect(
            !older.recoveredDamagedFile && older.mode == .rule && older.profile == store.profile,
            "a file from before modes opens in rule mode")

        try? Data("{broken".utf8).write(to: directory.appending(path: "profile.json"))
        let recovered = ProxyStore(directory: directory, secrets: secrets)
        expect(
            recovered.recoveredDamagedFile && recovered.profile.sources.isEmpty, "a damaged file falls back")
        expect(
            FileManager.default.fileExists(atPath: directory.appending(path: "profile.json.damaged").path),
            "and is kept aside")
    }

    // MARK: - Core installs

    static let machine = ProxyCore.Identity.expected(tag: "", architecture: .current).architecture

    /// A shell script answering `-v` as `tag` and `-t` with `checkStatus`, the way the core does.
    static func fakeCore(_ tag: String, architecture: String = machine, checkStatus: Int = 0) -> Data {
        Data(
            """
            #!/bin/sh
            case "$1" in
                -v) echo "Mihomo Meta \(tag) darwin \(architecture) with go1.0 fake"; exit 0 ;;
                -t) [ \(checkStatus) = 0 ] || echo 'time="x" level=error msg="bad config"'; exit \(checkStatus) ;;
            esac
            exit 3
            """.utf8)
    }

    static func release(_ tag: String, archive: Data) -> ProxyCoreRelease {
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        return ProxyCoreRelease(
            version: AppVersion(tag)!, tag: tag, assetURL: URL(filePath: "/\(tag).gz"),
            assetSize: Int64(archive.count), sha256: digest)
    }

    static func install(
        _ binary: Data, as tag: String, into releases: URL, config: Data? = Data("{}".utf8),
        archive: Data? = nil, digestOf other: Data? = nil
    ) async -> Result<ProxyCore, ProxyCoreUpdateFailure> {
        let archive = archive ?? ((try? Zlib.gzip(binary)) ?? Data())
        let release = release(tag, archive: other ?? archive)
        do {
            let installed = try await ProxyCoreInstaller.install(
                archive, release: release, architecture: .current, into: releases, checking: config)
            let digest = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
            expect(installed.sha256 == digest, "the digest handed to the helper is the binary's own")
            return .success(installed.core)
        } catch let failure as ProxyCoreUpdateFailure {
            return .failure(failure)
        } catch {
            return .failure(.storage("\(error)"))
        }
    }

    static func testInstaller() async {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: "tc-proxy-cores-\(UUID().uuidString)")
        let releases = root.appending(path: "Releases")
        defer { try? manager.removeItem(at: root) }
        func exists(_ path: String) -> Bool {
            manager.fileExists(atPath: releases.appending(path: path).path)
        }

        let installed = await install(fakeCore("v9.9.9"), as: "v9.9.9", into: releases)
        let core = try? installed.get()
        expect(
            core?.version == AppVersion("9.9.9") && core?.isBundled == false
                && core?.executable == releases.appending(path: "v9.9.9/mihomo"),
            "a verified release lands under its tag: \(installed)")
        expect(
            manager.isExecutableFile(atPath: releases.appending(path: "v9.9.9/mihomo").path)
                && !exists(".staging"),
            "executable, with nothing left in staging")
        expect(ProxyCoreInstaller.installed(in: releases).map(\.tag) == ["v9.9.9"], "it is listed")
        let alone = await ProxyCoreInstaller.resolve(bundled: nil, releases: releases)
        expect(
            alone.chosen?.tag == "v9.9.9" && alone.retired.isEmpty, "a build without a core runs the download"
        )

        let rejected = await install(fakeCore("v9.9.10", checkStatus: 1), as: "v9.9.10", into: releases)
        expect(rejected == .failure(.rejected("bad config")), "a core refusing the config: \(rejected)")
        expect(!exists("v9.9.10") && !exists(".staging"), "is not installed")
        let unchecked = await install(
            fakeCore("v9.9.10", checkStatus: 1), as: "v9.9.10", into: releases, config: nil)
        expect((try? unchecked.get())?.tag == "v9.9.10", "with no config to check it installs")
        try? manager.removeItem(at: releases.appending(path: "v9.9.10"))

        let impostor = await install(fakeCore("v9.9.8"), as: "v9.9.11", into: releases)
        expect(impostor == .failure(.wrongIdentity("v9.9.8 \(machine)")), "a binary naming another version")
        let foreign = machine == "arm64" ? "amd64" : "arm64"
        let wrongMachine = await install(
            fakeCore("v9.9.11", architecture: foreign), as: "v9.9.11", into: releases)
        expect(wrongMachine == .failure(.wrongIdentity("v9.9.11 \(foreign)")), "a build for another Mac")
        let garbage = await install(Data(repeating: 0xcf, count: 64), as: "v9.9.11", into: releases)
        if case .failure(.wrongIdentity) = garbage {
        } else {
            expect(false, "a binary that cannot run: \(garbage)")
        }
        expect(!exists("v9.9.11"), "none of them is installed")

        let tampered = await install(
            fakeCore("v9.9.12"), as: "v9.9.12", into: releases, digestOf: Data("x".utf8))
        expect(tampered == .failure(.checksumMismatch) && !exists("v9.9.12"), "a mismatched digest")
        let raw = fakeCore("v9.9.12")
        let notGzip = await install(raw, as: "v9.9.12", into: releases, archive: raw)
        expect(notGzip == .failure(.damaged), "an archive that is not gzip")

        try? manager.createDirectory(
            at: releases.appending(path: "latest"), withIntermediateDirectories: true)
        try? manager.createDirectory(
            at: releases.appending(path: "v9.9.13"), withIntermediateDirectories: true)
        try? Data().write(to: releases.appending(path: "latest/mihomo"))
        expect(
            ProxyCoreInstaller.installed(in: releases).map(\.tag) == ["v9.9.9"],
            "odd directories are never run")

        let bundled = root.appending(path: "bundled-mihomo")
        try? fakeCore("v9.9.9").write(to: bundled)
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
        let tie = await ProxyCoreInstaller.resolve(bundled: bundled, releases: releases)
        expect(
            tie.chosen?.isBundled == true && tie.chosen?.version == AppVersion("9.9.9")
                && tie.retired.map(\.tag) == ["v9.9.9"],
            "a tie goes to the bundled core, retiring the download")
        expect(exists("v9.9.9"), "though nothing is removed before the chosen core starts")
        await ProxyCoreInstaller.remove(tie.retired + [tie.chosen].compactMap { $0 })
        expect(!exists("v9.9.9") && manager.fileExists(atPath: bundled.path), "and never the bundled core")

        _ = await install(fakeCore("v9.9.5"), as: "v9.9.5", into: releases)
        _ = await install(fakeCore("v9.9.20"), as: "v9.9.20", into: releases)
        let newest = await ProxyCoreInstaller.resolve(bundled: bundled, releases: releases)
        expect(
            newest.chosen?.tag == "v9.9.20" && newest.chosen?.isBundled == false
                && newest.retired.map(\.tag) == ["v9.9.5"],
            "a newer download beats the bundled core and retires older downloads")
    }

    static func main() async {
        let server = FakeController()
        defer { server.stop() }
        let api = ProxyAPIService.unixSocket(at: server.path)
        await testRequests(server, api)
        await testStreams(server, api)
        await testDeadlines(server, api)
        testStore()
        await testInstaller()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
