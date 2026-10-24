import Foundation

/// The proxy's persisted state: profile, mode, whether to stay connected, and subscription links.
@MainActor
@Observable
final class ProxyStore {
    private struct Document: Codable {
        var profile: ProxyProfile
        var connected: Bool
        /// Absent from a file written before modes existed, which ran by the rules.
        var mode: ProxyMode?
    }

    private(set) var profile: ProxyProfile
    /// Whether the user last left it connected, which the next launch restores.
    private(set) var wantsConnection: Bool
    private(set) var mode: ProxyMode
    /// A damaged file was set aside and the starter profile took its place.
    private(set) var recoveredDamagedFile = false

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let secrets: KeychainSecretStore
    /// Whether each source has a link, read from the keychain once rather than on every render.
    @ObservationIgnored private var linkKnown: [UUID: Bool] = [:]

    init(
        directory: URL = AppPaths.applicationSupport().appending(path: "Proxy", directoryHint: .isDirectory),
        secrets: KeychainSecretStore = .proxySubscriptions
    ) {
        self.directory = directory
        self.secrets = secrets
        let file = directory.appending(path: "profile.json")
        if let data = try? Data(contentsOf: file) {
            if let document = try? JSONDecoder().decode(Document.self, from: data) {
                profile = document.profile
                wantsConnection = document.connected
                mode = document.mode ?? .rule
                return
            }
            try? FileManager.default.removeItem(at: file.appendingPathExtension("damaged"))
            try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("damaged"))
            recoveredDamagedFile = true
        }
        profile = Self.starter()
        wantsConnection = false
        mode = .rule
    }

    /// The core's own directory for a user-level run: its config, caches and log.
    var coreDirectory: URL { directory.appending(path: "Core", directoryHint: .isDirectory) }

    /// Downloaded cores, one `<tag>/mihomo` each; kept out of the core's own directory.
    var releasesDirectory: URL { directory.appending(path: "Releases", directoryHint: .isDirectory) }

    /// Where a new local node file goes when the user does not choose a place.
    var nodesDirectory: URL { directory.appending(path: "Nodes", directoryHint: .isDirectory) }

    /// Saved first, so memory never holds a profile the disk does not.
    func update(_ change: (inout ProxyProfile) -> Void) throws {
        var profile = profile
        change(&profile)
        try save(Document(profile: profile, connected: wantsConnection, mode: mode))
        self.profile = profile
    }

    func setWantsConnection(_ wants: Bool) throws {
        guard wants != wantsConnection else { return }
        try save(Document(profile: profile, connected: wants, mode: mode))
        wantsConnection = wants
    }

    func setMode(_ mode: ProxyMode) throws {
        guard mode != self.mode else { return }
        try save(Document(profile: profile, connected: wantsConnection, mode: mode))
        self.mode = mode
    }

    func subscriptionURL(for source: UUID) -> String? {
        try? secrets.secret(for: source)
    }

    func setSubscriptionURL(_ url: String, for source: UUID) throws {
        try secrets.setSecret(url, for: source)
        linkKnown[source] = true
    }

    func removeSubscriptionURL(for source: UUID) throws {
        try secrets.removeSecret(for: source)
        linkKnown[source] = false
    }

    func hasSubscriptionURL(for source: UUID) -> Bool {
        if let known = linkKnown[source] { return known }
        let known = subscriptionURL(for: source) != nil
        linkKnown[source] = known
        return known
    }

    /// Every enabled subscription's link the keychain can read; the builder reports the rest.
    func subscriptionURLs() -> [UUID: String] {
        var urls: [UUID: String] = [:]
        for source in profile.sources where source.isEnabled && source.kind == .subscription {
            urls[source.id] = subscriptionURL(for: source.id)
        }
        return urls
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: directory.appending(path: "profile.json"), options: .atomic)
    }

    private static func starter() -> ProxyProfile {
        ProxyProfile.starter(
            defaultName: String(localized: "Default Proxy"), fastestName: String(localized: "Fastest"),
            newID: UUID.init)
    }
}
