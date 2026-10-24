import Foundation

/// Installs and removes the TUN helper behind macOS's own administrator prompt.
enum ProxyHelperInstaller {
    enum Outcome: Equatable, Sendable {
        case done
        /// The prompt's Cancel button, which is no failure.
        case cancelled
        case failed(String)
    }

    /// Absent from a build whose helper target was not embedded.
    static var bundledHelper: URL? {
        let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/TinycastProxyHelper")
        return FileManager.default.isExecutableFile(atPath: helper.path) ? helper : nil
    }

    /// Tinycast's own signer and user; nil for a build no requirement can pin, like ad-hoc.
    static func grant(for layout: ProxyHelperLayout) -> ProxyHelperGrant? {
        guard let signer = ProxyCodeSignature.current(), signer.identifier == layout.appIdentifier else {
            return nil
        }
        let grant = ProxyHelperGrant(
            appIdentifier: layout.appIdentifier, leafHash: signer.leafHash, uid: getuid())
        return grant.isValid ? grant : nil
    }

    static func isInstalled(_ layout: ProxyHelperLayout) -> Bool {
        FileManager.default.fileExists(atPath: layout.launchdPlist)
            && FileManager.default.isExecutableFile(atPath: layout.executable)
    }

    static func install(_ layout: ProxyHelperLayout, grant: ProxyHelperGrant, prompt: String) async -> Outcome
    {
        guard let helper = bundledHelper,
            let script = ProxyHelperScript.install(
                bundledHelper: helper.path, layout: layout, grant: grant, prompt: prompt)
        else { return .failed(String(localized: "This build has no TUN helper.")) }
        return await run(script)
    }

    static func uninstall(_ layout: ProxyHelperLayout, prompt: String) async -> Outcome {
        await run(ProxyHelperScript.uninstall(layout: layout, prompt: prompt))
    }

    /// The system shows the password prompt itself; -128 is its Cancel button.
    private static func run(_ script: String) async -> Outcome {
        do {
            let result = try await ToolRunner.run(
                URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script], timeout: nil)
            if result.succeeded { return .done }
            return result.output.contains("-128") ? .cancelled : .failed(result.tail)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
