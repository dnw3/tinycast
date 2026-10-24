import CryptoKit
import Foundation

/// An official mihomo release with a build for this Mac, and the SHA-256 GitHub publishes for it.
struct ProxyCoreRelease: Equatable, Sendable {
    var version: AppVersion
    var tag: String
    var assetURL: URL
    var assetSize: Int64
    /// Lowercase hex digest of the gzip archive.
    var sha256: String

    static let feed = URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")!

    /// The names `Scripts/fetch-mihomo.sh` uses too; Intel takes the build for any x86-64 CPU.
    static func assetName(tag: String, architecture: ReleaseArchitecture) -> String {
        switch architecture {
        case .appleSilicon: "mihomo-darwin-arm64-\(tag).gz"
        case .intel: "mihomo-darwin-amd64-compatible-\(tag).gz"
        }
    }

    /// The release a `releases/latest` or `releases/tags/…` body describes.
    static func parse(
        _ data: Data, architecture: ReleaseArchitecture
    ) throws(ProxyCoreUpdateFailure) -> ProxyCoreRelease {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data), !entry.draft, !entry.prerelease,
            let version = AppVersion(entry.tagName), !version.isPrerelease
        else { throw .noRelease }
        let name = assetName(tag: entry.tagName, architecture: architecture)
        guard let asset = entry.assets.first(where: { $0.name == name }),
            ProxyText.isWebURL(asset.browserDownloadURL), let url = URL(string: asset.browserDownloadURL)
        else { throw .noAsset }
        let digest = asset.digest?.lowercased() ?? ""
        let hex = digest.dropFirst(Self.digestPrefix.count)
        guard digest.hasPrefix(Self.digestPrefix), hex.count == 64, hex.allSatisfy(\.isHexDigit) else {
            throw .unverifiable
        }
        return ProxyCoreRelease(
            version: version, tag: entry.tagName, assetURL: url, assetSize: asset.size, sha256: String(hex))
    }

    /// The archive is the one GitHub published, so its own CRC and length need no second check.
    func verify(_ archive: Data) throws(ProxyCoreUpdateFailure) {
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw .checksumMismatch }
    }

    private static let digestPrefix = "sha256:"

    private struct Entry: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }

        struct Asset: Decodable {
            let name: String
            let size: Int64
            let digest: String?
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name, size, digest
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
