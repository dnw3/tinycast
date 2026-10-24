import CryptoKit
import Foundation

/// The cores on disk: installs a verified release beside the bundled core and picks one to run.
enum ProxyCoreInstaller {
    /// The binary inside each `<releases>/<tag>/` directory.
    static let binaryName = "mihomo"
    /// Over four times the 57 MB core; the digest, checked first, already rules out a bomb.
    static let maxBinarySize = 256 * 1024 * 1024

    /// The newest core and the downloads it makes redundant; `-v` runs only if a download exists.
    @concurrent
    static func resolve(bundled: URL?, releases: URL) async -> (chosen: ProxyCore?, retired: [ProxyCore]) {
        var shipped = bundled.map { ProxyCore(executable: $0, version: nil, isBundled: true) }
        let downloads = installed(in: releases)
        guard !downloads.isEmpty else { return (shipped, []) }
        if let bundled, let identity = try? await ProxyCoreRunner.identify(bundled) {
            shipped?.version = AppVersion(identity.tag)
        }
        return ProxyCore.choose(bundled: shipped, downloads: downloads)
    }

    /// Called once the chosen core runs, so a new core that cannot start has one to fall back on.
    @concurrent
    static func remove(_ cores: [ProxyCore]) async {
        for core in cores where !core.isBundled {
            try? FileManager.default.removeItem(at: core.executable.deletingLastPathComponent())
        }
    }

    /// Every complete download, named for its release; a directory of another name is never run.
    static func installed(in releases: URL) -> [ProxyCore] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: releases.path)) ?? []
        return names.compactMap { name in
            guard let version = AppVersion(name), name == "v\(version)" else { return nil }
            let executable = releases.appending(path: name).appending(path: binaryName)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
            return ProxyCore(executable: executable, version: version, isBundled: false)
        }
    }

    /// A core just installed, with its digest taken in memory: the copy on disk could change later.
    struct Installed: Equatable, Sendable {
        var core: ProxyCore
        var sha256: String
    }

    /// Only a binary that is the release it claims and accepts `config` takes the release's place.
    @concurrent
    static func install(
        _ archive: Data, release: ProxyCoreRelease, architecture: ReleaseArchitecture, into releases: URL,
        checking config: Data?
    ) async throws -> Installed {
        try release.verify(archive)
        let binary: Data
        do {
            binary = try Zlib.gunzip(archive, maxOutput: maxBinarySize)
        } catch {
            throw ProxyCoreUpdateFailure.damaged
        }
        let sha256 = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        let manager = FileManager.default
        let staging = releases.appending(path: ".staging", directoryHint: .isDirectory)
        let executable = staging.appending(path: binaryName)
        do {
            try manager.createDirectory(
                at: releases, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? manager.removeItem(at: staging)
            try manager.createDirectory(
                at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try binary.write(to: executable)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            throw ProxyCoreUpdateFailure.storage(error.localizedDescription)
        }
        defer { try? manager.removeItem(at: staging) }

        let identity: ProxyCore.Identity
        do {
            identity = try await ProxyCoreRunner.identify(executable)
        } catch is CancellationError {
            throw CancellationError()
        } catch let rejection as ProxyCoreRunner.Rejection {
            throw ProxyCoreUpdateFailure.wrongIdentity(rejection.reason)
        } catch {
            throw ProxyCoreUpdateFailure.wrongIdentity(error.localizedDescription)
        }
        guard identity == ProxyCore.Identity.expected(tag: release.tag, architecture: architecture) else {
            throw ProxyCoreUpdateFailure.wrongIdentity("\(identity.tag) \(identity.architecture)")
        }
        if let config {
            do {
                try await ProxyCoreRunner.check(config, core: executable)
            } catch let rejection as ProxyCoreRunner.Rejection {
                throw ProxyCoreUpdateFailure.rejected(rejection.reason)
            }
        }

        let destination = releases.appending(path: release.tag, directoryHint: .isDirectory)
        do {
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: staging, to: destination)
        } catch {
            throw ProxyCoreUpdateFailure.storage(error.localizedDescription)
        }
        let core = ProxyCore(
            executable: destination.appending(path: binaryName), version: release.version, isBundled: false)
        return Installed(core: core, sha256: sha256)
    }
}
