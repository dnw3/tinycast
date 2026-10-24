import Foundation

/// Why a core release was not installed; the core already in use is left as it was.
enum ProxyCoreUpdateFailure: Error, Equatable, Sendable {
    /// The request did not complete, in the system's words.
    case unreachable(String)
    /// GitHub counts anonymous requests per address, and a busy proxy exit can use them all up.
    case rateLimited
    /// The feed holds no stable release this build can read.
    case noRelease
    /// The release has no build for this Mac.
    case noAsset
    /// The release publishes no SHA-256, so nothing could prove the download intact.
    case unverifiable
    case checksumMismatch
    /// Not a gzip stream, though it matched its digest.
    case damaged
    /// The binary named another version or architecture than its release, in its own words.
    case wrongIdentity(String)
    /// The new core refused the current config, in its own words.
    case rejected(String)
    case storage(String)
}
