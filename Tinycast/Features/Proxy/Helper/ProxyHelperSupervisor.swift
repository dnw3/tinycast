import CryptoKit
import Foundation
import os

/// Runs the root core as Tinycast last asked, from the copy it verified, and again after a crash.
@MainActor
final class ProxyHelperSupervisor {
    private(set) var status = ProxyHelperStatus()
    /// After every change of `status`, for the clients and the idle check.
    var onChange: (() -> Void)?

    let layout: ProxyHelperLayout
    private let grant: ProxyHelperGrant
    private let placeholder: ProxyDNSPlaceholder
    private let boot: String
    private let absenceGrace: Duration
    private let api: ProxyAPIService
    private var record: ProxyHelperRecord
    /// Decided at launch, so a status asked for before the resume reads as starting, not stopped.
    private let launchPlan: ProxyHelperRecord.LaunchPlan
    private var process: Process?
    private var generation = 0
    private var exitStatus: Int32?
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopping = false
    private var launches = 0
    private var restarts = 0
    private var restartPolicy = ProxyRestartPolicy()
    private var restartTask: Task<Void, Never>?
    private var absenceTask: Task<Void, Never>?
    private var queue: Task<Void, Never>?

    nonisolated private static let logger = Logger(subsystem: "com.tinycast", category: "ProxyHelper")

    init(
        layout: ProxyHelperLayout, grant: ProxyHelperGrant, dns: any ProxySystemDNS, boot: String,
        absenceGrace: Duration = .seconds(5)
    ) {
        self.layout = layout
        self.grant = grant
        placeholder = ProxyDNSPlaceholder(dns: dns)
        self.boot = boot
        self.absenceGrace = absenceGrace
        api = .unixSocket(at: layout.socket)
        var record = Self.loadRecord(at: layout.record)
        launchPlan = record.plan(forLaunchIn: boot)
        self.record = record
        status.installed = record.core
        status.placeholderApplied = record.dns != nil
        if launchPlan.resumesCore { status.core = .starting }
    }

    /// Nothing to run and nothing waiting to run, so the process may exit.
    var isIdle: Bool { !record.wantsCore && process == nil && restartTask == nil }

    /// Requests run one at a time in arrival order, as each may wait on the core.
    func enqueue(_ operation: @escaping @MainActor (ProxyHelperSupervisor) async -> Void) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    // MARK: - Requests

    /// A core left by a crashed helper is stopped; one wanted in this boot is started again.
    func resumeAfterLaunch() async {
        await Self.stopOrphan(of: layout)
        saveRecord()
        if launchPlan.restoresDNS { restorePlaceholder() }
        if launchPlan.resumesCore, process == nil, await launch() != nil { restartAfterExit() }
        publish()
    }

    func installCore(from file: FileHandle, sha256: String, signed: Bool) async throws(ProxyHelperFailure) {
        guard ProxyHelperGrant.isDigest(sha256) else { throw .refused("malformed digest") }
        let manager = FileManager.default
        let staging = layout.coreDirectory + "/.incoming-" + UUID().uuidString
        do {
            try manager.createDirectory(
                atPath: layout.coreDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            throw .storage(error.localizedDescription)
        }
        defer { try? manager.removeItem(atPath: staging) }
        let digest: String
        do {
            digest = try await Self.copy(file, to: staging, limit: ProxyHelperPolicy.maxCoreSize)
        } catch let failure as ProxyHelperFailure {
            throw failure
        } catch {
            throw .storage(error.localizedDescription)
        }
        guard digest == sha256 else { throw .digestMismatch }
        guard !signed || ProxyCodeSignature.satisfies(fileAt: staging, requirement: grant.coreRequirement)
        else {
            throw .unsigned
        }
        let identity: ProxyCore.Identity
        do {
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging)
            identity = try await ProxyCoreRunner.identify(URL(filePath: staging))
        } catch {
            throw .notCore(error.localizedDescription)
        }
        let machine = ProxyCore.Identity.expected(tag: identity.tag, architecture: .current)
        guard identity == machine else { throw .notCore("\(identity.tag) \(identity.architecture)") }
        guard rename(staging, layout.core) == 0 else { throw .storage(String(cString: strerror(errno))) }
        record.core = ProxyHelperRecord.Core(sha256: digest, tag: identity.tag)
        saveRecord()
        status.installed = record.core
        publish()
    }

