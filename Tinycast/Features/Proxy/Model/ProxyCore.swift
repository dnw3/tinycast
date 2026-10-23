import Foundation

/// A core binary Tinycast can run: the one in the app bundle, or an official release it downloaded.
struct ProxyCore: Equatable, Sendable {
    var executable: URL
    /// Unknown for a bundled core nobody has asked yet; a download is named for its release.
    var version: AppVersion?
    var isBundled: Bool

    /// The tag the core reports for itself, such as `v1.19.32`.
    var tag: String? { version.map { "v\($0)" } }

    /// The first line `mihomo -v` prints: `Mihomo Meta v1.19.32 darwin arm64 with go1.26.8 …`.
    struct Identity: Equatable, Sendable {
        var tag: String
        /// Go's name for it: `arm64` or `amd64`.
        var architecture: String

        init(tag: String, architecture: String) {
            self.tag = tag
            self.architecture = architecture
        }

        init?(versionOutput: String) {
            let words = versionOutput.split(whereSeparator: \.isWhitespace)
            guard let meta = words.firstIndex(of: "Meta"), meta + 3 < words.count, words[meta + 2] == "darwin"
            else { return nil }
            tag = String(words[meta + 1])
            architecture = String(words[meta + 3])
        }

        /// What an official build for this Mac reports.
        static func expected(tag: String, architecture: ReleaseArchitecture) -> Identity {
            Identity(tag: tag, architecture: architecture == .appleSilicon ? "arm64" : "amd64")
        }
    }

    /// The newest core, the signed bundled one winning a tie, and the downloads it retires.
    static func choose(
        bundled: ProxyCore?, downloads: [ProxyCore]
    ) -> (chosen: ProxyCore?, retired: [ProxyCore]) {
        let ranked = downloads.compactMap { core in core.version.map { (core, $0) } }.sorted { $0.1 > $1.1 }
        guard let (newest, version) = ranked.first else { return (bundled, []) }
        if let bundled, let shipped = bundled.version, shipped >= version {
            return (bundled, ranked.map(\.0))
        }
        return (newest, ranked.dropFirst().map(\.0))
    }
}
