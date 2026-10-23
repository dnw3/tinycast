import Foundation
import os

/// Keeps the core running as the profile describes, and mirrors what it reports for the views.
@MainActor
@Observable
final class ProxyManager {
    enum Status: Equatable, Sendable {
        case off
        case starting
        case running(since: Date)
        case failed(ProxyFailure)
    }

    /// Where a check for, or install of, a newer core stands.
    enum CoreUpdate: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(ProxyCoreRelease)
        /// A fraction once the download's size is known.
        case downloading(ProxyCoreRelease, fraction: Double?)
        case installing(ProxyCoreRelease)
    }

    private(set) var status = Status.off
    private(set) var snapshot: ProxySnapshot?
    private(set) var coreVersion: String?
    /// A failure that left a running core as it was, for the next HUD; `dismissNotice()` clears it.
    private(set) var notice: ProxyFailure?
    private(set) var testingStrategies: Set<UUID> = []
    private(set) var updatingSources: Set<UUID> = []
    private(set) var isTestingSources = false
    private(set) var isUpdatingRuleSets = false
    private(set) var coreUpdate = CoreUpdate.idle
    /// The core the last start or check chose, for settings to name.
    private(set) var activeCore: ProxyCore?
    /// The running core is the helper's, which takes over all traffic through a TUN device.
    private(set) var isTUN = false

    @ObservationIgnored let store: ProxyStore
    @ObservationIgnored let helper: ProxyHelperClient
    /// Holds the user-level core's socket: short enough for `sockaddr_un`, and private to the user.
    @ObservationIgnored private let runtimeDirectory: URL
    @ObservationIgnored private let ruleCatalogBase: String
    @ObservationIgnored private let coreFeed: URL
    @ObservationIgnored private var coreUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var core: RunningCore? {
        didSet { isTUN = core?.helper != nil }
    }
    @ObservationIgnored private var applied: ProxyConfig?
    @ObservationIgnored private var appliedOptions: HelperOptions?
    @ObservationIgnored private var appliedSelections: [String: String] = [:]
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var restartPolicy = ProxyRestartPolicy()
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    /// Copies a TUN core's warnings to a file the user can read, as the helper's log is root's.
    @ObservationIgnored private var logRecorder: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    static let testTimeout = Duration.seconds(5)
    static let tunLogName = "tun-core.log"
    private static let logger = Logger(subsystem: "com.tinycast", category: "Proxy")

    init(
        store: ProxyStore,
        runtimeDirectory: URL = FileManager.default.temporaryDirectory.appending(
            path: (Bundle.main.bundleIdentifier ?? "com.tinycast.app") + ".proxy", directoryHint: .isDirectory
        ),
        ruleCatalogBase: String = ProxyRuleSet.catalogBase,
        coreFeed: URL = ProxyCoreRelease.feed,
        helper: ProxyHelperClient = ProxyHelperClient()
    ) {
        self.store = store
        self.runtimeDirectory = runtimeDirectory
        self.ruleCatalogBase = ruleCatalogBase
        self.coreFeed = coreFeed
        self.helper = helper
        helper.onStatus = { [weak self] in self?.helperStatusDidChange($0) }
        helper.onInterruption = { [weak self] in self?.helperWasInterrupted() }
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var mode: ProxyMode { store.mode }

    /// The running core's API; monitors fetch it again after the core restarts.
    var controller: ProxyAPIService? { isRunning ? core?.api : nil }

    var hasBundledCore: Bool { ProxyCoreRunner.bundledCore != nil }

    // MARK: - Intent

    /// Restores the last connection when asked to, and takes back a TUN core left running.
    func start() {
        let profile = store.profile
        if profile.general.usesTUN, helper.state == .ready {
            enqueue { await $0.adoptHelperCore() }
            return
        }
        guard profile.isEnabled, store.wantsConnection, profile.general.connectsAtLogin else {
            setWantsConnection(false)
            return
        }
        enqueue { await $0.bringUp() }
    }

    func connect() {
        setWantsConnection(true)
        enqueue { await $0.bringUp() }
    }

    func disconnect() {
        setWantsConnection(false)
        restartTask?.cancel()
        enqueue { await $0.tearDown() }
    }

    /// Every profile edit lands here: saved, then applied to a running core as cheaply as it can.
    func update(_ change: (inout ProxyProfile) -> Void) throws {
        try store.update(change)
        enqueue { await $0.reconcile() }
    }

    func select(_ option: String, in strategy: UUID) throws {
        try update { profile in
            guard let index = profile.strategies.firstIndex(where: { $0.id == strategy }) else { return }
            profile.strategies[index].selected = option
        }
    }

    /// `ProxyRoute.finalID` names the route that takes the remaining traffic.
    func route(_ id: String, to target: ProxyTarget) throws {
        try update { profile in
            if id == ProxyRoute.finalID {
                profile.finalTarget = target
            } else if let index = profile.routes.firstIndex(where: { $0.id == id }) {
                profile.routes[index].target = target
            }
        }
    }

    func dismissNotice() {
        notice = nil
    }

    /// Saved, and sent to a running core on its own, since its config needs no reload for it.
    func setMode(_ mode: ProxyMode) {
        do {
            try store.setMode(mode)
        } catch {
            notice = .storage(error.localizedDescription)
            return
        }
        enqueue { await $0.applyMode() }
    }

    /// Starts the same core again on the current config, which also rereads every local file.
    func restart() {
        enqueue { manager in
            guard let running = manager.core else {
                await manager.reconcile()
                return
            }
            await manager.stop(running, as: .starting)
            await manager.bringUp()
        }
    }

    /// The config as the running core would get it, links masked, for reading and copying.
    func previewConfig(linkPlaceholder: String) throws -> String {
        let links = Dictionary(
            uniqueKeysWithValues: store.subscriptionURLs().keys.map { ($0, linkPlaceholder) })
        let config = try ProxyConfigBuilder.build(
            store.profile,
            environment: ProxyBuildEnvironment(
                mode: wantsTUN ? .tun : .portOnly, subscriptionURLs: links, ruleCatalogBase: ruleCatalogBase,
                proxyMode: store.mode))
        let data = try config.document.encoded(pretty: true)
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    // MARK: - Core updates

    /// Asks GitHub for the newest official release; `coreUpdate` says whether it is newer.
    func checkForCoreUpdate() {
        guard coreUpdateTask == nil else { return }
        coreUpdate = .checking
        coreUpdateTask = Task { [weak self] in
            await self?.findCoreUpdate()
            self?.coreUpdateTask = nil
        }
    }

    /// Installs the release the check found and moves a connected proxy onto it.
    func installCoreUpdate() {
        guard case .available(let release) = coreUpdate, coreUpdateTask == nil else { return }
        coreUpdate = .downloading(release, fraction: nil)
        coreUpdateTask = Task { [weak self] in
            await self?.install(release)
            self?.coreUpdateTask = nil
        }
    }

    func cancelCoreUpdate() {
        coreUpdateTask?.cancel()
    }

    /// Names the core a start would choose, for a settings page opened while nothing runs.
    func identifyActiveCore() {
        guard core == nil, coreUpdateTask == nil else { return }
        Task { _ = await currentCoreVersion() }
    }

    /// Deletes every downloaded core, so the one the app shipped with runs again.
    func restoreBundledCore() {
        coreUpdateTask?.cancel()
        coreUpdate = .idle
        enqueue { manager in
            try? FileManager.default.removeItem(at: manager.store.releasesDirectory)
            guard let running = manager.core else {
                manager.activeCore = ProxyCoreRunner.bundledCore.map {
                    ProxyCore(executable: $0, version: nil, isBundled: true)
                }
                await manager.reconcile()
                return
            }
            guard !running.isBundled else { return }
            await manager.stop(running, as: .starting)
            await manager.bringUp()
        }
    }

    // MARK: - Core requests

    func refresh() async {
        guard let running = core, isRunning else { return }
        let api = running.api
        do {
            async let proxies = api.proxies()
            async let providers = api.providers()
            async let ruleProviders = api.ruleProviders()
            let snapshot = await Self.snapshot(
                proxies: try await proxies, providers: try await providers,
                ruleProviders: (try? await ruleProviders) ?? [:], profile: store.profile)
            guard core === running else { return }
            self.snapshot = snapshot
        } catch {
            Self.logger.error("Proxy refresh failed: \(error.localizedDescription, privacy: .public)")
        }
        if let applied { await applySelections(applied.selections, on: running) }
    }

    func testDelays(of strategyID: UUID) async {
        guard let running = core, let strategy = store.profile.strategy(strategyID),
            testingStrategies.insert(strategyID).inserted
        else { return }
        defer { testingStrategies.remove(strategyID) }
        do {
            _ = try await running.api.testGroup(
                strategy.name, url: strategy.testURL, timeout: Self.testTimeout)
        } catch {
            Self.logger.notice(
                "Delay test of a strategy failed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    func testNode(_ name: String) async {
        guard let running = core, let source = snapshot?.nodes[name]?.source,
            let provider = store.profile.sources.first(where: { $0.id == source })?.providerName
        else { return }
        _ = try? await running.api.testNode(
            name, provider: provider, url: ProxyStrategy.defaultTestURL, timeout: Self.testTimeout)
        await refresh()
    }

    /// Every enabled source's nodes, tested at once.
    func testSources() async {
        guard let running = core, !isTestingSources else { return }
        isTestingSources = true
        defer { isTestingSources = false }
        let api = running.api
        let providers = store.profile.sources.filter(\.isEnabled).map(\.providerName)
        await withTaskGroup { group in
            for provider in providers {
                group.addTask { _ = try? await api.testProvider(provider) }
            }
        }
        await refresh()
    }

    /// Every enabled subscription fetched again; one that fails keeps its last nodes.
    func updateSources() async {
        let subscriptions = store.profile.sources.filter { $0.isEnabled && $0.kind == .subscription }
        await withTaskGroup { group in
            for source in subscriptions {
                group.addTask { await self.updateSource(source.id) }
            }
        }
    }

    func updateSource(_ id: UUID) async {
        guard let running = core, let source = store.profile.sources.first(where: { $0.id == id }),
            updatingSources.insert(id).inserted
        else { return }
        defer { updatingSources.remove(id) }
        do {
            try await running.api.updateProvider(source.providerName)
        } catch {
            if core === running { notice = .sourceUpdate(id, reason: Self.reason(from: error)) }
        }
        await refresh()
    }

    /// Every rule set downloaded again; one that fails keeps its rules, and makes this false.
    @discardableResult
    func updateRuleSets() async -> Bool {
        guard let running = core, isRunning, !isUpdatingRuleSets else { return false }
        isUpdatingRuleSets = true
        defer { isUpdatingRuleSets = false }
        let api = running.api
        let names = (try? await api.ruleProviders()).map { Array($0.keys) } ?? []
        let failures = await withTaskGroup(of: (any Error)?.self) { group in
            for name in names {
                group.addTask {
                    do {
                        try await api.updateRuleProvider(name)
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            var failures: [any Error] = []
            for await failure in group {
                if let failure { failures.append(failure) }
            }
            return failures
        }
        if !failures.isEmpty, core === running {
            notice = .ruleSetUpdate(
                count: failures.count, reason: failures.lazy.compactMap(Self.reason).first)
        }
        await refresh()
        return failures.isEmpty
    }

    /// Has a connected core reread a node file just edited; the next start copies it in anyway.
    func reloadFile(at url: URL) {
        enqueue { await $0.reloadNodes(at: url.resolvingSymlinksInPath()) }
    }

    /// The core would otherwise start from the old link's nodes and keep them until they expire.
    func discardCachedNodes(of source: ProxySource) {
        try? FileManager.default.removeItem(at: store.coreDirectory.appending(path: source.providerPath))
        guard helper.state == .ready else { return }
        let name = source.providerName + ".yaml"
        enqueue { manager in
            guard let connection = await manager.helper.connect() else { return }
            try? await connection.removeFile(name)
            if !manager.isTUN { manager.helper.disconnect() }
        }
    }

    /// A user-level core is Tinycast's child, so it stops with the app; the helper's may stay.
    func prepareForTermination() {
        coreUpdateTask?.cancel()
        guard let core, core.exitStatus == nil else { return }
        core.stopping = true
        guard let process = core.process else {
            // Best effort: the helper also stops it once Tinycast's connection is gone.
            if !store.profile.general.staysConnectedAfterQuit, let helper = core.helper {
                Task { try? await helper.stop() }
            }
            return
        }
        process.terminate()
    }

    private func reloadNodes(at edited: URL) async {
        guard let running = core, isRunning, let applied else { return }
        for file in applied.files {
            guard let source = store.profile.sources.first(where: { $0.id == file.source }),
                case .file(let path) = source.kind,
                URL(filePath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath() == edited
            else { continue }
            do {
                let nodes = try Data(contentsOf: edited)
                if let helper = running.helper {
                    try await helper.writeFile(source.providerName + ".yaml", contents: nodes)
                } else {
                    try nodes.write(to: running.directory.appending(path: file.path), options: .atomic)
                }
                try await running.api.updateProvider(source.providerName)
            } catch {
                if core === running { notice = .sourceUpdate(source.id, reason: Self.reason(from: error)) }
            }
        }
        await refresh()
    }

    // MARK: - TUN helper

    /// Asks an installed helper which version it speaks, so Settings can offer to update it.
    func checkHelper() {
        helper.refresh()
        guard helper.state == .ready || helper.state == .needsReinstall, !isTUN else { return }
        enqueue { manager in
            _ = await manager.helper.connect()
            if !manager.isTUN { manager.helper.disconnect() }
        }
    }

    /// Installing over a helper restarts it, so its core stops first and starts again after.
    func installHelper(prompt: String) async -> ProxyHelperInstaller.Outcome {
        await stopHelperCore()
        let outcome = await helper.install(prompt: prompt)
        enqueue { await $0.connectAfterHelperChange() }
        return outcome
    }

    /// A TUN core stops first, so the helper still puts DNS back; the proxy then runs on the port.
    func uninstallHelper(prompt: String) async -> ProxyHelperInstaller.Outcome {
        await stopHelperCore()
        let outcome = await helper.uninstall(prompt: prompt)
        enqueue { await $0.connectAfterHelperChange() }
        return outcome
    }

    private func stopHelperCore() async {
        await enqueueAndWait { manager in
            guard let running = manager.core, running.helper != nil else { return }
            await manager.stop(running, as: .starting)
        }
    }

    private func connectAfterHelperChange() async {
        await bringUp()
        if core == nil, status == .starting { status = .off }
    }

    /// The helper restarts its core itself; Tinycast follows and reapplies picks each start.
    private func helperStatusDidChange(_ helperStatus: ProxyHelperStatus) {
        guard let running = core, running.helper != nil, !running.stopping,
            helperStatus.revision >= running.statusRevision
        else { return }
        running.statusRevision = helperStatus.revision
        switch helperStatus.core {
        case .running(let since, let launch):
            guard launch != running.launch else { return }
            running.launch = launch
            appliedSelections = [:]
            status = .running(since: since)
            enqueue { manager in
                guard manager.core === running, let applied = manager.applied else { return }
                await manager.applySelections(applied.selections, on: running)
                // The helper restarted it on the last config it took, which may hold an older mode.
                await manager.applyMode()
                await manager.refresh()
            }
        case .starting, .restarting:
            status = .starting
            snapshot = nil
        case .failed(let exitStatus, let log):
            forget(running)
            status = .failed(.coreExited(status: exitStatus, log: log))
        case .stopped:
            forget(running)
            status = .off
            if store.wantsConnection { enqueue { await $0.bringUp() } }
        }
    }

    /// The helper process went away; asking for status starts it again, and it resumes the core.
    private func helperWasInterrupted() {
        guard let running = core, running.helper != nil, !running.stopping else { return }
        running.launch = 0
        running.statusRevision = -1
        status = .starting
        snapshot = nil
        enqueue { manager in
            guard manager.core === running, let connection = running.helper else { return }
            do {
                manager.helperStatusDidChange(try await connection.status())
            } catch {
                manager.forget(running)
                manager.status = .failed(.helperUnavailable)
            }
        }
    }

    // MARK: - Lifecycle

    private func enqueue(_ operation: @escaping (ProxyManager) async -> Void) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func enqueueAndWait(_ operation: @escaping (ProxyManager) async -> Void) async {
        enqueue(operation)
        await queue?.value
    }

    private func setWantsConnection(_ wants: Bool) {
        do {
            try store.setWantsConnection(wants)
        } catch {
            notice = .storage(error.localizedDescription)
        }
    }

    private func bringUp() async {
        restartTask = nil
        guard store.profile.isEnabled, store.wantsConnection else { return }
        if core != nil {
            await reconcile()
            return
        }
        status = .starting
        let bundled = ProxyCoreRunner.bundledCore
        let (resolved, retired) = await ProxyCoreInstaller.resolve(
            bundled: bundled, releases: store.releasesDirectory)
        guard let chosen = resolved else {
            activeCore = nil
            status = .failed(.coreMissing)
            return
        }
        activeCore = chosen
        let executable = chosen.executable
        let directory = store.coreDirectory
        let tunHelper = store.profile.general.usesTUN ? await helper.connect() : nil
        if tunHelper == nil { helper.disconnect() }
        let config: ProxyConfig
        let document: Data
        do {
            config = try build(tun: tunHelper != nil)
            document = try config.document.encoded()
            try await ProxyCoreRunner.check(document, core: executable)
            if tunHelper == nil { try write(document, files: config.files, to: directory) }
        } catch {
            status = .failed(Self.failure(from: error))
            return
        }
        guard store.wantsConnection, core == nil else { return }
        if let tunHelper {
            await bringUp(on: tunHelper, chosen: chosen, retired: retired, config: config, document: document)
            return
        }

        await Self.stopOrphan(in: directory, bundled: bundled, releases: store.releasesDirectory)
        let socket = runtimeDirectory.appending(path: "core.sock").path
        generation += 1
        let launched = generation
        let running: RunningCore
        do {
            try FileManager.default.createDirectory(
                at: runtimeDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try? FileManager.default.removeItem(atPath: socket)
            let onExit: @Sendable (Int32) -> Void = { [weak self] exitStatus in
                Task { @MainActor in self?.coreDidExit(exitStatus, generation: launched) }
            }
            let process = try ProxyCoreRunner.launch(
                core: executable, directory: directory, socket: socket, onExit: onExit)
            running = RunningCore(
                process: process, executable: executable, isBundled: chosen.isBundled,
                api: .unixSocket(at: socket), directory: directory, generation: launched)
            core = running
            try? String(process.processIdentifier).write(
                to: directory.appending(path: "core.pid"), atomically: true, encoding: .utf8)
        } catch {
            status = .failed(.storage(error.localizedDescription))
            return
        }

        guard await waitUntilReachable(running), core === running else {
            if core === running { await stop(running, as: .failed(.unreachable)) }
            return
        }
        await didStart(running, config: config, retired: retired)
    }

    /// The helper runs the core as root, and hands over a socket for each controller request.
    private func bringUp(
        on connection: ProxyHelperConnection, chosen: ProxyCore, retired: [ProxyCore], config: ProxyConfig,
        document: Data
    ) async {
        let options = HelperOptions(store.profile.general)
        let prepared: ProxyCore
        do {
            prepared = try await helper.prepareCore(chosen, on: connection)
            for file in config.files {
                guard let nodes = try nodes(for: file) else { continue }
                try await connection.writeFile((file.path as NSString).lastPathComponent, contents: nodes)
            }
            try await connection.start(
                document, placeholderDNS: options.placeholderDNS, outlivesClient: options.outlivesClient)
        } catch {
            status = .failed(Self.failure(from: error))
            return
        }
        guard store.wantsConnection, core == nil else {
            if core == nil { try? await connection.stop() }
            return
        }
        activeCore = prepared
        generation += 1
        let running = RunningCore(
            process: nil, helper: connection, executable: chosen.executable, isBundled: prepared.isBundled,
            api: ProxyAPIService { try await connection.openController() }, directory: store.coreDirectory,
            generation: generation)
        core = running
        appliedOptions = options
        var since = Date.now
        if let started = try? await connection.status() {
            running.statusRevision = started.revision
            if case .running(let start, let launch) = started.core {
                running.launch = launch
                since = start
            }
        }
        await didStart(running, config: config, retired: retired, since: since)
    }

    /// `since` is when the core started, which for a TUN core taken back after a quit is earlier.
    private func didStart(
        _ running: RunningCore, config: ProxyConfig, retired: [ProxyCore], since: Date = .now
    ) async {
        applied = config
        appliedSelections = [:]
        if running.helper != nil { recordLog(of: running) }
        coreVersion = try? await running.api.version()
        if activeCore?.version == nil { activeCore?.version = coreVersion.flatMap(AppVersion.init) }
        status = .running(since: since)
        await ProxyCoreInstaller.remove(retired)
        await applySelections(config.selections, on: running)
        await refresh()
    }

    /// A TUN core that outlived the last quit is taken back, or stopped when nothing wants it now.
    private func adoptHelperCore() async {
        let profile = store.profile
        let wanted = profile.isEnabled && store.wantsConnection
        guard let connection = await helper.connect() else {
            if wanted, profile.general.connectsAtLogin { await bringUp() } else { setWantsConnection(false) }
            return
        }
        let coreRuns: Bool
        switch (try? await connection.status())?.core {
        case .running, .starting, .restarting: coreRuns = true
        case .stopped, .failed, nil: coreRuns = false
        }
        if wanted, coreRuns || profile.general.connectsAtLogin {
            await bringUp()
            return
        }
        if coreRuns { try? await connection.stop() }
        helper.disconnect()
        // A launch that leaves the proxy off says so, rather than offering to disconnect it.
        setWantsConnection(false)
    }

    private func tearDown() async {
        restartTask?.cancel()
        restartTask = nil
        defer { helper.disconnect() }
        guard let running = core else {
            status = .off
            return
        }
        await stop(running, as: .off)
    }

    private func stop(_ running: RunningCore, as outcome: Status) async {
        running.stopping = true
        if let process = running.process {
            process.terminate()
            let pid = process.processIdentifier
            let deadline = Task {
                try await Task.sleep(for: .seconds(3))
                if running.exitStatus == nil { kill(pid, SIGKILL) }
            }
            await running.waitForExit()
            deadline.cancel()
            try? FileManager.default.removeItem(at: running.directory.appending(path: "core.pid"))
        } else if let connection = running.helper {
            try? await connection.stop()
        }
        guard core === running else { return }
        forget(running)
        status = outcome
    }

    private func forget(_ running: RunningCore) {
        guard core === running else { return }
        logRecorder?.cancel()
        logRecorder = nil
        core = nil
        applied = nil
        appliedOptions = nil
        appliedSelections = [:]
        snapshot = nil
        coreVersion = nil
    }

    private func coreDidExit(_ exitStatus: Int32, generation: Int) {
        guard let running = core, running.generation == generation else { return }
        running.didExit(exitStatus)
        guard !running.stopping else { return }
        Self.logger.error("Proxy core exited on its own with status \(exitStatus)")
        forget(running)
        status = .failed(.coreExited(status: exitStatus, log: ProxyCoreRunner.logTail(in: running.directory)))
        guard store.wantsConnection, let delay = restartPolicy.delay(afterExitAt: .now) else { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueue { await $0.bringUp() }
        }
    }

    private func recordLog(of running: RunningCore) {
        logRecorder?.cancel()
        let file = store.coreDirectory.appending(path: Self.tunLogName)
        let since = Date.now.formatted(date: .abbreviated, time: .standard)
        let header = String(localized: "TUN core warnings since \(since). Nothing below means none so far.")
        logRecorder = Task { [api = running.api] in
            await Self.record(api, header: header, to: file)
        }
    }

    /// Reconnects when the stream ends, as it does each time the helper restarts its core.
    @concurrent
    private static func record(_ api: ProxyAPIService, header: String, to file: URL) async {
        let files = FileManager.default
        try? files.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard
            files.createFile(
                atPath: file.path, contents: Data((header + "\n").utf8),
                attributes: [.posixPermissions: 0o600]),
            let handle = try? FileHandle(forWritingTo: file)
        else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let time = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)
        while !Task.isCancelled {
            do {
                for try await record in api.logs(level: "warning") {
                    let message = record.payload.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
                        .replacing("\n", with: "\\n")
                    let line =
                        "time=\"\(Date.now.formatted(time))\" level=\(record.type) msg=\"\(message)\"\n"
                    if ((try? handle.offset()) ?? 0) > tunLogLimit { try? handle.truncate(atOffset: 0) }
                    try? handle.write(contentsOf: Data(line.utf8))
                }
            } catch {}
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Warnings repeat for as long as a node is down, so the file starts over past this size.
    nonisolated private static let tunLogLimit: UInt64 = 8 << 20

    /// Applies the profile to a running core: selections alone if only they changed, else a reload.
    private func reconcile() async {
        guard store.profile.isEnabled else {
            await tearDown()
            return
        }
        guard let running = core, isRunning, let applied else {
            if store.wantsConnection, case .failed = status { await bringUp() }
            return
        }
        guard (running.helper != nil) == wantsTUN else {
            await stop(running, as: .starting)
            await bringUp()
            return
        }
        let config: ProxyConfig
        do {
            config = try build(tun: running.helper != nil)
        } catch {
            notice = Self.failure(from: error)
            return
        }
        let options = HelperOptions(store.profile.general)
        if config.reloadKey != applied.reloadKey || (running.helper != nil && options != appliedOptions) {
            do {
                let document = try config.document.encoded()
                try await ProxyCoreRunner.check(document, core: running.executable)
                guard core === running else { return }
                if let connection = running.helper {
                    for file in config.files {
                        guard let nodes = try nodes(for: file) else { continue }
                        try await connection.writeFile(
                            (file.path as NSString).lastPathComponent, contents: nodes)
                    }
                    try await connection.start(
                        document, placeholderDNS: options.placeholderDNS,
                        outlivesClient: options.outlivesClient)
                } else {
                    try write(document, files: config.files, to: running.directory)
                    try await running.api.reload(document)
                }
            } catch {
                if core === running { notice = Self.failure(from: error) }
                return
            }
            guard core === running else { return }
            appliedOptions = options
            appliedSelections = [:]
        }
        // Kept current without a reload too, since `refresh` applies these picks again.
        self.applied = config
        await applySelections(config.selections, on: running)
        await refresh()
    }

    /// A pick that fails, such as a node still loading, is tried again on the next refresh.
    private func applySelections(_ selections: [ProxyConfig.Selection], on running: RunningCore) async {
        for selection in selections where appliedSelections[selection.group] != selection.option {
            do {
                try await running.api.select(selection.option, in: selection.group)
            } catch {
                continue
            }
            guard core === running else { return }
            appliedSelections[selection.group] = selection.option
        }
    }

    private func applyMode() async {
        guard let running = core, isRunning else { return }
        do {
            try await running.api.setMode(store.mode.rawValue)
        } catch {
            if core === running { notice = Self.failure(from: error) }
        }
    }

    // MARK: - Core update work

    private func findCoreUpdate() async {
        do {
            let release = try await ProxyCoreDownloader.release(
                from: coreFeed, architecture: .current, proxyPort: proxyPort)
            let current = await currentCoreVersion()
            guard coreUpdate == .checking else { return }
            let isNewer = current.map { release.version > $0 } ?? true
            coreUpdate = isNewer ? .available(release) : .upToDate
        } catch {
            guard coreUpdate == .checking else { return }
            coreUpdate = .idle
            reportCoreUpdate(error)
        }
    }

    /// The running core's own answer, or else what the core a start would choose says it is.
    private func currentCoreVersion() async -> AppVersion? {
        if core != nil, let coreVersion { return AppVersion(coreVersion) }
        let resolution = await ProxyCoreInstaller.resolve(
            bundled: ProxyCoreRunner.bundledCore, releases: store.releasesDirectory)
        guard var resolved = resolution.chosen else { return nil }
        if resolved.version == nil {
            resolved.version = (try? await ProxyCoreRunner.identify(resolved.executable)).flatMap {
                AppVersion($0.tag)
            }
        }
        if core == nil { activeCore = resolved }
        return resolved.version
    }

    private func install(_ release: ProxyCoreRelease) async {
        let config = try? build().document.encoded()
        do {
            var archive: Data?
            for try await event in ProxyCoreDownloader.download(release, proxyPort: proxyPort) {
                switch event {
                case .progress(let received, let expected):
                    let fraction = expected > 0 ? min(Double(received) / Double(expected), 1) : nil
                    coreUpdate = .downloading(release, fraction: fraction)
                case .finished(let data):
                    archive = data
                }
            }
            try Task.checkCancellation()
            // The stream yields the archive or throws, so ending without one means cancellation.
            guard let archive else { throw CancellationError() }
            coreUpdate = .installing(release)
            let installed = try await ProxyCoreInstaller.install(
                archive, release: release, architecture: .current, into: store.releasesDirectory,
                checking: config)
            helper.trust(installed)
            coreUpdate = .idle
            enqueue { await $0.switchCore(to: installed.core) }
        } catch {
            guard coreUpdate != .idle else { return }
            coreUpdate = .available(release)
            reportCoreUpdate(error)
        }
    }

    /// Restarts a connected proxy on a core just installed; one that cannot start is removed again.
    private func switchCore(to installed: ProxyCore) async {
        guard store.profile.isEnabled, store.wantsConnection else {
            if core == nil { activeCore = installed }
            return
        }
        if let running = core { await stop(running, as: .starting) }
        await bringUp()
        guard activeCore?.executable == installed.executable, case .failed(let failure) = status else {
            return
        }
        switch failure {
        case .coreExited, .unreachable: break
        default: return
        }
        restartTask?.cancel()
        try? FileManager.default.removeItem(at: installed.executable.deletingLastPathComponent())
        notice = .coreDidNotStart(tag: installed.tag ?? "")
        await bringUp()
    }

    /// Release requests go through the running core, so they work where GitHub is hard to reach.
    private var proxyPort: Int? {
        isRunning ? store.profile.general.mixedPort : nil
    }

    private func reportCoreUpdate(_ error: any Error) {
        switch error {
        case is CancellationError: break
        case let failure as ProxyCoreUpdateFailure: notice = .coreUpdate(failure)
        default: notice = .coreUpdate(.storage(error.localizedDescription))
        }
    }

    // MARK: - Files

    private func build(tun: Bool = false) throws(ProxyInvalidProfile) -> ProxyConfig {
        try ProxyConfigBuilder.build(
            store.profile,
            environment: ProxyBuildEnvironment(
                mode: tun ? .tun : .portOnly, subscriptionURLs: store.subscriptionURLs(),
                ruleCatalogBase: ruleCatalogBase, proxyMode: store.mode)
        )
    }

    /// What a connection would run in: the helper only once it answered in this version.
    private var wantsTUN: Bool { store.profile.general.usesTUN && helper.state == .ready }

    /// A file source's nodes as they are now; nil for a source no longer in the profile.
    private func nodes(for file: ProxyConfig.File) throws -> Data? {
        guard let source = store.profile.sources.first(where: { $0.id == file.source }),
            case .file(let path) = source.kind
        else { return nil }
        return try Data(contentsOf: URL(filePath: (path as NSString).expandingTildeInPath))
    }

    /// The config and each file source copied in: the core reads nothing outside its directory.
    private func write(_ document: Data, files: [ProxyConfig.File], to directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory.appending(path: "providers"), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let config = directory.appending(path: "config.json")
        try document.write(to: config, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        for file in files {
            guard let nodes = try nodes(for: file) else { continue }
            try nodes.write(to: directory.appending(path: file.path), options: .atomic)
        }
    }

    /// A core left behind by a crashed Tinycast still holds the mixed port, whichever core it was.
    @concurrent
    private static func stopOrphan(in directory: URL, bundled: URL?, releases: URL) async {
        let file = directory.appending(path: "core.pid")
        defer { try? FileManager.default.removeItem(at: file) }
        guard let text = try? String(contentsOf: file, encoding: .utf8), let pid = pid_t(text), pid > 0 else {
            return
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let downloads = releases.resolvingSymlinksInPath().path + "/"
        guard path == bundled?.resolvingSymlinksInPath().path || path.hasPrefix(downloads) else { return }
        kill(pid, SIGTERM)
        for _ in 0..<20 where kill(pid, 0) == 0 { usleep(100_000) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// Gives up as soon as the core exits, rather than waiting out the ten seconds.
    private func waitUntilReachable(_ running: RunningCore) async -> Bool {
        for _ in 0..<100 {
            guard core === running else { return false }
            if (try? await running.api.version()) != nil { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @concurrent
    private static func snapshot(
        proxies: [String: ProxyAPI.Proxy], providers: [String: ProxyAPI.Provider],
        ruleProviders: [String: ProxyAPI.RuleProvider], profile: ProxyProfile
    ) async -> ProxySnapshot {
        ProxySnapshot(proxies: proxies, providers: providers, ruleProviders: ruleProviders, profile: profile)
    }

    /// The core's own message for a request it refused; a lost connection has none worth showing.
    nonisolated private static func reason(from error: any Error) -> String? {
        guard case ProxyAPIService.Failure.rejected(_, let message) = error else { return nil }
        let lines = message.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let reason = lines.filter { !$0.isEmpty }.joined(separator: " ")
        return reason.isEmpty ? nil : reason
    }

    private static func failure(from error: any Error) -> ProxyFailure {
        switch error {
        case let invalid as ProxyInvalidProfile: .invalidProfile(invalid.problems)
        case let rejection as ProxyCoreRunner.Rejection: .rejected(rejection.reason)
        case ProxyAPIService.Failure.rejected(_, let message): .rejected(message)
        case is ProxyAPIService.Failure: .unreachable
        case ProxyHelperConnection.Failure.unavailable: .helperUnavailable
        case ProxyHelperConnection.Failure.helper(let failure): failure.proxyFailure
        default: .storage(error.localizedDescription)
        }
    }
}

/// One launch of a core: Tinycast's own child or the helper's, its API, and who waits for its exit.
@MainActor
private final class RunningCore {
    /// Nil for the core the TUN helper runs as root.
    let process: Process?
    let helper: ProxyHelperConnection?
    /// The core Tinycast checks configs with, which the helper's own copy may differ from.
    let executable: URL
    let isBundled: Bool
    let api: ProxyAPIService
    let directory: URL
    let generation: Int
    var stopping = false
    /// The helper's count of core starts as last seen, which tells a restart from a repeat.
    var launch = 0
    var statusRevision = -1
    private(set) var exitStatus: Int32?
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        process: Process?, helper: ProxyHelperConnection? = nil, executable: URL, isBundled: Bool,
        api: ProxyAPIService, directory: URL, generation: Int
    ) {
        self.process = process
        self.helper = helper
        self.executable = executable
        self.isBundled = isBundled
        self.api = api
        self.directory = directory
        self.generation = generation
    }

    func didExit(_ status: Int32) {
        exitStatus = status
        for waiter in exitWaiters { waiter.resume() }
        exitWaiters = []
    }

    func waitForExit() async {
        guard exitStatus == nil else { return }
        await withCheckedContinuation { exitWaiters.append($0) }
    }
}

/// What the helper is told beside the config; a change reaches it with the config unchanged.
private struct HelperOptions: Equatable {
    var placeholderDNS: Bool
    var outlivesClient: Bool

    init(_ general: ProxyGeneral) {
        placeholderDNS = general.placeholderDNS
        outlivesClient = general.staysConnectedAfterQuit
    }
}

extension ProxyHelperFailure {
    /// What the core did, in the terms the rest of the proxy reports.
    fileprivate var proxyFailure: ProxyFailure {
        switch self {
        case .rejected(let reason): .rejected(reason)
        case .exited(let status, let log): .coreExited(status: status, log: log)
        case .unreachable: .unreachable
        default: .helper(self)
        }
    }
}
