import Foundation

/// The DNS servers the placeholder replaced on one network service, kept until they are put back.
struct ProxyDNSBackup: Codable, Equatable, Sendable {
    /// A public resolver: queries to it enter the TUN device, and it still works if left behind.
    static let placeholder = ["223.5.5.5"]

    /// The SystemConfiguration service ID, which survives the service being renamed.
    var serviceID: String
    /// Nil when the service had none of its own and used the network's.
    var servers: [String]?

    enum Restoration: Equatable, Sendable {
        case restore([String]?)
        /// Someone set other servers since, and theirs win.
        case leave
    }

    func restoration(current: [String]?) -> Restoration {
        current == Self.placeholder ? .restore(servers) : .leave
    }
}
