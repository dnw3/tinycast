import CryptoKit
import Foundation
import Synchronization

/// The core the supervisor runs here: this binary again, answering like mihomo on its socket.
enum FakeCore {
    static let tag = "v9.9.9"
    static let machine = ProxyCore.Identity.expected(tag: "", architecture: .current).architecture

    /// Nothing when this process is the harness itself; a core never returns.
    static func runIfAsked() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["-v"] {
            print("Mihomo Meta \(tag) darwin \(machine) with go1.0 fake")
            exit(0)
        }
        guard let socketIndex = arguments.firstIndex(of: "-ext-ctl-unix"), socketIndex + 1 < arguments.count,
            let directoryIndex = arguments.firstIndex(of: "-d"), directoryIndex + 1 < arguments.count
        else { return }
        serve(socket: arguments[socketIndex + 1], directory: arguments[directoryIndex + 1])
    }

    /// `fake-core.json` in the core's directory: `rejectReload` refuses the next config change.
    private static func behaviour(in directory: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: directory + "/fake-core.json") else {
            return [:]
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func serve(socket path: String, directory: String) -> Never {
        unlink(path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 16) == 0 else { exit(9) }
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            answer(client, directory: directory)
            close(client)
        }
    }

    private static func answer(_ client: Int32, directory: String) {
        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let separator = Array("\r\n\r\n".utf8)
        while data.firstRange(of: separator) == nil {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            data += buffer[..<count]
        }
        guard let end = data.firstRange(of: separator),
            let head = String(bytes: data[..<end.lowerBound], encoding: .utf8)
        else { return }
        let lines = head.components(separatedBy: "\r\n")
        let request = lines[0].split(separator: " ")
        guard request.count >= 2 else { return }
        let length =
            lines.dropFirst().compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }.first ?? 0
        var body = Array(data[end.upperBound...])
        while body.count < length {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            body += buffer[..<count]
        }
        let method = String(request[0])
        let target = String(request[1])
        let log = directory + "/fake-core.requests"
        if let handle = FileHandle(forWritingAtPath: log)
            ?? {
                FileManager.default.createFile(atPath: log, contents: nil)
                return FileHandle(forWritingAtPath: log)
            }()
        {
            handle.seekToEndOfFile()
            handle.write(Data("\(method) \(target)\n".utf8))
            try? handle.close()
        }
        func send(_ status: String, _ json: String) {
            let response =
                "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n"
                + "Connection: close\r\n\r\n" + json
            _ = response.withCString { write(client, $0, strlen($0)) }
        }
        switch (method, target) {
        case ("GET", "/version"):
            send("200 OK", "{\"version\":\"\(tag)\"}")
        case ("PUT", "/configs?force=true"):
            if let reason = behaviour(in: directory)["rejectReload"] as? String {
                send("400 Bad Request", "{\"message\":\"\(reason)\"}")
            } else {
                send("204 No Content", "")
            }
        default:
            send("404 Not Found", "{\"message\":\"not found\"}")
        }
    }
}

/// The system's DNS, as the placeholder sees it, held in memory.
final class FakeDNS: ProxySystemDNS, Sendable {
    private struct State {
        var primary: String? = "SVC-A"
        var servers: [String: [String]?] = ["SVC-A": ["192.168.0.1"], "SVC-B": nil]
        var writes = 0
    }

    private let state = Mutex(State())

    var primary: String? {
        get { state.withLock { $0.primary } }
        set { state.withLock { $0.primary = newValue } }
    }

    var writes: Int { state.withLock { $0.writes } }

    func set(_ servers: [String]?, for service: String) {
        state.withLock { $0.servers[service] = .some(servers) }
    }

    func current(_ service: String) -> [String]? {
        state.withLock { $0.servers[service].flatMap { $0 } }
    }

    func primaryServiceID() -> String? { primary }

    func servers(of serviceID: String) throws -> [String]? {
        try state.withLock { state in
            guard let servers = state.servers[serviceID] else { throw CocoaError(.fileNoSuchFile) }
            return servers
        }
    }

    func setServers(_ servers: [String]?, of serviceID: String) throws {
        state.withLock { state in
            state.servers[serviceID] = .some(servers)
            state.writes += 1
        }
    }
}

/// Status pushes as they arrive from the helper.
final class StatusLog: Sendable {
    private let entries = Mutex<[ProxyHelperStatus]>([])

    func append(_ status: ProxyHelperStatus) { entries.withLock { $0.append(status) } }
    var all: [ProxyHelperStatus] { entries.withLock { $0 } }
}

/// An anonymous listener's endpoint is an immutable token, safe to hand to the connector.
final class Endpoint: @unchecked Sendable {
    let value: NSXPCListenerEndpoint

