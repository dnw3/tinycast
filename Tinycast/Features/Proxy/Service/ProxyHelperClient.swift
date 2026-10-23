import CryptoKit
import Foundation

/// Tinycast's side of the TUN helper: whether it can be used, the line to it, and the core it runs.
@MainActor
@Observable
final class ProxyHelperClient {
    enum State: Equatable, Sendable {
        /// This build ships no helper, or carries no certificate a requirement could pin.
        case unsupported
        case notInstalled
        /// Installed and answering in this version.
        case ready
        /// Installed, but answering in another version or not at all; installing again fixes both.
        case needsReinstall
    }

    private(set) var state = State.unsupported
    private(set) var isInstalling = false

    @ObservationIgnored let layout: ProxyHelperLayout?
    @ObservationIgnored private lazy var grant = layout.flatMap(ProxyHelperInstaller.grant(for:))
    @ObservationIgnored private var connection: ProxyHelperConnection?
    /// Digests taken in memory while downloading, the only ones a download is handed over with.
    @ObservationIgnored private var verifiedDownloads: [String: String] = [:]
    @ObservationIgnored private var bundledDigest: (path: String, sha256: String)?
    @ObservationIgnored var onStatus: ((ProxyHelperStatus) -> Void)?
    /// The helper process went away; the next call starts it again.
    @ObservationIgnored var onInterruption: (() -> Void)?

    init(appIdentifier: String? = Bundle.main.bundleIdentifier) {
        layout = appIdentifier.flatMap { ProxyHelperLayout(appIdentifier: $0) }
        refresh()
    }

    /// What the files on disk say; only a handshake tells a stale or silent helper apart.
    func refresh() {
        guard let layout, grant != nil, ProxyHelperInstaller.bundledHelper != nil else {
            state = .unsupported
            return
        }
        guard ProxyHelperInstaller.isInstalled(layout) else {
            state = .notInstalled
            return
        }
        if state != .needsReinstall { state = .ready }
    }

    /// A line to a helper speaking this version, or nil; `state` says which it was.
    func connect() async -> ProxyHelperConnection? {
        refresh()
        guard state == .ready || state == .needsReinstall, let layout, let grant else { return nil }
        let connection = self.connection ?? makeConnection(layout: layout, grant: grant)
        self.connection = connection
        let version = try? await connection.handshake()
        state = version == ProxyHelperWire.version ? .ready : .needsReinstall
        return state == .ready ? connection : nil
    }

    /// Lets a helper with nothing to run exit; the next `connect()` starts it again.
    func disconnect() {
        connection?.close()
        connection = nil
    }

    func trust(_ installed: ProxyCoreInstaller.Installed) {
        guard let tag = installed.core.tag else { return }
        verifiedDownloads[tag] = installed.sha256
    }

    /// A download goes over only with this run's digest; the bundled core also by signature.
    func prepareCore(_ chosen: ProxyCore, on connection: ProxyHelperConnection) async throws -> ProxyCore {
        let installed = try await connection.status().installed
        if !chosen.isBundled, let tag = chosen.tag {
            if installed?.tag == tag { return chosen }
            if let digest = verifiedDownloads[tag] {
                try await hand(chosen.executable, sha256: digest, signed: false, over: connection)
                return chosen
            }
        }
        guard let bundled = ProxyCoreRunner.bundledCore else {
            guard installed != nil else { throw ProxyHelperConnection.Failure.helper(.noCore) }
            return chosen
        }
        let digest = await sha256(ofBundled: bundled)
        if installed?.sha256 != digest {
            try await hand(bundled, sha256: digest, signed: true, over: connection)
        }
        return chosen.isBundled ? chosen : ProxyCore(executable: bundled, version: nil, isBundled: true)
    }

    // MARK: - Installing

    func install(prompt: String) async -> ProxyHelperInstaller.Outcome {
        guard let layout, let grant else {
            return .failed(String(localized: "This build cannot install the TUN helper."))
        }
        isInstalling = true
        defer { isInstalling = false }
        disconnect()
        let outcome = await ProxyHelperInstaller.install(layout, grant: grant, prompt: prompt)
        if outcome == .done { state = .notInstalled }
        refresh()
        return outcome
    }

    func uninstall(prompt: String) async -> ProxyHelperInstaller.Outcome {
        guard let layout else { return .done }
        isInstalling = true
        defer { isInstalling = false }
        disconnect()
        let outcome = await ProxyHelperInstaller.uninstall(layout, prompt: prompt)
        if outcome == .done { state = .notInstalled }
        refresh()
        return outcome
    }

    // MARK: - Plumbing

    private func makeConnection(layout: ProxyHelperLayout, grant: ProxyHelperGrant) -> ProxyHelperConnection {
        ProxyHelperConnection(
            layout: layout, grant: grant,
            onStatus: { [weak self] status in Task { @MainActor in self?.onStatus?(status) } },
            onInterruption: { [weak self] in Task { @MainActor in self?.onInterruption?() } })
    }

    /// The helper reads to the end itself; the digest, not the path, says which bytes it accepts.
    private func hand(
        _ executable: URL, sha256: String, signed: Bool, over connection: ProxyHelperConnection
    ) async throws {
        let file = try FileHandle(forReadingFrom: executable)
        defer { try? file.close() }
        try await connection.installCore(file, sha256: sha256, signed: signed)
    }

    private func sha256(ofBundled core: URL) async -> String {
        if let bundledDigest, bundledDigest.path == core.path { return bundledDigest.sha256 }
        let digest = await Self.sha256(of: core)
        bundledDigest = (core.path, digest)
        return digest
    }

    @concurrent
    private static func sha256(of file: URL) async -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
