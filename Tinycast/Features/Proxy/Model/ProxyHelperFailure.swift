import Foundation

/// Why the helper turned a request down, carried back across XPC as JSON.
enum ProxyHelperFailure: Error, Codable, Equatable, Sendable {
    /// The request broke the helper's rules, such as a file name or a config key it never takes.
    case refused(String)
    /// No verified core is installed, or the copy no longer matches the one verified.
    case noCore
    case digestMismatch
    /// A core said to ship with Tinycast is not signed as Tinycast's.
    case unsigned
    /// `-v` did not describe a mihomo build for this Mac.
    case notCore(String)
    case storage(String)
    /// The core exited while starting.
    case exited(status: Int32, log: String)
    case unreachable
    /// The running core refused a config, in its own words.
    case rejected(String)

    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// A reply the helper could not have sent reads as the helper not answering properly.
    init(decoding data: Data) {
        self = (try? JSONDecoder().decode(Self.self, from: data)) ?? .refused("unreadable reply")
    }
}
