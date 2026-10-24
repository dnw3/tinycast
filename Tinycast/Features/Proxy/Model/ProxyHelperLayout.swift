import Foundation

/// Where one channel's TUN helper and its root-owned files live; the label tells them apart.
struct ProxyHelperLayout: Equatable, Sendable {
    static let suffix = ".proxy-helper"
    static let toolsDirectory = "/Library/PrivilegedHelperTools"
    static let daemonsDirectory = "/Library/LaunchDaemons"
    static let supportDirectory = "/Library/Application Support/Tinycast"

    let label: String
    /// Root-owned and 0700: the helper reads and writes nothing outside it.
    let root: String

    init?(appIdentifier: String, root: String? = nil) {
        guard ProxyHelperGrant.isIdentifier(appIdentifier) else { return nil }
        label = appIdentifier + Self.suffix
        self.root = root ?? Self.supportDirectory + "/" + label
    }

    /// Recovered from the helper's own path, which the installer names after the label.
    init?(executablePath: String) {
        let name = (executablePath as NSString).lastPathComponent
        guard name.hasSuffix(Self.suffix), executablePath == Self.toolsDirectory + "/" + name else {
            return nil
        }
        self.init(appIdentifier: String(name.dropLast(Self.suffix.count)))
    }

    var appIdentifier: String { String(label.dropLast(Self.suffix.count)) }
    var executable: String { Self.toolsDirectory + "/" + label }
    var launchdPlist: String { Self.daemonsDirectory + "/" + label + ".plist" }

    var coreDirectory: String { root + "/core" }
    var core: String { coreDirectory + "/mihomo" }
    var config: String { root + "/config.json" }
    var providers: String { root + "/providers" }
    /// Only root may enter it, so only root can reach the core's controller.
    var socketDirectory: String { root + "/run" }
    var socket: String { socketDirectory + "/core.sock" }
    var record: String { root + "/record.json" }
    var grant: String { root + "/grant.json" }
    var log: String { root + "/core.log" }
    var corePID: String { root + "/core.pid" }

    /// Runs once at load to put back DNS a crash left set; afterwards on demand, and after a crash.
    var launchdJob: [String: Any] {
        [
            "Label": label, "ProgramArguments": [executable], "MachServices": [label: true],
            "KeepAlive": ["SuccessfulExit": false], "AssociatedBundleIdentifiers": [appIdentifier]
        ]
    }
}