    func writeFile(_ name: String, contents: Data) throws(ProxyHelperFailure) {
        guard ProxyHelperPolicy.isProviderFile(name), contents.count <= ProxyHelperPolicy.maxFileSize else {
            throw .refused("file \(name) is not one Tinycast writes")
        }
        do {
            try FileManager.default.createDirectory(
                atPath: layout.providers, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try Self.writeProtected(contents, to: layout.providers + "/" + name)
        } catch {
            throw .storage(error.localizedDescription)
        }
    }

    func removeFile(_ name: String) throws(ProxyHelperFailure) {
        guard ProxyHelperPolicy.isProviderFile(name) else {
            throw .refused("file \(name) is not one Tinycast writes")
        }
        try? FileManager.default.removeItem(atPath: layout.providers + "/" + name)
    }

    /// A running core reloads a changed config in place; the file is written once it accepts.
    func start(config: Data, placeholderDNS: Bool, outlivesClient: Bool) async throws(ProxyHelperFailure) {
        let problems = ProxyHelperPolicy.problems(inConfig: config)
        guard problems.isEmpty else { throw .refused(problems.joined(separator: "; ")) }
        if process != nil, case .running = status.core {
            if FileManager.default.contents(atPath: layout.config) != config {
                do {
                    try await api.reload(config)
                } catch ProxyAPIService.Failure.rejected(_, let message) {
                    throw .rejected(message)
                } catch {
                    throw .unreachable
                }
                try writeConfig(config)
            }
            record.outlivesClient = outlivesClient
            record.placeholderDNS = placeholderDNS
            saveRecord()
            if placeholderDNS { applyPlaceholder() } else { restorePlaceholder() }
            publish()
            return
        }
        try writeConfig(config)
        record.outlivesClient = outlivesClient
        record.placeholderDNS = placeholderDNS
        restartTask?.cancel()
        restartTask = nil
        restartPolicy.reset()
        restarts = 0
        if let failure = await launch() {
            record.wantsCore = false
            saveRecord()
            publish()
            throw failure
        }
        publish()
    }

    func stop() async {
        restartTask?.cancel()
        restartTask = nil
        absenceTask?.cancel()
        absenceTask = nil
        record.wantsCore = false
        saveRecord()
        await terminateCore()
        restorePlaceholder()
        status.core = .stopped
        publish()
    }

    /// For SIGTERM: the wish stays recorded, so a relaunch in this boot resumes the core.
    func shutDown() async {
        restartTask?.cancel()
        absenceTask?.cancel()
        await terminateCore()
        restorePlaceholder()
    }

    /// Only root can open the socket, so this is the one way a client reaches the controller.
    func openController() throws(ProxyHelperFailure) -> Int32 {
        guard process != nil, case .running = status.core else { throw .unreachable }
        do {
            return try ProxySocket.connect(path: layout.socket)
        } catch {
            throw .unreachable
        }
    }

    /// Tinycast quitting or crashing takes the core with it, unless it asked for the core to stay.
    func clientsDidChange(count: Int) {
        absenceTask?.cancel()
        absenceTask = nil
        guard count == 0, record.wantsCore, !record.outlivesClient else { return }
        absenceTask = Task { [weak self, absenceGrace] in
            try? await Task.sleep(for: absenceGrace)
            guard !Task.isCancelled else { return }
            self?.enqueue { await $0.stop() }
        }
    }

    // MARK: - Core

    /// The failure that kept the core from running, or nil once its controller answers.
    private func launch() async -> ProxyHelperFailure? {
        guard let installed = record.core, await Self.digest(ofFileAt: layout.core) == installed.sha256 else {
            return .noCore
        }
        await Self.stopOrphan(of: layout)
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                atPath: layout.socketDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: layout.root)
            try? manager.removeItem(atPath: layout.socket)
        } catch {
            return .storage(error.localizedDescription)
        }
        generation += 1
        let launched = generation
        let onExit: @Sendable (Int32) -> Void = { [weak self] exitStatus in
            Task { @MainActor in self?.coreDidExit(exitStatus, generation: launched) }
        }
        do {
            process = try ProxyCoreRunner.launch(
                core: URL(filePath: layout.core), directory: URL(filePath: layout.root),
                socket: layout.socket,
                onExit: onExit)
        } catch {
            return .storage(error.localizedDescription)
        }
        exitStatus = nil
        record.wantsCore = true
        record.boot = boot
        saveRecord()
        if let pid = process?.processIdentifier {
            try? Self.writeProtected(Data(String(pid).utf8), to: layout.corePID)
        }
        status.core = .starting
        publish()