    init(_ value: NSXPCListenerEndpoint) {
        self.value = value
    }
}

@main
@MainActor
struct ProxyHelperTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    static func failure(of operation: () async throws -> Void) async -> (any Error)? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static var executablePath: String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        _ = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// This binary's ad-hoc signing identifier, the one requirement it can satisfy.
    static var selfRequirement: String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        SecCodeCopySelf([], &code)
        if let code { SecCodeCopyStaticCode(code, [], &staticCode) }
        if let staticCode {
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        }
        let identifier = (information as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String ?? ""
        return "identifier \"\(identifier)\""
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        guard let exit = try? process.runObservingExit() else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    // MARK: - Model

    static func testLayout() {
        let layout = ProxyHelperLayout(appIdentifier: "com.tinycast.app.dev")
        expect(layout?.label == "com.tinycast.app.dev.proxy-helper", "the label names the channel")
        expect(
            layout?.executable == "/Library/PrivilegedHelperTools/com.tinycast.app.dev.proxy-helper"
                && layout?.launchdPlist == "/Library/LaunchDaemons/com.tinycast.app.dev.proxy-helper.plist"
                && layout?.root == "/Library/Application Support/Tinycast/com.tinycast.app.dev.proxy-helper",
            "installed paths: \(String(describing: layout))")
        expect(
            (layout?.socket.utf8.count ?? 200) < MemoryLayout.size(ofValue: sockaddr_un().sun_path),
            "the controller socket fits sockaddr_un")
        for bad in [
            "", "com.tinycast app", "com/evil", "a..b", ".a", "a.", "com.\"x\"", "com.tinycast'app",
            "com.tinycast.app;rm", String(repeating: "a", count: 201), "com.tinycast.äpp"
        ] {
            expect(ProxyHelperLayout(appIdentifier: bad) == nil, "refuses identifier \(bad)")
        }
        let recovered = ProxyHelperLayout(
            executablePath: "/Library/PrivilegedHelperTools/com.tinycast.app.proxy-helper")
        expect(recovered?.appIdentifier == "com.tinycast.app", "a helper finds its own channel")
        for bad in [
            "/tmp/com.tinycast.app.proxy-helper", "/Library/PrivilegedHelperTools/com.tinycast.app",
            "/Library/PrivilegedHelperTools/../PrivilegedHelperTools/com.tinycast.app.proxy-helper",
            "/Library/PrivilegedHelperTools/sub/com.tinycast.app.proxy-helper"
        ] {
            expect(ProxyHelperLayout(executablePath: bad) == nil, "no layout from \(bad)")
        }
        let job = layout?.launchdJob ?? [:]
        expect(
            job["Label"] as? String == layout?.label
                && (job["MachServices"] as? [String: Bool]) == [layout?.label ?? "": true]
                && (job["ProgramArguments"] as? [String]) == [layout?.executable ?? ""]
                && (job["KeepAlive"] as? [String: Bool]) == ["SuccessfulExit": false]
                && (job["AssociatedBundleIdentifiers"] as? [String]) == ["com.tinycast.app.dev"],
            "the launchd job: \(job)")
        expect(
            (try? PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)) != nil,
            "the job serializes as a plist")
    }

    static func testGrant() {
        let leaf = "ccc45372b9efd58a7b102df90c075657a693d170"
        let grant = ProxyHelperGrant(appIdentifier: "com.tinycast.app.dev", leafHash: leaf, uid: 501)
        expect(grant.isValid, "a signed channel's grant is valid")
        expect(
            grant.appRequirement == "identifier \"com.tinycast.app.dev\" and certificate leaf = H\"\(leaf)\"",
            "the app requirement: \(grant.appRequirement)")
        expect(
            grant.helperRequirement
                == "identifier \"com.tinycast.app.dev.proxy-helper\" and certificate leaf = H\"\(leaf)\"",
            "the helper requirement")
        expect(
            grant.coreRequirement
                == "identifier \"com.tinycast.app.dev.mihomo\" and certificate leaf = H\"\(leaf)\"",
            "the bundled core's requirement")
        for bad in [leaf.uppercased(), String(leaf.dropLast()), String(leaf.dropLast()) + "g", ""] {
            expect(
                !ProxyHelperGrant(appIdentifier: "com.tinycast.app", leafHash: bad, uid: 501).isValid,
                "refuses leaf \(bad)")
        }
        expect(
            !ProxyHelperGrant(appIdentifier: "com tinycast", leafHash: leaf, uid: 501).isValid, "and bad ids")
        let digest = String(repeating: "0123456789abcdef", count: 4)
        expect(ProxyHelperGrant.isDigest(digest), "a SHA-256 in lowercase hex")
        expect(
            !ProxyHelperGrant.isDigest(digest.uppercased()) && !ProxyHelperGrant.isDigest(leaf), "only that")
        let decoded = (try? JSONEncoder().encode(grant)).flatMap {
            try? JSONDecoder().decode(ProxyHelperGrant.self, from: $0)
        }
        expect(decoded == grant, "the grant survives its file")
    }

    static func profileConfig(mode: ProxyBuildEnvironment.Mode) -> (ProxyConfig, ProxyProfile)? {
        var profile = ProxyProfile.starter(defaultName: "默认代理", fastestName: "自动最快") { UUID() }
        let subscription = ProxySource.subscription(id: UUID(), name: "机场")
        let file = ProxySource.file(id: UUID(), name: "自建", path: "~/nodes.yaml")
        profile.sources = [subscription, file]
        let environment = ProxyBuildEnvironment(
            mode: mode, subscriptionURLs: [subscription.id: "https://example.com/sub?token=x"])
        guard let config = try? ProxyConfigBuilder.build(profile, environment: environment) else {
            return nil
        }
        return (config, profile)
    }

    static func testPolicy() {
        for good in ["src-0123abcd.yaml", "src-ffffffff.yaml"] {
            expect(ProxyHelperPolicy.isProviderFile(good), "takes \(good)")
        }
        for bad in [
            "src-0123ABCD.yaml", "src-0123abc.yaml", "../src-0123abcd.yaml", "src-0123abcd.yaml/",
            "src-0123abcd.yml", "src-0123abcg.yaml", "providers/src-0123abcd.yaml", "src-0123abcd.yaml\0",
            "config.json"
        ] {
            expect(!ProxyHelperPolicy.isProviderFile(bad), "refuses \(bad)")
        }
        for mode in [ProxyBuildEnvironment.Mode.tun, .portOnly] {
            guard let (config, _) = profileConfig(mode: mode), let data = try? config.document.encoded()
            else {
                expect(false, "the builder made a config")
                continue
            }
            let problems = ProxyHelperPolicy.problems(inConfig: data)
            expect(problems.isEmpty, "the builder's own config passes: \(problems)")
        }
        guard let (config, _) = profileConfig(mode: .tun),
            let data = try? config.document.encoded(),
            var document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            expect(false, "a config to tamper with")
            return
        }
        func problems(_ change: (inout [String: Any]) -> Void) -> [String] {
            var copy = document
            change(&copy)
            let data = (try? JSONSerialization.data(withJSONObject: copy)) ?? Data()
            return ProxyHelperPolicy.problems(inConfig: data)
        }
        for key in ["external-controller", "external-ui", "secret", "external-controller-unix", "listeners"] {
            expect(problems { $0[key] = "x" } == ["unexpected key \(key)"], "refuses \(key)")
        }
        let escaped = problems { document in
            var providers = document["proxy-providers"] as? [String: Any] ?? [:]
            providers["src-0123abcd"] = ["type": "file", "path": "../../etc/sudoers"]
            document["proxy-providers"] = providers
        }
        expect(escaped == ["proxy provider src-0123abcd has an unexpected path"], "a provider path elsewhere")
        let renamed = problems { document in
            var providers = document["proxy-providers"] as? [String: Any] ?? [:]
            providers["evil"] = ["type": "file", "path": "providers/evil.yaml"]
            document["proxy-providers"] = providers
        }
        expect(
            renamed == ["proxy provider evil has an unexpected path"], "a provider not named by the builder")
        let ruleEscape = problems { document in
            var providers = document["rule-providers"] as? [String: Any] ?? [:]
            providers["geosite-cn"] = ["type": "http", "path": "rules/../../x.mrs"]
            providers["a/b"] = ["type": "http", "path": "rules/a/b.mrs"]
            document["rule-providers"] = providers
        }
        expect(
            ruleEscape == [
                "rule provider a/b has an unexpected path", "rule provider geosite-cn has an unexpected path"
            ],
            "rule-set paths stay in rules/: \(ruleEscape)")
        document["mode"] = "rule"
        expect(
            ProxyHelperPolicy.problems(inConfig: Data("[]".utf8)) == ["config is not a JSON object"],
            "an array")
        expect(
            ProxyHelperPolicy.problems(inConfig: Data("mode: rule".utf8)) == ["config is not a JSON object"],
            "YAML")
        expect(
            ProxyHelperPolicy.problems(inConfig: Data(count: ProxyHelperPolicy.maxConfigSize + 1))
                == ["config is too large"], "and an oversized one")
    }

    static func testRecord() {
        var record = ProxyHelperRecord()
        record.wantsCore = true
        record.boot = "boot-1"
        expect(record.plan(forLaunchIn: "boot-1") == .init(resumesCore: true), "a crash in this boot resumes")
        expect(record.wantsCore, "and keeps wanting the core")
        record.dns = ProxyDNSBackup(serviceID: "SVC-A", servers: ["10.0.0.1"])
        expect(record.plan(forLaunchIn: "boot-2") == .init(restoresDNS: true), "a new boot only tidies up")
        expect(!record.wantsCore, "and forgets the core")
        var idle = ProxyHelperRecord()
        expect(idle.plan(forLaunchIn: "boot-1") == .init(), "nothing to do without a wish or a backup")
        let decoded = try? JSONDecoder().decode(ProxyHelperRecord.self, from: Data("{\"later\":1}".utf8))
        expect(decoded == ProxyHelperRecord(), "an older or newer file keeps the defaults")

        let backup = ProxyDNSBackup(serviceID: "SVC-A", servers: ["192.168.0.1"])
        expect(backup.restoration(current: ["223.5.5.5"]) == .restore(["192.168.0.1"]), "restores over ours")
        expect(backup.restoration(current: ["8.8.8.8"]) == .leave, "never over someone else's")
        expect(backup.restoration(current: nil) == .leave, "nor over a cleared list")
        expect(
            ProxyDNSBackup(serviceID: "S", servers: nil).restoration(current: ["223.5.5.5"]) == .restore(nil),
            "a service that had none gets none back")
    }

    static func testWireValues() {
        let failures: [ProxyHelperFailure] = [
            .refused("x"), .noCore, .digestMismatch, .unsigned, .notCore("v1 amd64"), .storage("disk"),
            .exited(status: 2, log: "panic"), .unreachable, .rejected("bad")
        ]
        for failure in failures {
            expect(ProxyHelperFailure(decoding: failure.encoded) == failure, "\(failure) crosses XPC")
        }
        expect(ProxyHelperFailure(decoding: Data("nonsense".utf8)) == .refused("unreadable reply"), "garbage")
        var status = ProxyHelperStatus()
        status.core = .running(since: Date(timeIntervalSince1970: 1_000), launch: 3)
        status.installed = ProxyHelperRecord.Core(sha256: String(repeating: "a", count: 64), tag: "v1.19.33")
        status.dnsProblem = "no primary network service"
        let decoded = (try? JSONEncoder().encode(status)).flatMap {
            try? JSONDecoder().decode(ProxyHelperStatus.self, from: $0)
        }
        expect(decoded == status, "the status crosses XPC")
    }

    // MARK: - Scripts

    /// The first AppleScript string literal in `script`, quotes included.
    static func firstLiteral(in script: String) -> String? {
        guard let open = script.firstIndex(of: "\"") else { return nil }
        var index = script.index(after: open)
        while index < script.endIndex {
            if script[index] == "\\" {
                index = script.index(index, offsetBy: 2, limitedBy: script.endIndex) ?? script.endIndex
                continue
            }
            if script[index] == "\"" { return String(script[open...index]) }
            index = script.index(after: index)
        }
        return nil
    }

    /// AppleScript evaluates the literal: the result is what `do shell script` would get.
    static func shellText(of script: String) -> String? {
        guard let literal = firstLiteral(in: script) else { return nil }
        let (status, output) = run("/usr/bin/osascript", ["-e", "return " + literal])
        guard status == 0 else { return nil }
        return output.hasSuffix("\n") ? String(output.dropLast()) : output
    }

    static func testScripts() {
        let layout = ProxyHelperLayout(appIdentifier: "com.tinycast.app.dev")!
        let leaf = "ccc45372b9efd58a7b102df90c075657a693d170"
        let grant = ProxyHelperGrant(appIdentifier: "com.tinycast.app.dev", leafHash: leaf, uid: 501)
        let nasty = "/tmp/a b/it's \"x\" \\ $(printf INJECTED) `printf TICKED`/Tinycast.app/Helper"
        let quoted = ProxyHelperScript.quoted(nasty)
        let (printed, echoed) = run("/bin/sh", ["-c", "printf %s " + quoted])
        expect(printed == 0 && echoed == nasty, "a quoted word reaches the shell unchanged: \(echoed)")

        guard
            let install = ProxyHelperScript.install(
                bundledHelper: nasty, layout: layout, grant: grant, prompt: "Tinycast \"wants\" it")
        else {
            expect(false, "an install script for a valid grant")
            return
        }
        expect(
            install.hasPrefix("do shell script \"")
                && install.hasSuffix(
                    "\" with prompt \"Tinycast \\\"wants\\\" it\" with administrator privileges"),
            "an administrator script with its prompt")
        let shell = shellText(of: install)
        expect(shell != nil, "AppleScript reads the install literal")
        if let shell {
            expect(run("/bin/sh", ["-n", "-c", shell]).status == 0, "the install shell parses")
            expect(shell.contains("/bin/cp -X \(quoted) \"$copy\""), "it copies from the bundle, quoted")
            expect(
                shell.contains(
                    "/usr/bin/codesign --verify --strict -R '=\(grant.helperRequirement)' \"$copy\""),
                "root checks the copy against Tinycast's signer before running it")
            let verify = shell.range(of: "codesign")!.lowerBound
            let move = shell.range(of: "/bin/mv -f")!.lowerBound
            let runs = shell.range(of: "--install 501")!.lowerBound
            expect(verify < move && move < runs, "verify, then move into place, then run")
            expect(shell.hasPrefix("set -e\n"), "any failing step stops the install")
            expect(
                shell.contains("/bin/launchctl bootstrap system '\(layout.launchdPlist)'"),
                "and loads the job")
        }
        let wrongChannel = ProxyHelperGrant(appIdentifier: "com.tinycast.app", leafHash: leaf, uid: 501)
        expect(
            ProxyHelperScript.install(bundledHelper: "/x", layout: layout, grant: wrongChannel, prompt: "")
                == nil,
            "no script for another channel's grant")
        let unsigned = ProxyHelperGrant(appIdentifier: "com.tinycast.app.dev", leafHash: "", uid: 501)
        expect(
            ProxyHelperScript.install(bundledHelper: "/x", layout: layout, grant: unsigned, prompt: "")
                == nil,
            "nor for a grant that pins nothing")

        let uninstall = ProxyHelperScript.uninstall(layout: layout, prompt: "Remove")
        if let shell = shellText(of: uninstall) {
            expect(run("/bin/sh", ["-n", "-c", shell]).status == 0, "the uninstall shell parses")
            let bootout = shell.range(of: "bootout")!.lowerBound
            let restore = shell.range(of: "--restore-dns")!.lowerBound
            let remove = shell.range(of: "/bin/rm -rf")!.lowerBound
            expect(bootout < restore && restore < remove, "stop, put DNS back, then delete")
            expect(
                shell.contains("/bin/rm -rf '\(layout.root)'")
                    && shell.contains("/bin/rm -f '\(layout.launchdPlist)' '\(layout.executable)'"),
                "and it removes the job, the binary and the root directory")
        } else {
            expect(false, "AppleScript reads the uninstall literal")
        }
    }

    // MARK: - Helper over XPC

    static func makeRoot() -> String {
        let root = "/private/tmp/tch-\(getpid())-\(Int.random(in: 0..<1_000_000))"
        try? FileManager.default.createDirectory(
            atPath: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }

    static func requests(in root: String) -> [String] {
        let text = (try? String(contentsOfFile: root + "/fake-core.requests", encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    static func client(_ endpoint: Endpoint, requirement: String, log: StatusLog) -> ProxyHelperConnection {
        ProxyHelperConnection(
            requirement: requirement, onStatus: { log.append($0) }, onInterruption: {},
            connector: { NSXPCConnection(listenerEndpoint: endpoint.value) })
    }

    static func helperFailure(of operation: () async throws -> Void) async -> ProxyHelperFailure? {
        guard case ProxyHelperConnection.Failure.helper(let failure)? = await failure(of: operation) else {
            return nil
        }
        return failure
    }

    static func isRunning(_ status: ProxyHelperStatus) -> Bool {
        if case .running = status.core { return true }
        return false
    }

    static func launch(of status: ProxyHelperStatus) -> Int? {
        if case .running(_, let launch) = status.core { return launch }
        return nil
    }

    static func testHelper() async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = ProxyHelperLayout(appIdentifier: "com.tinycast.harness", root: root)!
        let grant = ProxyHelperGrant(
            appIdentifier: "com.tinycast.harness", leafHash: String(repeating: "a", count: 40), uid: getuid())
        let dns = FakeDNS()
        let supervisor = ProxyHelperSupervisor(
            layout: layout, grant: grant, dns: dns, boot: "boot-1", absenceGrace: .milliseconds(300))
        var idles = 0
        let listener = ProxyHelperListener(
            grant: grant, supervisor: supervisor, idleTimeout: .milliseconds(200)
        ) {
            idles += 1
        }
        let xpc = NSXPCListener.anonymous()
        listener.listen(on: xpc, requiring: selfRequirement)
        defer { xpc.invalidate() }
        let endpoint = Endpoint(xpc.endpoint)
        let log = StatusLog()
        var helper = client(endpoint, requirement: selfRequirement, log: log)

        expect((try? await helper.handshake()) == ProxyHelperWire.version, "the helper speaks this version")
        let fresh = try? await helper.status()
        expect(fresh?.core == .stopped && fresh?.installed == nil, "a fresh helper runs nothing")
        guard let (config, _) = profileConfig(mode: .portOnly), let document = try? config.document.encoded()
        else {
            expect(false, "a config to start with")
            return
        }
        let noCore = await helperFailure {
            try await helper.start(document, placeholderDNS: true, outlivesClient: false)
        }
        expect(noCore == .noCore, "nothing starts before a core is installed: \(String(describing: noCore))")
        expect(dns.writes == 0, "and DNS is untouched")

        // Installing the core.
        let binary = (try? Data(contentsOf: URL(filePath: executablePath))) ?? Data()
        let digest = sha256(binary)
        func handOver(_ path: String, sha256: String, signed: Bool) async -> ProxyHelperFailure? {
            guard let file = FileHandle(forReadingAtPath: path) else { return .storage("unreadable") }
            defer { try? file.close() }
            return await helperFailure { try await helper.installCore(file, sha256: sha256, signed: signed) }
        }
        let mismatch = await handOver(
            executablePath, sha256: String(repeating: "0", count: 64), signed: false)
        expect(mismatch == .digestMismatch, "a digest that does not match is refused")
        let unsigned = await handOver(executablePath, sha256: digest, signed: true)
        expect(unsigned == .unsigned, "a core said to be bundled must carry Tinycast's signature")
        let script = root + "/not-a-core"
        let scriptData = Data("#!/bin/sh\necho nope\n".utf8)
        FileManager.default.createFile(atPath: script, contents: scriptData)
        let notCore = await handOver(script, sha256: sha256(scriptData), signed: false)
        if case .notCore? = notCore {
            passes += 1
        } else {
            expect(false, "a binary that is no core is refused: \(String(describing: notCore))")
        }
        expect(
            await handOver(script, sha256: "../x", signed: false) == .refused("malformed digest"),
            "bad digests")
        expect(!FileManager.default.fileExists(atPath: layout.core), "none of them is installed")
        let installed = await handOver(executablePath, sha256: digest, signed: false)
        expect(installed == nil, "a download is installed by its digest: \(String(describing: installed))")
        let afterInstall = try? await helper.status()
        expect(
            afterInstall?.installed == ProxyHelperRecord.Core(sha256: digest, tag: FakeCore.tag),
            "and recorded")
        let copied = FileManager.default.contents(atPath: layout.core).map(sha256)
        expect(copied == digest, "the copy root runs is the verified one")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: layout.coreDirectory)) ?? []
        expect(leftovers == ["mihomo"], "with nothing left over: \(leftovers)")

        // Node files.
        expect(
            await helperFailure { try await helper.writeFile("../evil.yaml", contents: Data()) }
                == .refused("file ../evil.yaml is not one Tinycast writes"),
            "a name outside the pattern is refused")
        let nodes = Data("proxies: []\n".utf8)
        let wrote = await failure { try await helper.writeFile("src-0123abcd.yaml", contents: nodes) }
        let written = layout.providers + "/src-0123abcd.yaml"
        let mode = (try? FileManager.default.attributesOfItem(atPath: written))?[.posixPermissions] as? Int
        expect(
            wrote == nil && FileManager.default.contents(atPath: written) == nodes && mode == 0o600,
            "a node file lands in providers/, 0600")
        _ = await failure { try await helper.removeFile("src-0123abcd.yaml") }
        expect(!FileManager.default.fileExists(atPath: written), "and can be removed")

        // Starting.
        var tampered = (try? JSONSerialization.jsonObject(with: document)) as? [String: Any] ?? [:]
        tampered["external-controller"] = "0.0.0.0:9090"
        let tamperedData = (try? JSONSerialization.data(withJSONObject: tampered)) ?? Data()
        let refused = await helperFailure {
            try await helper.start(tamperedData, placeholderDNS: true, outlivesClient: false)
        }
        expect(refused == .refused("unexpected key external-controller"), "a config opening a controller")
        expect(supervisor.status.core == .stopped, "starts nothing")

        let started = await failure {
            try await helper.start(document, placeholderDNS: true, outlivesClient: false)
        }
        expect(started == nil, "the builder's config starts the core: \(String(describing: started))")
        expect(
            isRunning(supervisor.status) && launch(of: supervisor.status) == 1,
            "it runs: \(supervisor.status)")
        expect(await waitUntil { log.all.contains(where: isRunning) }, "and the client hears so")
        expect(dns.current("SVC-A") == ProxyDNSBackup.placeholder, "the placeholder stands in")
        let record = FileManager.default.contents(atPath: layout.record).flatMap {
            try? JSONDecoder().decode(ProxyHelperRecord.self, from: $0)
        }
        expect(
            record?.dns == ProxyDNSBackup(serviceID: "SVC-A", servers: ["192.168.0.1"])
                && record?.wantsCore == true
                && record?.boot == "boot-1",
            "with the original kept on disk: \(String(describing: record))")
        let configMode =
            (try? FileManager.default.attributesOfItem(atPath: layout.config))?[.posixPermissions] as? Int
        expect(
            FileManager.default.contents(atPath: layout.config) == document && configMode == 0o600,
            "config 0600")

        let connected = helper
        let api = ProxyAPIService { try await connected.openController() }
        let version = try? await api.version()
        expect(
            version == FakeCore.tag,
            "a handed-over socket reaches the controller: \(String(describing: version))")

        // Applying again.
        _ = await failure { try await helper.start(document, placeholderDNS: true, outlivesClient: false) }
        expect(
            !requests(in: root).contains { $0.hasPrefix("PUT /configs") }, "the same config is not reloaded")
        guard let (otherConfig, _) = profileConfig(mode: .portOnly),
            let other = try? otherConfig.document.encoded()
        else { return }
        let reloaded = await failure {
            try await helper.start(other, placeholderDNS: true, outlivesClient: false)
        }
        expect(
            reloaded == nil && requests(in: root).contains("PUT /configs?force=true")
                && FileManager.default.contents(atPath: layout.config) == other,
            "a changed config is reloaded in place")
        expect(launch(of: supervisor.status) == 1, "without restarting the core")
        FileManager.default.createFile(
            atPath: root + "/fake-core.json", contents: Data("{\"rejectReload\":\"bad port\"}".utf8))
        let rejected = await helperFailure {
            try await helper.start(document, placeholderDNS: true, outlivesClient: false)
        }
        expect(
            rejected == .rejected("bad port"),
            "the core's refusal comes back: \(String(describing: rejected))")
        expect(
            FileManager.default.contents(atPath: layout.config) == other,
            "and the file keeps the last good config")
        try? FileManager.default.removeItem(atPath: root + "/fake-core.json")

        // A crash.
        let pid = (try? String(contentsOfFile: layout.corePID, encoding: .utf8)).flatMap { pid_t($0) } ?? 0
        expect(pid > 0, "the core's pid is recorded")
        if pid > 0 { kill(pid, SIGKILL) }
        expect(
            await waitUntil { log.all.contains { $0.core == .restarting(attempt: 1) } },
            "a crash is reported as a restart")
        expect(await waitUntil(.seconds(6)) { launch(of: supervisor.status) == 2 }, "and the core comes back")
        expect(await waitUntil { log.all.contains { launch(of: $0) == 2 } }, "which the client hears")
        expect(dns.current("SVC-A") == ProxyDNSBackup.placeholder, "with DNS still in place")
        let revisions = log.all.map(\.revision)
        expect(revisions == revisions.sorted() && Set(revisions).count == revisions.count, "pushes count up")

        // Tinycast going away.
        helper.close()
        expect(await waitUntil { supervisor.status.core == .stopped }, "a client gone stops the core it ran")
        expect(dns.current("SVC-A") == ["192.168.0.1"], "and DNS is put back")
        expect(await waitUntil { idles > 0 }, "after which the helper may exit")

        // Staying connected after quitting.
        helper = client(endpoint, requirement: selfRequirement, log: log)
        _ = await failure { try await helper.start(document, placeholderDNS: true, outlivesClient: true) }
        expect(isRunning(supervisor.status), "running again")
        dns.set(["8.8.8.8"], for: "SVC-A")
        helper.close()
        try? await Task.sleep(for: .milliseconds(700))
        expect(isRunning(supervisor.status), "a core asked to stay outlives its client")
        helper = client(endpoint, requirement: selfRequirement, log: log)
        _ = await failure { try await helper.stop() }
        expect(supervisor.status.core == .stopped, "until asked to stop")
        expect(dns.current("SVC-A") == ["8.8.8.8"], "servers someone else set are left alone")

        // The primary service changing while connected.
        _ = await failure { try await helper.start(document, placeholderDNS: true, outlivesClient: false) }
        dns.primary = "SVC-B"
        _ = await failure { try await helper.start(document, placeholderDNS: true, outlivesClient: false) }
        expect(
            dns.current("SVC-A") == ["8.8.8.8"] && dns.current("SVC-B") == ProxyDNSBackup.placeholder,
            "the placeholder follows the new primary service, the old one restored")
        _ = await failure { try await helper.start(document, placeholderDNS: false, outlivesClient: false) }
        expect(dns.current("SVC-B") == nil, "turning the placeholder off puts DNS back while connected")
        _ = await failure { try await helper.stop() }
        dns.primary = "SVC-A"

        await testResume(layout: layout, grant: grant, dns: dns, digest: digest)
        helper.close()
    }

    static func testResume(
        layout: ProxyHelperLayout, grant: ProxyHelperGrant, dns: FakeDNS, digest: String
    ) async {
        func write(_ record: ProxyHelperRecord) {
            try? JSONEncoder().encode(record).write(to: URL(filePath: layout.record))
        }
        dns.set(["192.168.0.1"], for: "SVC-A")
        var record = ProxyHelperRecord()
        record.wantsCore = true
        record.boot = "boot-1"
        record.placeholderDNS = true
        record.core = ProxyHelperRecord.Core(sha256: digest, tag: FakeCore.tag)
        write(record)

        let resumed = ProxyHelperSupervisor(layout: layout, grant: grant, dns: dns, boot: "boot-1")
        expect(resumed.status.core == .starting, "a helper relaunched in this boot reports starting at once")
        await resumed.resumeAfterLaunch()
        expect(isRunning(resumed.status), "and runs the core again: \(resumed.status)")
        expect(dns.current("SVC-A") == ProxyDNSBackup.placeholder, "with the placeholder")
        await resumed.stop()
        expect(dns.current("SVC-A") == ["192.168.0.1"], "and stops cleanly")

        record.boot = "boot-0"
        record.dns = ProxyDNSBackup(serviceID: "SVC-A", servers: ["10.0.0.1"])
        write(record)
        dns.set(ProxyDNSBackup.placeholder, for: "SVC-A")
        let rebooted = ProxyHelperSupervisor(layout: layout, grant: grant, dns: dns, boot: "boot-1")
        await rebooted.resumeAfterLaunch()
        expect(rebooted.status.core == .stopped, "after a reboot the core waits to be asked")
        expect(dns.current("SVC-A") == ["10.0.0.1"], "but DNS a crash left set is put back")
        let saved = FileManager.default.contents(atPath: layout.record).flatMap {
            try? JSONDecoder().decode(ProxyHelperRecord.self, from: $0)
        }
        expect(saved?.wantsCore == false && saved?.dns == nil, "and the record says so")

        // A core an earlier helper process left running.
        let orphan = Process()
        orphan.executableURL = URL(filePath: layout.core)
        orphan.arguments = [
            "-d", layout.root, "-f", layout.config, "-ext-ctl-unix", layout.root + "/orphan.sock"
        ]
        orphan.standardOutput = FileHandle.nullDevice
        orphan.standardError = FileHandle.nullDevice
        guard let exit = try? orphan.runObservingExit() else {
            expect(false, "an orphan to stop")
            return
        }
        try? Data(String(orphan.processIdentifier).utf8).write(to: URL(filePath: layout.corePID))
        let next = ProxyHelperSupervisor(layout: layout, grant: grant, dns: dns, boot: "boot-1")
        await next.resumeAfterLaunch()
        exit.wait()
        expect(!orphan.isRunning, "a core left by an earlier helper is stopped before anything starts")
    }

    static func testRejections() async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = ProxyHelperLayout(appIdentifier: "com.tinycast.harness", root: root)!
        func attempt(listenerRequirement: String, uid: UInt32, clientRequirement: String) async -> Bool {
            let grant = ProxyHelperGrant(
                appIdentifier: "com.tinycast.harness", leafHash: String(repeating: "b", count: 40), uid: uid)
            let supervisor = ProxyHelperSupervisor(
                layout: layout, grant: grant, dns: FakeDNS(), boot: "boot-1")
            let listener = ProxyHelperListener(grant: grant, supervisor: supervisor) {}
            let xpc = NSXPCListener.anonymous()
            listener.listen(on: xpc, requiring: listenerRequirement)
            defer { xpc.invalidate() }
            let helper = client(Endpoint(xpc.endpoint), requirement: clientRequirement, log: StatusLog())
            defer { helper.close() }
            let started = ContinuousClock.now
            let refused = await failure { _ = try await helper.handshake() } as? ProxyHelperConnection.Failure
            expect(ContinuousClock.now - started < .seconds(5), "a refusal is prompt, not a timeout")
            return refused == .unavailable
        }
        let grantOnly = ProxyHelperGrant(
            appIdentifier: "com.tinycast.harness", leafHash: String(repeating: "b", count: 40), uid: getuid())
        expect(
            await attempt(
                listenerRequirement: grantOnly.appRequirement, uid: getuid(),
                clientRequirement: selfRequirement),
            "a process not signed as Tinycast is turned away")
        expect(
            await attempt(
                listenerRequirement: selfRequirement, uid: getuid() + 1, clientRequirement: selfRequirement),
            "so is another user")
        expect(
            await attempt(
                listenerRequirement: selfRequirement, uid: getuid(),
                clientRequirement: "identifier \"not-the-helper\""),
            "and Tinycast refuses a helper that is not its own")
    }

    static func main() async {
        FakeCore.runIfAsked()
        testLayout()
        testGrant()
        testPolicy()
        testRecord()
        testWireValues()
        testScripts()
        await testHelper()
        await testRejections()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