        guard await waitUntilReachable(launched) else {
            let exited = exitStatus
            await terminateCore()
            status.core = .stopped
            let log = ProxyCoreRunner.logTail(in: URL(filePath: layout.root))
            return exited.map { .exited(status: $0, log: log) } ?? .unreachable
        }
        launches += 1
        status.core = .running(since: .now, launch: launches)
        if record.placeholderDNS { applyPlaceholder() } else { restorePlaceholder() }
        return nil
    }

    private func waitUntilReachable(_ launched: Int) async -> Bool {
        for _ in 0..<100 {
            guard generation == launched, process != nil else { return false }
            if (try? await api.version()) != nil { return generation == launched && process != nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func coreDidExit(_ status: Int32, generation launched: Int) {
        guard launched == generation, process != nil else { return }
        process = nil
        exitStatus = status
        try? FileManager.default.removeItem(atPath: layout.corePID)
        for waiter in exitWaiters { waiter.resume() }
        exitWaiters = []
        guard !stopping, case .running = self.status.core else { return }
        Self.logger.error("Root core exited on its own with status \(status)")
        restartAfterExit()
    }

    /// Backs off 1, 2, 4… seconds; five exits in five minutes stop it, as for the user-level core.
    private func restartAfterExit() {
        let log = ProxyCoreRunner.logTail(in: URL(filePath: layout.root))
        guard record.wantsCore, let delay = restartPolicy.delay(afterExitAt: .now) else {
            record.wantsCore = false
            saveRecord()
            restorePlaceholder()
            status.core = .failed(status: exitStatus ?? -1, log: log)
            publish()
            return
        }
        restarts += 1
        status.core = .restarting(attempt: restarts)
        publish()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueue { supervisor in
                supervisor.restartTask = nil
                guard supervisor.record.wantsCore, supervisor.process == nil else { return }
                if await supervisor.launch() != nil { supervisor.restartAfterExit() }
                supervisor.publish()
            }
        }
    }

    private func terminateCore() async {
        guard let process else { return }
        stopping = true
        defer { stopping = false }
        process.terminate()
        let pid = process.processIdentifier
        let deadline = Task { [weak self] in
            try await Task.sleep(for: .seconds(3))
            if self?.process === process { kill(pid, SIGKILL) }
        }
        await withCheckedContinuation { exitWaiters.append($0) }
        deadline.cancel()
    }

    // MARK: - DNS

    private func applyPlaceholder() {
        do {
            try placeholder.apply(to: &record, saving: saveRecord)
            status.dnsProblem = nil
        } catch {
            status.dnsProblem = "\(error)"
        }
        status.placeholderApplied = record.dns != nil
    }

    private func restorePlaceholder() {
        do {
            try placeholder.restore(&record, saving: saveRecord)
            status.dnsProblem = nil
        } catch {
            status.dnsProblem = "\(error)"
        }
        status.placeholderApplied = record.dns != nil
    }

    // MARK: - Files

    private func publish() {
        status.revision += 1
        onChange?()
    }

    private func writeConfig(_ config: Data) throws(ProxyHelperFailure) {
        do {
            try Self.writeProtected(config, to: layout.config)
        } catch {
            throw .storage(error.localizedDescription)
        }
    }

    private func saveRecord() {
        Self.save(record, at: layout.record)
    }

    private func saveRecord(_ record: ProxyHelperRecord) {
        Self.save(record, at: layout.record)
    }

    nonisolated static func save(_ record: ProxyHelperRecord, at path: String) {
        do {
            try writeProtected(JSONEncoder().encode(record), to: path)
        } catch {
            logger.error("Helper record not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func loadRecord(at path: String) -> ProxyHelperRecord {
        guard let data = FileManager.default.contents(atPath: path) else { return ProxyHelperRecord() }
        return (try? JSONDecoder().decode(ProxyHelperRecord.self, from: data)) ?? ProxyHelperRecord()
    }

    nonisolated static func writeProtected(_ data: Data, to path: String) throws {
        try data.write(to: URL(filePath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Reads to the end on a thread of its own, hashing as it writes.
    @concurrent
    private static func copy(_ file: FileHandle, to path: String, limit: Int) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    with: Result {
                        guard
                            FileManager.default.createFile(
                                atPath: path, contents: nil, attributes: [.posixPermissions: 0o700])
                        else { throw CocoaError(.fileWriteUnknown) }
                        let output = try FileHandle(forWritingTo: URL(filePath: path))
                        defer { try? output.close() }
                        var hasher = SHA256()
                        var total = 0
                        while let chunk = try file.read(upToCount: 1 << 20), !chunk.isEmpty {
                            total += chunk.count
                            guard total <= limit else {
                                throw ProxyHelperFailure.refused("core is too large")
                            }
                            hasher.update(data: chunk)
                            try output.write(contentsOf: chunk)
                        }
                        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    })
            }
        }
    }

    @concurrent
    private static func digest(ofFileAt path: String) async -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A core left by an earlier helper process holds the TUN device, so it goes first.
    @concurrent
    private static func stopOrphan(of layout: ProxyHelperLayout) async {
        defer { try? FileManager.default.removeItem(atPath: layout.corePID) }
        guard let text = try? String(contentsOfFile: layout.corePID, encoding: .utf8), let pid = pid_t(text),
            pid > 0
        else { return }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard path == layout.core else { return }
        kill(pid, SIGTERM)
        for _ in 0..<30 where kill(pid, 0) == 0 { usleep(100_000) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }
}
